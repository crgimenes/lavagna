#include "lavagna_image.h"

#include <stdlib.h>

CGImageRef lavagna_create_cgimage(const uint32_t *pixels, int32_t w, int32_t h) {
    size_t n = (size_t)w * (size_t)h;
    CFMutableDataRef data = CFDataCreateMutable(NULL, (CFIndex)(n * 4));
    if (data == NULL) {
        return NULL;
    }
    CFDataSetLength(data, (CFIndex)(n * 4));
    uint8_t *rgba = CFDataGetMutableBytePtr(data);
    for (size_t i = 0; i < n; i++) {
        uint32_t p = pixels[i];
        rgba[i * 4] = (uint8_t)(p >> 16u);
        rgba[i * 4 + 1] = (uint8_t)(p >> 8u);
        rgba[i * 4 + 2] = (uint8_t)p;
        rgba[i * 4 + 3] = (uint8_t)(p >> 24u);
    }
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
    CFRelease(data);
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGImageRef img = CGImageCreate((size_t)w, (size_t)h, 8, 32, (size_t)w * 4, cs,
                                   (CGBitmapInfo)kCGImageAlphaLast, provider, NULL, false,
                                   kCGRenderingIntentDefault);
    CGColorSpaceRelease(cs);
    CGDataProviderRelease(provider);
    return img;
}

/* Drawn into an sRGB context (which only comes premultiplied), then the
   alpha divided back out. */
int lavagna_pixels_of(CGImageRef img, uint32_t *dst, size_t cap, int32_t *w, int32_t *h) {
    size_t iw = CGImageGetWidth(img);
    size_t ih = CGImageGetHeight(img);
    if (iw == 0 || ih == 0 || iw > INT32_MAX || ih > INT32_MAX) {
        return 0;
    }
    *w = (int32_t)iw;
    *h = (int32_t)ih;
    if (iw > cap / ih) {
        return -1;
    }
    uint8_t *rgba = calloc(iw * ih, 4);
    if (rgba == NULL) {
        return 0;
    }
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef ctx = CGBitmapContextCreate(rgba, iw, ih, 8, iw * 4, cs,
                                             (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(cs);
    if (ctx == NULL) {
        free(rgba);
        return 0;
    }
    CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);
    CGContextDrawImage(ctx, CGRectMake(0, 0, (CGFloat)iw, (CGFloat)ih), img);
    CGContextRelease(ctx);
    for (size_t i = 0; i < iw * ih; i++) {
        uint32_t a = rgba[i * 4 + 3];
        uint32_t c[3];
        for (int k = 0; k < 3; k++) {
            c[k] = a == 0 ? 0 : (rgba[i * 4 + (size_t)k] * 255u + a / 2) / a;
            c[k] = c[k] > 255 ? 255 : c[k];
        }
        dst[i] = a << 24u | c[0] << 16u | c[1] << 8u | c[2];
    }
    free(rgba);
    return 1;
}
