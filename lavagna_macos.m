#import <Cocoa/Cocoa.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include <math.h>
#include <string.h>

#import "lavagna_metal.h"

#include "lavagna_image.h"

enum {
    FOLLOW_W = 960,
    FOLLOW_H = 640,
    LINE_PX = 32,
    ZOOM_UNIT = 1000,
    FIELD_W = 260,
    FIELD_H = 24,
};

/* Indexed by macOS virtual key code (kVK_*). */
static const uint16_t keymap[128] = {
    [0x00] = 'a',
    [0x01] = 's',
    [0x02] = 'd',
    [0x03] = 'f',
    [0x04] = 'h',
    [0x05] = 'g',
    [0x06] = 'z',
    [0x07] = 'x',
    [0x08] = 'c',
    [0x09] = 'v',
    [0x0B] = 'b',
    [0x0C] = 'q',
    [0x0D] = 'w',
    [0x0E] = 'e',
    [0x0F] = 'r',
    [0x10] = 'y',
    [0x11] = 't',
    [0x12] = '1',
    [0x13] = '2',
    [0x14] = '3',
    [0x15] = '4',
    [0x16] = '6',
    [0x17] = '5',
    [0x18] = '=',
    [0x19] = '9',
    [0x1A] = '7',
    [0x1B] = '-',
    [0x1C] = '8',
    [0x1D] = '0',
    [0x1E] = ']',
    [0x1F] = 'o',
    [0x20] = 'u',
    [0x21] = '[',
    [0x22] = 'i',
    [0x23] = 'p',
    [0x25] = 'l',
    [0x26] = 'j',
    [0x27] = '\'',
    [0x28] = 'k',
    [0x29] = ';',
    [0x2A] = '\\',
    [0x2B] = ',',
    [0x2C] = '/',
    [0x2D] = 'n',
    [0x2E] = 'm',
    [0x2F] = '.',
    [0x31] = ' ',
    [0x32] = '`',
    [0x24] = LAV_KEY_ENTER,
    [0x30] = LAV_KEY_TAB,
    [0x33] = LAV_KEY_BACKSPACE,
    [0x35] = LAV_KEY_ESCAPE,
    [0x75] = LAV_KEY_DELETE,
    [0x7B] = LAV_KEY_LEFT,
    [0x7C] = LAV_KEY_RIGHT,
    [0x7D] = LAV_KEY_DOWN,
    [0x7E] = LAV_KEY_UP,
    [0x73] = LAV_KEY_HOME,
    [0x77] = LAV_KEY_END,
    [0x74] = LAV_KEY_PAGE_UP,
    [0x79] = LAV_KEY_PAGE_DOWN,
    [0x7A] = LAV_KEY_F1,
    [0x78] = LAV_KEY_F2,
    [0x63] = LAV_KEY_F3,
    [0x76] = LAV_KEY_F4,
    [0x60] = LAV_KEY_F5,
    [0x61] = LAV_KEY_F6,
    [0x62] = LAV_KEY_F7,
    [0x64] = LAV_KEY_F8,
    [0x65] = LAV_KEY_F9,
    [0x6D] = LAV_KEY_F10,
    [0x67] = LAV_KEY_F11,
    [0x6F] = LAV_KEY_F12,
};

static const struct {
    NSEventModifierFlags flag;
    uint32_t mod;
    uint32_t key;
} modmap[] = {
    {NSEventModifierFlagShift, LAV_MOD_SHIFT, LAV_KEY_SHIFT},
    {NSEventModifierFlagControl, LAV_MOD_CTRL, LAV_KEY_CTRL},
    {NSEventModifierFlagOption, LAV_MOD_ALT, LAV_KEY_ALT},
    {NSEventModifierFlagCommand, LAV_MOD_CMD, LAV_KEY_CMD},
};

static uint32_t mods_of(NSEventModifierFlags f) {
    uint32_t m = 0;
    for (size_t i = 0; i < sizeof modmap / sizeof modmap[0]; i++) {
        if (f & modmap[i].flag) {
            m |= modmap[i].mod;
        }
    }
    return m;
}

static NSWindow *window_of(const lavagna *lv) {
    return (__bridge NSWindow *)lv->window;
}

void lav_set_title(lavagna *lv, const char *title) {
    window_of(lv).title = @(title);
}

void lav_set_edited(lavagna *lv, int edited) {
    window_of(lv).documentEdited = edited != 0;
}

