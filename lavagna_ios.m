#import <UIKit/UIKit.h>

#include <math.h>

#import "lavagna_metal.h"

enum {
    ZOOM_UNIT = 1000,
    FRAME_RATE_MAX = 120,
    HID_A = 0x04,
    HID_Z = 0x1d,
    HID_1 = 0x1e,
    HID_0 = 0x27,
    HID_F1 = 0x3a,
    HID_F12 = 0x45,
    HID_MAX = 0xe8,
};

/* One app, one lavagna. */
static lavagna the_lv;

/* Indexed by USB HID keyboard usage (UIKeyboardHIDUsage). Letters, digits
   and F-keys are ranges, filled in key_of. */
static const uint16_t hidmap[HID_MAX] = {
    [0x28] = LAV_KEY_ENTER,
    [0x29] = LAV_KEY_ESCAPE,
    [0x2a] = LAV_KEY_BACKSPACE,
    [0x2b] = LAV_KEY_TAB,
    [0x2c] = ' ',
    [0x2d] = '-',
    [0x2e] = '=',
    [0x2f] = '[',
    [0x30] = ']',
    [0x31] = '\\',
    [0x33] = ';',
    [0x34] = '\'',
    [0x35] = '`',
    [0x36] = ',',
    [0x37] = '.',
    [0x38] = '/',
    [0x4a] = LAV_KEY_HOME,
    [0x4b] = LAV_KEY_PAGE_UP,
    [0x4c] = LAV_KEY_DELETE,
    [0x4d] = LAV_KEY_END,
    [0x4e] = LAV_KEY_PAGE_DOWN,
    [0x4f] = LAV_KEY_RIGHT,
    [0x50] = LAV_KEY_LEFT,
    [0x51] = LAV_KEY_DOWN,
    [0x52] = LAV_KEY_UP,
    [0xe0] = LAV_KEY_CTRL,
    [0xe1] = LAV_KEY_SHIFT,
    [0xe2] = LAV_KEY_ALT,
    [0xe3] = LAV_KEY_CMD,
    [0xe4] = LAV_KEY_CTRL,
    [0xe5] = LAV_KEY_SHIFT,
    [0xe6] = LAV_KEY_ALT,
    [0xe7] = LAV_KEY_CMD,
};

static uint32_t key_of(long hid) {
    if (hid >= HID_A && hid <= HID_Z) {
        return (uint32_t)('a' + (hid - HID_A));
    }
    if (hid >= HID_1 && hid < HID_0) {
        return (uint32_t)('1' + (hid - HID_1));
    }
    if (hid == HID_0) {
        return '0';
    }
    if (hid >= HID_F1 && hid <= HID_F12) {
        return (uint32_t)(LAV_KEY_F1 + (hid - HID_F1));
    }
    if (hid > 0 && hid < HID_MAX) {
        return hidmap[hid];
    }
    return 0;
}

static uint32_t mods_of(UIKeyModifierFlags f) {
    uint32_t m = 0;
    m |= (f & UIKeyModifierShift) != 0 ? LAV_MOD_SHIFT : 0;
    m |= (f & UIKeyModifierControl) != 0 ? LAV_MOD_CTRL : 0;
    m |= (f & UIKeyModifierAlternate) != 0 ? LAV_MOD_ALT : 0;
    m |= (f & UIKeyModifierCommand) != 0 ? LAV_MOD_CMD : 0;
    return m;
}

static UIWindow *window_of(const lavagna *lv) {
    return (__bridge UIWindow *)lv->window;
}

void lav_set_title(lavagna *lv, const char *title) {
    window_of(lv).windowScene.title = @(title);
}

void lav_cursor(lavagna *lv, lav_cursor_kind kind) {
    lv->cursor = kind;
}

@interface LavView : UIView
- (void)tick:(CADisplayLink *)link;
@end

@implementation LavView {
    lavagna *_lv;
    LavRenderer *_renderer;
    CADisplayLink *_link;
    UITouch *_primary;
    CGFloat _pinch_last;
    CGPoint _pan_last;
    double _zoom;
}

+ (Class)layerClass {
    return [CAMetalLayer class];
}

