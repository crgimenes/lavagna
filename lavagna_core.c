#include "lavagna_core.h"

/* The platform-free part: no libc, so the wasm build shares it. */

void lavagna_push(lavagna *lv, lav_event ev) {
    if (lv->len == EVENTS_MAX) {
        lv->dropped++;
        return;
    }
    lv->queue[(lv->head + lv->len) % EVENTS_MAX] = ev;
    lv->len++;
}

int lav_poll(lavagna *lv, lav_event *ev) {
    if (lv->len == 0) {
        return 0;
    }
    *ev = lv->queue[lv->head];
    lv->head = (lv->head + 1) % EVENTS_MAX;
    lv->len--;
    return 1;
}

lav_buffer lav_pixels(lavagna *lv) {
    return (lav_buffer){lv->pixels, lv->width, lv->height, lv->width};
}

void lav_dirty(lavagna *lv, int32_t x, int32_t y, int32_t w, int32_t h) {
    int32_t x0 = x < 0 ? 0 : x;
    int32_t y0 = y < 0 ? 0 : y;
    int32_t x1 = x + w > lv->width ? lv->width : x + w;
    int32_t y1 = y + h > lv->height ? lv->height : y + h;
    if (x0 >= x1 || y0 >= y1) {
        return;
    }
    if (!lv->dirty) {
        lv->dirty = 1;
        lv->dx0 = x0;
        lv->dy0 = y0;
        lv->dx1 = x1;
        lv->dy1 = y1;
        return;
    }
    lv->dx0 = x0 < lv->dx0 ? x0 : lv->dx0;
    lv->dy0 = y0 < lv->dy0 ? y0 : lv->dy0;
    lv->dx1 = x1 > lv->dx1 ? x1 : lv->dx1;
    lv->dy1 = y1 > lv->dy1 ? y1 : lv->dy1;
}

uint64_t lav_time_ns(const lavagna *lv) {
    return lv->frame_ns;
}

int32_t lav_device_scale(const lavagna *lv) {
    return lv->device_scale;
}

void lav_quit(lavagna *lv) {
    lv->quit = 1;
}

int lavagna_layout(lavagna *lv, int32_t dw, int32_t dh) {
    int realloc = 0;
    lv->redraw = 1;
    if (lv->follow && (dw != lv->width || dh != lv->height)) {
        if (!lavagna_alloc(lv, dw, dh)) {
            return realloc;
        }
        lavagna_push(lv, (lav_event){.type = LAV_EV_RESIZE, .time_ns = lavagna_now_ns()});
        realloc = 1;
    }
    int32_t s = 1;
    if (!lv->follow) {
        int32_t sx = dw / lv->width;
        int32_t sy = dh / lv->height;
        s = sx < sy ? sx : sy;
        s = s < 1 ? 1 : s;
    }
    lv->scale = s;
    lv->offx = (dw - lv->width * s) / 2;
    lv->offy = (dh - lv->height * s) / 2;
    return realloc;
}

int lavagna_valid(const lav_config *cfg) {
    if (cfg->title == NULL || cfg->scale < 1 || cfg->width < 0 || cfg->height < 0) {
        return 0;
    }
    if ((cfg->width == 0) != (cfg->height == 0)) {
        return 0;
    }
    return cfg->width <= SIDE_MAX && cfg->height <= SIDE_MAX;
}