static NSCursor *cursor_for(lav_cursor_kind k) {
    switch (k) {
    case LAV_CURSOR_CROSSHAIR:
        return NSCursor.crosshairCursor;
    case LAV_CURSOR_HAND:
        return NSCursor.openHandCursor;
    case LAV_CURSOR_GRAB:
        return NSCursor.closedHandCursor;
    case LAV_CURSOR_ARROW:
    default:
        return NSCursor.arrowCursor;
    }
}

void lav_cursor(lavagna *lv, lav_cursor_kind kind) {
    if (lv->cursor == kind) {
        return;
    }
    lv->cursor = kind;
    [cursor_for(kind) set];
    [window_of(lv) invalidateCursorRectsForView:window_of(lv).contentView];
}

/* PNG for the apps that read it, TIFF for the older ones. */
int lav_clipboard_set_image(lavagna *lv, const uint32_t *pixels, int32_t w, int32_t h) {
    (void)lv;
    CGImageRef img = lavagna_create_cgimage(pixels, w, h);
    if (img == NULL) {
        return 0;
    }
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:img];
    CGImageRelease(img);
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    NSPasteboard *pb = NSPasteboard.generalPasteboard;
    [pb clearContents];
    return [pb setData:png forType:NSPasteboardTypePNG] && [pb setData:rep.TIFFRepresentation
                                                               forType:NSPasteboardTypeTIFF];
}

int lav_clipboard_get_image(lavagna *lv, uint32_t *dst, size_t cap, int32_t *w, int32_t *h) {
    (void)lv;
    NSPasteboard *pb = NSPasteboard.generalPasteboard;
    NSData *data = [pb dataForType:NSPasteboardTypePNG];
    if (data == nil) {
        data = [pb dataForType:NSPasteboardTypeTIFF];
    }
    NSBitmapImageRep *rep = data != nil ? [NSBitmapImageRep imageRepWithData:data] : nil;
    if (rep == nil || rep.CGImage == NULL) {
        return 0;
    }
    return lavagna_pixels_of(rep.CGImage, dst, cap, w, h);
}

static void panel_done(lavagna *lv, uint32_t id, NSURL *url) {
    lv->panel_path[0] = '\0';
    uint8_t chosen = 0;
    if (url != nil && strlen(url.fileSystemRepresentation) < PATH_CAP) {
        lavagna_copy_text(lv->panel_path, PATH_CAP, url.fileSystemRepresentation);
        chosen = 1;
    }
    lavagna_push(lv, (lav_event){
                         .type = LAV_EV_PANEL,
                         .time_ns = lavagna_now_ns(),
                         .button = chosen,
                         .id = id,
                     });
}

void lav_open_panel(lavagna *lv, uint32_t id, const char *extension) {
    if (lv->replay != NULL) {
        return;
    }
    NSOpenPanel *p = [NSOpenPanel openPanel];
    p.allowedContentTypes = @[ [UTType typeWithFilenameExtension:@(extension)] ];
    p.canChooseDirectories = NO;
    p.allowsMultipleSelection = NO;
    [p beginSheetModalForWindow:window_of(lv)
              completionHandler:^(NSModalResponse r) {
                panel_done(lv, id, r == NSModalResponseOK ? p.URL : nil);
              }];
}

void lav_save_panel(lavagna *lv, uint32_t id, const char *extension, const char *name) {
    if (lv->replay != NULL) {
        return;
    }
    NSSavePanel *p = [NSSavePanel savePanel];
    p.allowedContentTypes = @[ [UTType typeWithFilenameExtension:@(extension)] ];
    if (name != NULL) {
        p.nameFieldStringValue = @(name);
    }
    [p beginSheetModalForWindow:window_of(lv)
              completionHandler:^(NSModalResponse r) {
                panel_done(lv, id, r == NSModalResponseOK ? p.URL : nil);
              }];
}

void lav_alert(lavagna *lv, uint32_t id, const char *title, const char *message,
               const char *const *buttons, uint32_t nbuttons, const char *text) {
    if (lv->replay != NULL) {
        return;
    }
    NSAlert *a = [NSAlert new];
    a.messageText = @(title);
    a.informativeText = message != NULL ? @(message) : @"";
    for (uint32_t i = 0; i < nbuttons && i < ALERT_BUTTONS_MAX; i++) {
        [a addButtonWithTitle:@(buttons[i])];
    }
    NSTextField *field = nil;
    if (text != NULL) {
        field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, FIELD_W, FIELD_H)];
        field.stringValue = @(text);
        a.accessoryView = field;
        [a layout];
        a.window.initialFirstResponder = field;
    }
    [a beginSheetModalForWindow:window_of(lv)
              completionHandler:^(NSModalResponse r) {
                lv->alert_text[0] = '\0';
                if (field != nil) {
                    lavagna_copy_text(lv->alert_text, TEXT_CAP, field.stringValue.UTF8String);
                }
                uint8_t b = 0;
                if (r >= NSAlertFirstButtonReturn) {
                    b = (uint8_t)(r - NSAlertFirstButtonReturn);
                }
                lavagna_push(lv, (lav_event){
                                     .type = LAV_EV_ALERT,
                                     .time_ns = lavagna_now_ns(),
                                     .button = b,
                                     .id = id,
                                 });
              }];
}