- (instancetype)initWithFrame:(CGRect)frame lavagna:(lavagna *)lv {
    self = [super initWithFrame:frame];
    if (self == nil) {
        return nil;
    }
    _lv = lv;
    _renderer = [[LavRenderer alloc] initWithLayer:(CAMetalLayer *)self.layer];
    self.multipleTouchEnabled = YES;
    /* Two fingers pan and pinch; the Pencil only ever draws. */
    NSArray *fingers = @[ @(UITouchTypeDirect) ];
    UIPinchGestureRecognizer *pinch =
        [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinch:)];
    pinch.allowedTouchTypes = fingers;
    [self addGestureRecognizer:pinch];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                          action:@selector(pan:)];
    pan.minimumNumberOfTouches = 2;
    pan.maximumNumberOfTouches = 2;
    pan.allowedTouchTypes = fingers;
    pan.allowedScrollTypesMask = UIScrollTypeMaskAll;
    [self addGestureRecognizer:pan];
    UIHoverGestureRecognizer *hover =
        [[UIHoverGestureRecognizer alloc] initWithTarget:self action:@selector(hover:)];
    [self addGestureRecognizer:hover];
    return self;
}

- (BOOL)canBecomeFirstResponder {
    return YES;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window == nil || _link != nil) {
        return;
    }
    [self becomeFirstResponder];
    _link = [self.window.screen displayLinkWithTarget:self selector:@selector(tick:)];
    _link.preferredFrameRateRange = CAFrameRateRangeMake(30, FRAME_RATE_MAX, FRAME_RATE_MAX);
    [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)syncSize {
    CAMetalLayer *layer = _renderer.layer;
    CGFloat s = self.window.screen.scale;
    CGSize pt = self.bounds.size;
    CGSize px = CGSizeMake(fmax(1, floor(pt.width * s)), fmax(1, floor(pt.height * s)));
    if (CGSizeEqualToSize(px, layer.drawableSize) && layer.contentsScale == s) {
        return;
    }
    self.contentScaleFactor = s;
    layer.contentsScale = s;
    layer.drawableSize = px;
    _lv->device_scale = (int32_t)lround(s);
    (void)lavagna_layout(_lv, (int32_t)px.width, (int32_t)px.height);
}

- (void)tick:(CADisplayLink *)link {
    (void)link;
    [self syncSize];
    _lv->frame_ns = lavagna_now_ns();
    _lv->frames++;
    if (_lv->replay != NULL) {
        (void)lavagna_replay(_lv, 0);
    }
    lav_frame(_lv, _lv->cfg.user);
    if (_lv->replay != NULL && lavagna_replay(_lv, 1)) {
        exit(0);
    }
    [_renderer render:_lv];
}

- (lav_event)at:(CGPoint)p type:(lav_event_type)t {
    CGFloat s = self.window.screen.scale;
    return (lav_event){
        .type = t,
        .time_ns = lavagna_now_ns(),
        .x = (int32_t)floor((p.x * s - _lv->offx) / _lv->scale),
        .y = (int32_t)floor((p.y * s - _lv->offy) / _lv->scale),
    };
}

- (void)touch:(UITouch *)t event:(UIEvent *)e type:(lav_event_type)type {
    lav_event ev = [self at:[t preciseLocationInView:self] type:type];
    ev.time_ns = (uint64_t)(t.timestamp * 1e9);
    ev.mods = mods_of(e.modifierFlags);
    ev.button = (e.buttonMask & UIEventButtonMaskSecondary) != 0 ? LAV_BUTTON_SECONDARY
                                                                 : LAV_BUTTON_PRIMARY;
    switch (t.type) {
    case UITouchTypePencil:
        ev.pointer = LAV_POINTER_PEN;
        break;
    case UITouchTypeIndirectPointer:
        ev.pointer = LAV_POINTER_MOUSE;
        break;
    default:
        ev.pointer = LAV_POINTER_TOUCH;
        break;
    }
    if (type != LAV_EV_POINTER_UP && type != LAV_EV_POINTER_CANCEL) {
        double pr = 1;
        if (t.type == UITouchTypePencil && t.maximumPossibleForce > 0) {
            pr = fmin(fmax(t.force / t.maximumPossibleForce, 0), 1);
        }
        ev.pressure = (uint32_t)lround(pr * (double)LAV_PRESSURE_MAX);
    }
    lavagna_push(_lv, ev);
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)e {
    if (_primary != nil) {
        return;
    }
    _primary = touches.anyObject;
    [self touch:_primary event:e type:LAV_EV_POINTER_DOWN];
}

