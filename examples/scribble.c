/* Pressure-sensitive scribble on a buffer that follows the window. */
#include "../lavagna.h"

enum {
    MENU_CLEAR = 1,
    RADIUS_MAX = 6,
};

static const uint32_t paper = 0xfff4f1e8u;
static const uint32_t ink = 0xff1d2b53u;

typedef struct {
    int down;
    int32_t x;
    int32_t y;
} scribble;

static const lav_menu_item menu[] = {
    {"Image", "Clear", 'k', LAV_MOD_CMD, MENU_CLEAR},
};

void lav_setup(lav_config *cfg) {
    static scribble s;
    cfg->title = "scribble";
    cfg->menu = menu;
    cfg->menu_len = sizeof menu / sizeof menu[0];
    cfg->user = &s;
}

static void clear(lavagna *lv) {
    lav_buffer b = lav_pixels(lv);
    for (int32_t y = 0; y < b.height; y++) {
        for (int32_t x = 0; x < b.width; x++) {
            b.pixels[y * b.stride + x] = paper;
        }
    }
    lav_dirty(lv, 0, 0, b.width, b.height);
}

static void dot(lavagna *lv, int32_t cx, int32_t cy, int32_t r) {
    lav_buffer b = lav_pixels(lv);
    for (int32_t dy = -r; dy <= r; dy++) {
        for (int32_t dx = -r; dx <= r; dx++) {
            int32_t x = cx + dx;
            int32_t y = cy + dy;
            if (dx * dx + dy * dy > r * r || x < 0 || y < 0 || x >= b.width || y >= b.height) {
                continue;
            }
            b.pixels[y * b.stride + x] = ink;
        }
    }
    lav_dirty(lv, cx - r, cy - r, 2 * r + 1, 2 * r + 1);
}

static void line(lavagna *lv, int32_t x0, int32_t y0, int32_t x1, int32_t y1, int32_t r) {
    int32_t dx = x1 > x0 ? x1 - x0 : x0 - x1;
    int32_t dy = y1 > y0 ? y0 - y1 : y1 - y0;
    int32_t sx = x0 < x1 ? 1 : -1;
    int32_t sy = y0 < y1 ? 1 : -1;
    int32_t err = dx + dy;
    for (;;) {
        dot(lv, x0, y0, r);
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

static int32_t radius(uint32_t pressure) {
    return (int32_t)(pressure * RADIUS_MAX / LAV_PRESSURE_MAX);
}

void lav_frame(lavagna *lv, void *user) {
    scribble *s = user;
    lav_event ev;
    while (lav_poll(lv, &ev)) {
        switch (ev.type) {
        case LAV_EV_RESIZE:
            clear(lv);
            break;
        case LAV_EV_POINTER_DOWN:
            if (ev.button != LAV_BUTTON_PRIMARY) {
                break;
            }
            s->down = 1;
            s->x = ev.x;
            s->y = ev.y;
            dot(lv, ev.x, ev.y, radius(ev.pressure));
            break;
        case LAV_EV_POINTER_MOVE:
            if (!s->down) {
                break;
            }
            line(lv, s->x, s->y, ev.x, ev.y, radius(ev.pressure));
            s->x = ev.x;
            s->y = ev.y;
            break;
        case LAV_EV_POINTER_UP:
            s->down = 0;
            break;
        case LAV_EV_MENU:
            if (ev.id == MENU_CLEAR) {
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