@interface LavView : NSView
@end

@implementation LavView {
    lavagna *_lv;
    LavRenderer *_renderer;
    CADisplayLink *_link;
    double _scroll_x;
    double _scroll_y;
    double _zoom;
}

- (instancetype)initWithFrame:(NSRect)frame lavagna:(lavagna *)lv {
    self = [super initWithFrame:frame];
    if (self == nil) {
        return nil;
    }
    _lv = lv;
    self.wantsLayer = YES;
    return self;
}

- (CALayer *)makeBackingLayer {
    CAMetalLayer *layer = [CAMetalLayer layer];
    _renderer = [[LavRenderer alloc] initWithLayer:layer];
    return layer;
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)resetCursorRects {
    [self addCursorRect:self.bounds cursor:cursor_for(_lv->cursor)];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.window == nil || _link != nil) {
        return;
    }
    _link = [self displayLinkWithTarget:self selector:@selector(tick:)];
    [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)syncSize {
    CAMetalLayer *layer = _renderer.layer;
    CGFloat bs = self.window.backingScaleFactor;
    CGSize pt = self.bounds.size;
    CGSize px = CGSizeMake(fmax(1, floor(pt.width * bs)), fmax(1, floor(pt.height * bs)));
    if (CGSizeEqualToSize(px, layer.drawableSize) && layer.contentsScale == bs) {
        return;
    }
    layer.contentsScale = bs;
    layer.drawableSize = px;
    _lv->device_scale = (int32_t)lround(bs);
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
    if (_lv->quit) {
        [NSApp terminate:nil];
        return;
    }
    [_renderer render:_lv];
}

- (lav_event)at:(NSEvent *)e type:(lav_event_type)t {
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
    CGFloat bs = self.window.backingScaleFactor;
    return (lav_event){
        .type = t,
        .mods = mods_of(e.modifierFlags),
        .time_ns = (uint64_t)(e.timestamp * 1e9),
        .x = (int32_t)floor((p.x * bs - _lv->offx) / _lv->scale),
        .y = (int32_t)floor((p.y * bs - _lv->offy) / _lv->scale),
    };
}

- (void)scrollWheel:(NSEvent *)e {
    double k = e.hasPreciseScrollingDeltas ? self.window.backingScaleFactor : (double)LINE_PX;
    _scroll_x += e.scrollingDeltaX * k / _lv->scale;
    _scroll_y += e.scrollingDeltaY * k / _lv->scale;
    lav_event ev = [self at:e type:LAV_EV_SCROLL];
    ev.scroll_x = (int32_t)trunc(_scroll_x);
    ev.scroll_y = (int32_t)trunc(_scroll_y);
    _scroll_x -= ev.scroll_x;
    _scroll_y -= ev.scroll_y;
    if (ev.scroll_x != 0 || ev.scroll_y != 0) {
        lavagna_push(_lv, ev);
    }
}

- (void)magnifyWithEvent:(NSEvent *)e {
    _zoom += e.magnification * (double)ZOOM_UNIT;
    lav_event ev = [self at:e type:LAV_EV_PINCH];
    ev.zoom = (int32_t)trunc(_zoom);
    _zoom -= ev.zoom;
    if (ev.zoom != 0) {
        lavagna_push(_lv, ev);
    }
}

- (void)pointer:(NSEvent *)e type:(lav_event_type)t button:(uint8_t)b {
    lav_event ev = [self at:e type:t];
    ev.button = b;
    ev.pointer = LAV_POINTER_MOUSE;
    NSEventType et = e.type;
    int down = t == LAV_EV_POINTER_DOWN || et == NSEventTypeLeftMouseDragged ||
               et == NSEventTypeRightMouseDragged || et == NSEventTypeOtherMouseDragged;
    if (e.subtype == NSEventSubtypeTabletPoint) {
        ev.pointer = LAV_POINTER_PEN;
        double pr = fmin(fmax((double)e.pressure, 0), 1);
        ev.pressure = (uint32_t)lround(pr * (double)LAV_PRESSURE_MAX);
    } else if (down) {
        ev.pressure = LAV_PRESSURE_MAX;
    }
    lavagna_push(_lv, ev);
}

