/* Images between lavagna's 0xAARRGGBB pixels and CoreGraphics, for the
   clipboard on macOS and iOS. Internal to the Apple backends. */
#ifndef LAVAGNA_IMAGE_H
#define LAVAGNA_IMAGE_H

#include <CoreGraphics/CoreGraphics.h>
#include <stddef.h>
#include <stdint.h>

/* NULL when out of memory. The caller releases it. */
CGImageRef lavagna_create_cgimage(const uint32_t *pixels, int32_t w, int32_t h);
/* 1 with the size when the image fits in cap pixels, -1 with the size when
   it does not, 0 when it cannot be read. */
int lavagna_pixels_of(CGImageRef img, uint32_t *dst, size_t cap, int32_t *w, int32_t *h);

#endif
