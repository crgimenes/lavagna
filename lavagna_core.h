/* The state behind a lavagna and what every backend shares: the event
   queue, the dirty region, the buffer's layout on the drawable (in
   lavagna_core.c, free of libc), and on Apple's systems files and the
   replay (lavagna_apple.c). Internal to the backends. */
#ifndef LAVAGNA_CORE_H
#define LAVAGNA_CORE_H

#include "lavagna.h"

enum {
    EVENTS_MAX = 4096,
    SIDE_MAX = 16384,
    PATH_CAP = 4096,
    TEXT_CAP = 1024,
    REPLAY_MAX = 1024 * 1024,
    ALERT_BUTTONS_MAX = 3,
};

struct lavagna {
    lav_config cfg;
    lav_event queue[EVENTS_MAX];
    uint32_t head;
    uint32_t len;
    uint32_t dropped;
    uint32_t *pixels;
    int32_t width;
    int32_t height;
    int follow;
    int dirty;
    int32_t dx0;
    int32_t dy0;
    int32_t dx1;
    int32_t dy1;
    int redraw;
    int quit;
    uint32_t mods;
    uint64_t frame_ns;
    uint32_t frames;
    /* Where the buffer sits on the drawable: device pixels per buffer pixel
       and the top-left corner. */
    int32_t scale;
    int32_t offx;
    int32_t offy;
    int32_t device_scale;
    char *replay;      /* LAVAGNA_EVENTS, read whole; NULL when not replaying */
    char *replay_next; /* the next line to run */
    int replay_down;
    lav_cursor_kind cursor;
    char panel_path[PATH_CAP];
    char alert_text[TEXT_CAP];
    void *window; /* the platform's window, not retained */
};

/* lavagna_core.c */
void lavagna_push(lavagna *lv, lav_event ev);
void lavagna_copy_text(char *dst, size_t cap, const char *src);
int lavagna_valid(const lav_config *cfg);
/* A drawable of dw x dh device pixels: the buffer follows it or is placed
   on it. Returns 1 when the buffer was reallocated. */
int lavagna_layout(lavagna *lv, int32_t dw, int32_t dh);

/* Each platform: the clock, and a zeroed buffer of w x h (0 when it cannot). */
uint64_t lavagna_now_ns(void);
int lavagna_alloc(lavagna *lv, int32_t w, int32_t h);

/* lavagna_apple.c */
/* Checks the config and prepares the buffer and the replay; 0 on error. */
int lavagna_start(lavagna *lv);
/* Runs the replay lines due this frame, before or after it is drawn.
   Returns 1 when the replay asks to quit. */
int lavagna_replay(lavagna *lv, int after_draw);

#endif