- (void)mouseDown:(NSEvent *)e {
    [self pointer:e type:LAV_EV_POINTER_DOWN button:LAV_BUTTON_PRIMARY];
}

- (void)mouseDragged:(NSEvent *)e {
    [self pointer:e type:LAV_EV_POINTER_MOVE button:LAV_BUTTON_PRIMARY];
}

- (void)mouseUp:(NSEvent *)e {
    [self pointer:e type:LAV_EV_POINTER_UP button:LAV_BUTTON_PRIMARY];
}

- (void)mouseMoved:(NSEvent *)e {
    [self pointer:e type:LAV_EV_POINTER_MOVE button:LAV_BUTTON_PRIMARY];
}

- (void)rightMouseDown:(NSEvent *)e {
    [self pointer:e type:LAV_EV_POINTER_DOWN button:LAV_BUTTON_SECONDARY];
}

- (void)rightMouseDragged:(NSEvent *)e {
    [self pointer:e type:LAV_EV_POINTER_MOVE button:LAV_BUTTON_SECONDARY];
}

- (void)rightMouseUp:(NSEvent *)e {
    [self pointer:e type:LAV_EV_POINTER_UP button:LAV_BUTTON_SECONDARY];
}

- (void)otherMouseDown:(NSEvent *)e {
    [self pointer:e type:LAV_EV_POINTER_DOWN button:LAV_BUTTON_MIDDLE];
}

- (void)otherMouseDragged:(NSEvent *)e {
    [self pointer:e type:LAV_EV_POINTER_MOVE button:LAV_BUTTON_MIDDLE];
}

- (void)otherMouseUp:(NSEvent *)e {
    [self pointer:e type:LAV_EV_POINTER_UP button:LAV_BUTTON_MIDDLE];
}

- (void)key:(NSEvent *)e type:(lav_event_type)t {
    uint16_t code = e.keyCode;
    if (code >= sizeof keymap / sizeof keymap[0] || keymap[code] == 0) {
        return;
    }
    lavagna_push(_lv, (lav_event){
                          .type = t,
                          .mods = mods_of(e.modifierFlags),
                          .time_ns = (uint64_t)(e.timestamp * 1e9),
                          .key = keymap[code],
                          .repeat = t == LAV_EV_KEY_DOWN && e.ARepeat,
                      });
}

- (void)keyDown:(NSEvent *)e {
    [self key:e type:LAV_EV_KEY_DOWN];
}

- (void)keyUp:(NSEvent *)e {
    [self key:e type:LAV_EV_KEY_UP];
}

- (void)flagsChanged:(NSEvent *)e {
    uint32_t now = mods_of(e.modifierFlags);
    for (size_t i = 0; i < sizeof modmap / sizeof modmap[0]; i++) {
        uint32_t m = modmap[i].mod;
        if ((now & m) == (_lv->mods & m)) {
            continue;
        }
        lavagna_push(_lv, (lav_event){
                              .type = (now & m) ? LAV_EV_KEY_DOWN : LAV_EV_KEY_UP,
                              .mods = now,
                              .time_ns = (uint64_t)(e.timestamp * 1e9),
                              .key = modmap[i].key,
                          });
    }
    _lv->mods = now;
}

@end

@interface LavDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property(nonatomic) lavagna *lv;
@property(nonatomic, strong) NSWindow *window;
@end

@implementation LavDelegate

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)app {
    (void)app;
    if (self.lv->quit) {
        return NSTerminateNow;
    }
    lavagna_push(self.lv, (lav_event){.type = LAV_EV_CLOSE, .time_ns = lavagna_now_ns()});
    return NSTerminateCancel;
}

- (BOOL)windowShouldClose:(NSWindow *)w {
    (void)w;
    lavagna_push(self.lv, (lav_event){.type = LAV_EV_CLOSE, .time_ns = lavagna_now_ns()});
    return NO;
}

/* A file from the Finder or the Dock: the first one, since a lavagna has one
   window. */
- (void)application:(NSApplication *)app openURLs:(NSArray<NSURL *> *)urls {
    (void)app;
    NSURL *url = urls.firstObject;
    if (url == nil || strlen(url.fileSystemRepresentation) >= PATH_CAP) {
        return;
    }
    lavagna_copy_text(self.lv->panel_path, PATH_CAP, url.fileSystemRepresentation);
    lavagna_push(self.lv, (lav_event){.type = LAV_EV_OPEN, .time_ns = lavagna_now_ns()});
}

