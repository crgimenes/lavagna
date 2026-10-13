#import "lavagna_metal.h"

#import <Metal/Metal.h>

#include <stdio.h>
#include <stdlib.h>

static const char shader[] =
    "#include <metal_stdlib>\n"
    "using namespace metal;\n"
    "struct V { float4 pos [[position]]; float2 uv; };\n"
    "vertex V vmain(uint id [[vertex_id]]) {\n"
    "    float2 p = float2((id << 1) & 2, id & 2);\n"
    "    V v;\n"
    "    v.pos = float4(p * float2(2, -2) + float2(-1, 1), 0, 1);\n"
    "    v.uv = p;\n"
    "    return v;\n"
    "}\n"
    "fragment float4 fmain(V in [[stage_in]], texture2d<float> t [[texture(0)]]) {\n"
    "    constexpr sampler s(filter::nearest);\n"
    "    return t.sample(s, in.uv);\n"
    "}\n";

@implementation LavRenderer {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _queue;
    id<MTLRenderPipelineState> _pipeline;
    id<MTLTexture> _tex;
    id<MTLCommandBuffer> _last;
}

static void fatal(const char *what, NSError *err) {
    fprintf(stderr, "lavagna: %s: %s\n", what,
            err != nil ? err.localizedDescription.UTF8String : "unavailable");
    exit(1);
}

- (instancetype)initWithLayer:(CAMetalLayer *)layer {
    self = [super init];
    if (self == nil) {
        return nil;
    }
    _device = MTLCreateSystemDefaultDevice();
    if (_device == nil) {
        fatal("Metal device", nil);
    }
    _queue = [_device newCommandQueue];
    NSError *err = nil;
    id<MTLLibrary> lib = [_device newLibraryWithSource:@(shader) options:nil error:&err];
    if (lib == nil) {
        fatal("shader", err);
    }
    MTLRenderPipelineDescriptor *d = [MTLRenderPipelineDescriptor new];
    d.vertexFunction = [lib newFunctionWithName:@"vmain"];
    d.fragmentFunction = [lib newFunctionWithName:@"fmain"];
    d.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    _pipeline = [_device newRenderPipelineStateWithDescriptor:d error:&err];
    if (_pipeline == nil) {
        fatal("pipeline", err);
    }
    _layer = layer;
    layer.device = _device;
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    layer.framebufferOnly = YES;
    layer.opaque = YES;
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    layer.colorspace = cs;
    CGColorSpaceRelease(cs);
    return self;
}

- (void)upload:(lavagna *)lv {
    if (_tex == nil || (int32_t)_tex.width != lv->width || (int32_t)_tex.height != lv->height) {
        MTLTextureDescriptor *td =
            [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                               width:(NSUInteger)lv->width
                                                              height:(NSUInteger)lv->height
                                                           mipmapped:NO];
        td.usage = MTLTextureUsageShaderRead;
        td.storageMode = MTLStorageModeShared;
        _tex = [_device newTextureWithDescriptor:td];
        lav_dirty(lv, 0, 0, lv->width, lv->height);
    }
    if (!lv->dirty) {
        return;
    }
    /* The texture is shared with the GPU: writing it while the last frame
       still samples it would tear. */
    [_last waitUntilCompleted];
    int32_t x0 = lv->dx0;
    int32_t y0 = lv->dy0;
    MTLRegion r = MTLRegionMake2D((NSUInteger)x0, (NSUInteger)y0, (NSUInteger)(lv->dx1 - x0),
                                  (NSUInteger)(lv->dy1 - y0));
    [_tex replaceRegion:r
            mipmapLevel:0
              withBytes:lv->pixels + (size_t)y0 * (size_t)lv->width + (size_t)x0
            bytesPerRow:(NSUInteger)lv->width * 4];
    lv->dirty = 0;
    lv->redraw = 1;
}

- (void)render:(lavagna *)lv {
    [self upload:lv];
    if (!lv->redraw) {
        return;
    }
    id<CAMetalDrawable> dr = [_layer nextDrawable];
    if (dr == nil) {
        return;
    }
    MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
    rp.colorAttachments[0].texture = dr.texture;
    rp.colorAttachments[0].loadAction = MTLLoadActionClear;
    rp.colorAttachments[0].storeAction = MTLStoreActionStore;
    rp.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
    id<MTLCommandBuffer> cb = [_queue commandBuffer];
    id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
    [enc setRenderPipelineState:_pipeline];
    [enc
        setViewport:(MTLViewport){(double)lv->offx, (double)lv->offy, (double)lv->width * lv->scale,
                                  (double)lv->height * lv->scale, 0, 1}];
    [enc setFragmentTexture:_tex atIndex:0];
    [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [enc endEncoding];
    [cb presentDrawable:dr];
    [cb commit];
    _last = cb;
    lv->redraw = 0;
}

@end
