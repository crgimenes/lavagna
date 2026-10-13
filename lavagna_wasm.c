/* The browser backend: this file, lavagna_core.c and the program build
   together for wasm32 with no C library; lavagna.js is the other half.
   Pointers cross to JavaScript as offsets into the exported memory. */
#include "lavagna_core.h"

#define IMPORT(name) __attribute__((import_module("lavagna"), import_name(name)))
#define EXPORT(name) __attribute__((export_name(name)))

enum {
    PAGE = 65536,
};

IMPORT("present")
void js_present(const uint8_t *rgba, int32_t w, int32_t h, int32_t x, int32_t y, int32_t dw,
                int32_t dh);
IMPORT("title") void js_title(const char *title);
IMPORT("cursor") void js_cursor(int32_t kind);
IMPORT("file_read") int32_t js_file_read(const char *path, uint8_t *dst, uint32_t cap);
IMPORT("file_write") int32_t js_file_write(const char *path, const uint8_t *data, uint32_t len);

/* wasm-ld defines it: where the heap starts. */
// NOLINTNEXTLINE(bugprone-reserved-identifier,cert-dcl37-c,cert-dcl51-cpp)
extern unsigned char __heap_base;

static lavagna the_lv;
static uint8_t *rgba;
static uint64_t now;

/* The compiler calls these for copies and clears; nothing else provides
   them here. Built with -fno-builtin, so they do not call themselves. */
void *memcpy(void *dst, const void *src, size_t n) {
    uint8_t *d = dst;
    const uint8_t *s = src;
    for (size_t i = 0; i < n; i++) {
        d[i] = s[i];
    }
    return dst;
}

void *memmove(void *dst, const void *src, size_t n) {
    uint8_t *d = dst;
    const uint8_t *s = src;
    if (d < s) {
        return memcpy(dst, src, n);
    }
    for (size_t i = n; i > 0; i--) {
        d[i - 1] = s[i - 1];
    }
    return dst;
}

void *memset(void *dst, int c, size_t n) {
    uint8_t *d = dst;
    for (size_t i = 0; i < n; i++) {
        d[i] = (uint8_t)c;
    }
    return dst;
}

int memcmp(const void *a, const void *b, size_t n) {
    const uint8_t *x = a;
    const uint8_t *y = b;
    for (size_t i = 0; i < n; i++) {
        if (x[i] != y[i]) {
            return x[i] < y[i] ? -1 : 1;
        }
    }
    return 0;
}

uint64_t lavagna_now_ns(void) {
    return now;
}

/* One buffer at a time, at the heap's start, then its RGBA copy for the
   canvas: a resize reuses the place, growing the memory when it must. */
int lavagna_alloc(lavagna *lv, int32_t w, int32_t h) {
    size_t px = (size_t)w * (size_t)h * 4;
    size_t base = ((size_t)&__heap_base + 15) & ~(size_t)15;
    size_t need = base + px * 2;
    size_t have = __builtin_wasm_memory_size(0) * PAGE;
    if (need > have &&
        __builtin_wasm_memory_grow(0, (need - have + PAGE - 1) / PAGE) == (size_t)-1) {
        return 0;
    }
    lv->pixels = (uint32_t *)base;
    rgba = (uint8_t *)(base + px);
    memset(lv->pixels, 0, px);
    lv->width = w;
    lv->height = h;
    return 1;
}

void lav_set_title(lavagna *lv, const char *title) {
    (void)lv;
    js_title(title);
}

void lav_cursor(lavagna *lv, lav_cursor_kind kind) {
    if (lv->cursor != kind) {
        lv->cursor = kind;
        js_cursor((int32_t)kind);
    }
}

/* Files live in the browser's localStorage, by path. */
int64_t lav_file_read(lavagna *lv, const char *path, uint8_t *dst, size_t cap) {
    (void)lv;
    return js_file_read(path, dst, (uint32_t)cap);
}

int lav_file_write(lavagna *lv, const char *path, const uint8_t *data, size_t len) {
    (void)lv;
    return js_file_write(path, data, (uint32_t)len);
}

EXPORT("setup") int32_t wasm_setup(void) {
    lavagna *lv = &the_lv;
    lv->cfg = (lav_config){.title = "lavagna", .scale = 1};
    lav_setup(&lv->cfg);
    lv->scale = 1;
    lv->device_scale = 1;
    if (!lavagna_valid(&lv->cfg)) {
        return -1;
    }
    lv->follow = lv->cfg.width == 0;
    js_title(lv->cfg.title);
    if (!lv->follow) {
        if (!lavagna_alloc(lv, lv->cfg.width, lv->cfg.height)) {
            return -1;
        }
        lavagna_push(lv, (lav_event){.type = LAV_EV_RESIZE});
    }
    return lv->follow ? 0 : 1;
}

EXPORT("buffer_width") int32_t wasm_buffer_width(void) {
    return the_lv.width;
}

EXPORT("buffer_height") int32_t wasm_buffer_height(void) {
    return the_lv.height;
}

/* The canvas's size in device pixels. A fixed buffer is scaled by the
   page, so only one that follows the window cares. */
EXPORT("resize") void wasm_resize(int32_t dw, int32_t dh, int32_t device_scale) {
    lavagna *lv = &the_lv;
    lv->device_scale = device_scale < 1 ? 1 : device_scale;
    if (lv->follow) {
        (void)lavagna_layout(lv, dw, dh);
    }
    lv->scale = 1;
    lv->offx = 0;
    lv->offy = 0;
}

EXPORT("event")
void wasm_event(int32_t type, int32_t x, int32_t y, int32_t button, int32_t pointer,
                int32_t pressure, int32_t mods, int32_t key, int32_t sx, int32_t sy, int32_t zoom) {
    lavagna_push(&the_lv, (lav_event){
                              .type = (lav_event_type)type,
                              .mods = (uint32_t)mods,
                              .time_ns = now,
                              .x = x,
                              .y = y,
                              .pressure = (uint32_t)pressure,
                              .button = (uint8_t)button,
                              .pointer = (uint8_t)pointer,
                              .key = (uint32_t)key,
                              .scroll_x = sx,
                              .scroll_y = sy,
                              .zoom = zoom,
                          });
}

/* One frame at time ms; what changed goes to the canvas as RGBA. Returns 1
   when the program quit. */
EXPORT("frame") int32_t wasm_frame(double ms) {
    lavagna *lv = &the_lv;
    now = (uint64_t)(ms * 1e6);
    lv->frame_ns = now;
    lv->frames++;
    lav_frame(lv, lv->cfg.user);
    if (lv->dirty) {
        for (int32_t y = lv->dy0; y < lv->dy1; y++) {
            for (int32_t x = lv->dx0; x < lv->dx1; x++) {
                size_t i = (size_t)y * (size_t)lv->width + (size_t)x;
                uint32_t p = lv->pixels[i];
                rgba[i * 4] = (uint8_t)(p >> 16u);
                rgba[i * 4 + 1] = (uint8_t)(p >> 8u);
                rgba[i * 4 + 2] = (uint8_t)p;
                rgba[i * 4 + 3] = 255;
            }
        }
        js_present(rgba, lv->width, lv->height, lv->dx0, lv->dy0, lv->dx1 - lv->dx0,
                   lv->dy1 - lv->dy0);
        lv->dirty = 0;
    }
    return lv->quit;
}