- (void)menuItem:(NSMenuItem *)item {
    lavagna_push(self.lv, (lav_event){
                              .type = LAV_EV_MENU,
                              .mods = self.lv->mods,
                              .time_ns = lavagna_now_ns(),
                              .id = (uint32_t)item.tag,
                          });
}

@end

static NSMenuItem *item(NSString *title, SEL action, NSString *key) {
    return [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];
}

static NSMenu *submenu(NSMenu *bar, NSString *title) {
    NSMenuItem *top = [bar itemWithTitle:title];
    if (top != nil) {
        return top.submenu;
    }
    top = item(title, NULL, @"");
    top.submenu = [[NSMenu alloc] initWithTitle:title];
    [bar addItem:top];
    return top.submenu;
}

static void build_menu(const lav_config *cfg, LavDelegate *d) {
    NSString *name = @(cfg->title);
    NSMenu *bar = [NSMenu new];
    NSMenu *app = submenu(bar, name);
    [app addItem:item([@"About " stringByAppendingString:name],
                      @selector(orderFrontStandardAboutPanel:), @"")];
    [app addItem:[NSMenuItem separatorItem]];
    [app addItem:item([@"Hide " stringByAppendingString:name], @selector(hide:), @"h")];
    NSMenuItem *others = item(@"Hide Others", @selector(hideOtherApplications:), @"h");
    others.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    [app addItem:others];
    [app addItem:item(@"Show All", @selector(unhideAllApplications:), @"")];
    [app addItem:[NSMenuItem separatorItem]];
    [app addItem:item([@"Quit " stringByAppendingString:name], @selector(terminate:), @"q")];

    for (uint32_t i = 0; i < cfg->menu_len; i++) {
        const lav_menu_item *m = &cfg->menu[i];
        NSMenu *sub = submenu(bar, @(m->menu));
        if (m->title == NULL) {
            [sub addItem:[NSMenuItem separatorItem]];
            continue;
        }
        NSString *key = @"";
        if (m->key != 0) {
            unichar c = (unichar)m->key;
            key = [NSString stringWithCharacters:&c length:1];
        }
        NSMenuItem *it = item(@(m->title), @selector(menuItem:), key);
        NSEventModifierFlags mask = 0;
        for (size_t j = 0; j < sizeof modmap / sizeof modmap[0]; j++) {
            if (m->mods & modmap[j].mod) {
                mask |= modmap[j].flag;
            }
        }
        it.keyEquivalentModifierMask = mask;
        it.target = d;
        it.tag = (NSInteger)m->id;
        [sub addItem:it];
    }

    NSMenu *win = submenu(bar, @"Window");
    [win addItem:item(@"Minimize", @selector(performMiniaturize:), @"m")];
    [win addItem:item(@"Zoom", @selector(performZoom:), @"")];
    NSMenuItem *fs = item(@"Enter Full Screen", @selector(toggleFullScreen:), @"f");
    fs.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagControl;
    [win addItem:fs];
    NSApp.mainMenu = bar;
    NSApp.windowsMenu = win;
}

int main(void) {
    @autoreleasepool {
        static lavagna lv;
        lv.cfg = (lav_config){.title = "lavagna", .scale = 1};
        lav_setup(&lv.cfg);
        if (!lavagna_start(&lv)) {
            return 1;
        }
        NSSize size = NSMakeSize(FOLLOW_W, FOLLOW_H);
        if (!lv.follow) {
            size = NSMakeSize((CGFloat)lv.cfg.width * lv.cfg.scale,
                              (CGFloat)lv.cfg.height * lv.cfg.scale);
        }

        [NSApplication sharedApplication];
        NSApp.activationPolicy = NSApplicationActivationPolicyRegular;
        static LavDelegate *d;
        d = [LavDelegate new];
        d.lv = &lv;
        NSApp.delegate = d;
        build_menu(&lv.cfg, d);
        [NSEvent setMouseCoalescingEnabled:NO];

        NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                  NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
        d.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, size.width, size.height)
                                               styleMask:style
                                                 backing:NSBackingStoreBuffered
                                                   defer:NO];
        d.window.releasedWhenClosed = NO;
        d.window.title = @(lv.cfg.title);
        d.window.delegate = d;
        d.window.acceptsMouseMovedEvents = YES;
        d.window.contentMinSize = NSMakeSize(64, 64);
        lv.window = (__bridge void *)d.window;
        LavView *view = [[LavView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)
                                               lavagna:&lv];
        d.window.contentView = view;
        [d.window makeFirstResponder:view];
        [d.window center];
        [d.window makeKeyAndOrderFront:nil];
        [NSApp activate];
        [NSApp run];
    }
    return 0;
}