/* Every sample the touch made since the last frame, not just the last. */
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)e {
    if (_primary == nil || ![touches containsObject:_primary]) {
        return;
    }
    for (UITouch *t in [e coalescedTouchesForTouch:_primary]) {
        [self touch:t event:e type:LAV_EV_POINTER_MOVE];
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)e {
    if (_primary == nil || ![touches containsObject:_primary]) {
        return;
    }
    [self touch:_primary event:e type:LAV_EV_POINTER_UP];
    _primary = nil;
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)e {
    if (_primary == nil || ![touches containsObject:_primary]) {
        return;
    }
    [self touch:_primary event:e type:LAV_EV_POINTER_CANCEL];
    _primary = nil;
}

- (void)hover:(UIHoverGestureRecognizer *)g {
    lav_event ev = [self at:[g locationInView:self] type:LAV_EV_POINTER_MOVE];
    ev.pointer = LAV_POINTER_PEN;
    lavagna_push(_lv, ev);
}

- (void)pinch:(UIPinchGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) {
        _pinch_last = g.scale;
        return;
    }
    if (g.state != UIGestureRecognizerStateChanged) {
        return;
    }
    _zoom += (g.scale - _pinch_last) * (double)ZOOM_UNIT;
    _pinch_last = g.scale;
    lav_event ev = [self at:[g locationInView:self] type:LAV_EV_PINCH];
    ev.zoom = (int32_t)trunc(_zoom);
    _zoom -= ev.zoom;
    if (ev.zoom != 0) {
        lavagna_push(_lv, ev);
    }
}

- (void)pan:(UIPanGestureRecognizer *)g {
    CGPoint tr = [g translationInView:self];
    if (g.state == UIGestureRecognizerStateBegan) {
        _pan_last = tr;
        return;
    }
    if (g.state != UIGestureRecognizerStateChanged) {
        return;
    }
    CGFloat s = self.window.screen.scale;
    lav_event ev = [self at:[g locationInView:self] type:LAV_EV_SCROLL];
    ev.scroll_x = (int32_t)lround((tr.x - _pan_last.x) * s / _lv->scale);
    ev.scroll_y = (int32_t)lround((tr.y - _pan_last.y) * s / _lv->scale);
    _pan_last.x += ev.scroll_x * _lv->scale / s;
    _pan_last.y += ev.scroll_y * _lv->scale / s;
    if (ev.scroll_x != 0 || ev.scroll_y != 0) {
        lavagna_push(_lv, ev);
    }
}

- (void)presses:(NSSet<UIPress *> *)presses type:(lav_event_type)type {
    for (UIPress *p in presses) {
        uint32_t k = p.key != nil ? key_of(p.key.keyCode) : 0;
        if (k == 0) {
            continue;
        }
        lavagna_push(_lv, (lav_event){
                              .type = type,
                              .mods = mods_of(p.key.modifierFlags),
                              .time_ns = (uint64_t)(p.timestamp * 1e9),
                              .key = k,
                          });
    }
}

- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)e {
    (void)e;
    [self presses:presses type:LAV_EV_KEY_DOWN];
}

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)e {
    (void)e;
    [self presses:presses type:LAV_EV_KEY_UP];
}

@end

@interface LavController : UIViewController
@end

@implementation LavController

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    return YES;
}

@end

@interface LavSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation LavSceneDelegate

- (void)scene:(UIScene *)scene
    willConnectToSession:(UISceneSession *)session
                 options:(UISceneConnectionOptions *)options {
    (void)session;
    (void)options;
    UIWindowScene *ws = (UIWindowScene *)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:ws];
    LavController *c = [LavController new];
    c.view = [[LavView alloc] initWithFrame:ws.coordinateSpace.bounds lavagna:&the_lv];
    self.window.rootViewController = c;
    the_lv.window = (__bridge void *)self.window;
    ws.title = @(the_lv.cfg.title);
    [self.window makeKeyAndVisible];
}

/* One frame runs now, so the program saves before iOS may end it. */
- (void)sceneDidEnterBackground:(UIScene *)scene {
    (void)scene;
    lavagna_push(&the_lv, (lav_event){.type = LAV_EV_SUSPEND, .time_ns = lavagna_now_ns()});
    [(LavView *)self.window.rootViewController.view tick:nil];
}

@end

@interface LavAppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation LavAppDelegate

/* A game has nothing for the system's File, Edit, Format and View menus in
   the iPadOS menu bar. */
- (void)buildMenuWithBuilder:(id<UIMenuBuilder>)builder {
    if (builder.system != UIMenuSystem.mainSystem) {
        return;
    }
    [builder removeMenuForIdentifier:UIMenuFile];
    [builder removeMenuForIdentifier:UIMenuEdit];
    [builder removeMenuForIdentifier:UIMenuFormat];
    [builder removeMenuForIdentifier:UIMenuView];
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        the_lv.cfg = (lav_config){.title = "lavagna", .scale = 1};
        lav_setup(&the_lv.cfg);
        if (!lavagna_start(&the_lv)) {
            return 1;
        }
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([LavAppDelegate class]));
    }
}
