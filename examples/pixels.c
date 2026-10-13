/* A 1-pixel pencil on a fixed 128x96 buffer shown at an integer scale. */
#include "../lavagna.h"

enum {
    WIDTH = 128,
    HEIGHT = 96,
    COLORS = 8,
};

static const uint32_t palette[COLORS] = {
    0xff000000u, 0xff1d2b53u, 0xff7e2553u, 0xff008751u,
    0xffab5236u, 0xffff004du, 0xffffec27u, 0xfffff1e8u,
};

typedef struct {
    int down;
    int32_t x;
    int32_t y;
    uint32_t color;
} pixels;

void lav_setup(lav_config *cfg) {
    static pixels p = {.color = 7};
    cfg->title = "pixels";
    cfg->width = WIDTH;
    cfg->height = HEIGHT;
    cfg->scale = 6;
    cfg->user = &p;
}

static void clear(lavagna *lv) {
    lav_buffer b = lav_pixels(lv);
    for (int32_t y = 0; y < b.height; y++) {
        for (int32_t x = 0; x < b.width; x++) {
            b.pixels[y * b.stride + x] = palette[1];
        }
    }
    lav_dirty(lv, 0, 0, b.width, b.height);
}

static void plot(lavagna *lv, const pixels *p, int32_t x, int32_t y) {
    lav_buffer b = lav_pixels(lv);
    if (x < 0 || y < 0 || x >= b.width || y >= b.height) {
        return;
    }
    b.pixels[y * b.stride + x] = palette[p->color];
    lav_dirty(lv, x, y, 1, 1);
}

static void line(lavagna *lv, const pixels *p, int32_t x0, int32_t y0, int32_t x1, int32_t y1) {
    int32_t dx = x1 > x0 ? x1 - x0 : x0 - x1;
    int32_t dy = y1 > y0 ? y0 - y1 : y1 - y0;
    int32_t sx = x0 < x1 ? 1 : -1;
    int32_t sy = y0 < y1 ? 1 : -1;
    int32_t err = dx + dy;
    for (;;) {
        plot(lv, p, x0, y0);
        if (x0 == x1 && y0 == y1) {
            return;
        }
        int32_t e2 = 2 * err;
        if (e2 >= dy) {
            err += dy;
            x0 += sx;
        }
        if (e2 <= dx) {
            err += dx;
            y0 += sy;
        }
    }
}

void lav_frame(lavagna *lv, void *user) {
    pixels *p = user;
    lav_event ev;
    while (lav_poll(lv, &ev)) {
        switch (ev.type) {
        case LAV_EV_RESIZE:
            clear(lv);
            break;
        case LAV_EV_POINTER_DOWN:
            p->down = 1;
            p->x = ev.x;
            p->y = ev.y;
            plot(lv, p, ev.x, ev.y);
            break;
        case LAV_EV_POINTER_MOVE:
            if (p->down) {
                line(lv, p, p->x, p->y, ev.x, ev.y);
                p->x = ev.x;
                p->y = ev.y;
            }
            break;
        case LAV_EV_POINTER_UP:
            p->down = 0;
            break;
        case LAV_EV_KEY_DOWN:
            if (ev.key >= '1' && ev.key < '1' + COLORS) {
                p->color = ev.key - '1';
            } else if (ev.key == LAV_KEY_ESCAPE) {
                clear(lv);
            }
            break;
        case LAV_EV_CLOSE:
            lav_quit(lv);
            break;
        default:
            break;
        }
    }
}
