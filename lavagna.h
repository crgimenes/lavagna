/* lavagna: a window, a pixel buffer, input and time for small programs.

   The platform owns main and the loop. The program defines lav_setup, called
   once before the window opens, and lav_frame, called once per display
   refresh on the main thread. Everything else is valid only inside lav_frame.

   This header needs only the freestanding headers: a program that includes
   nothing else builds without a C library. */
#ifndef LAVAGNA_H
#define LAVAGNA_H

#include <stddef.h>
#include <stdint.h>

typedef struct lavagna lavagna;

typedef enum {
    LAV_EV_NONE,
    /* The buffer was reallocated or its contents lost: repaint all of it. */
    LAV_EV_RESIZE,
    LAV_EV_POINTER_DOWN,
    LAV_EV_POINTER_MOVE,
    LAV_EV_POINTER_UP,
    LAV_EV_KEY_DOWN,
    LAV_EV_KEY_UP,
    /* Window close or Quit. Nothing closes until the program calls lav_quit. */
    LAV_EV_CLOSE,
    /* Scroll or two-finger pan: scroll_x and scroll_y in buffer pixels, the
       platform's direction (natural scrolling applied); x and y where the
       pointer is. */
    LAV_EV_SCROLL,
    /* Pinch: zoom in thousandths of a magnification step, positive to
       enlarge; x and y where the pointer is. */
    LAV_EV_PINCH,
    /* A touch that began as the pointer turned out to be a two-finger
       gesture: take back what its press started. */
    LAV_EV_POINTER_CANCEL,
    /* The app is going to the background, where iOS may end it without a
       word: save now. lav_frame runs at once for this event. */
    LAV_EV_SUSPEND,
} lav_event_type;

typedef enum {
    LAV_POINTER_MOUSE,
    LAV_POINTER_PEN,
    LAV_POINTER_TOUCH,
} lav_pointer_kind;

#define LAV_MOD_SHIFT 0x1u
#define LAV_MOD_CTRL 0x2u
#define LAV_MOD_ALT 0x4u
#define LAV_MOD_CMD 0x8u

enum {
    LAV_BUTTON_PRIMARY = 0,
    LAV_BUTTON_SECONDARY = 1,
    LAV_BUTTON_MIDDLE = 2,
};

enum {
    LAV_PRESSURE_MAX = 65535,
};

/* Keys are physical and named by the US layout: 'a'..'z' and '0'..'9' are
   the ASCII codes, punctuation is its unshifted ASCII character, and the
   rest start at LAV_KEY_ESCAPE. */
enum {
    LAV_KEY_ESCAPE = 0x100,
    LAV_KEY_ENTER,
    LAV_KEY_TAB,
    LAV_KEY_BACKSPACE,
    LAV_KEY_DELETE,
    LAV_KEY_LEFT,
    LAV_KEY_RIGHT,
    LAV_KEY_UP,
    LAV_KEY_DOWN,
    LAV_KEY_HOME,
    LAV_KEY_END,
    LAV_KEY_PAGE_UP,
    LAV_KEY_PAGE_DOWN,
    LAV_KEY_SHIFT,
    LAV_KEY_CTRL,
    LAV_KEY_ALT,
    LAV_KEY_CMD,
    LAV_KEY_F1,
    LAV_KEY_F2,
    LAV_KEY_F3,
    LAV_KEY_F4,
    LAV_KEY_F5,
    LAV_KEY_F6,
    LAV_KEY_F7,
    LAV_KEY_F8,
    LAV_KEY_F9,
    LAV_KEY_F10,
    LAV_KEY_F11,
    LAV_KEY_F12,
};

typedef struct {
    lav_event_type type;
    uint32_t mods;
    uint64_t time_ns;
    /* Pointer events: buffer pixels, outside the buffer while dragging out. */
    int32_t x;
    int32_t y;
    uint32_t pressure;
    uint8_t button;
    uint8_t pointer;
    /* Key events. */
    uint8_t repeat;
    uint32_t key;
    int32_t scroll_x;
    int32_t scroll_y;
    int32_t zoom;
} lav_event;

typedef struct {
    const char *title;
    /* 0 x 0 makes the buffer follow the window in device pixels. Otherwise the
       buffer has this size and is shown at the largest integer scale that
       fits, centered. */
    int32_t width;
    int32_t height;
    /* Initial window size, in buffer pixels times this. */
    int32_t scale;
    void *user;
} lav_config;

/* Pixels are 0xAARRGGBB; alpha is ignored on screen. */
typedef struct {
    uint32_t *pixels;
    int32_t width;
    int32_t height;
    int32_t stride; /* in pixels */
} lav_buffer;

void lav_setup(lav_config *cfg);
void lav_frame(lavagna *lv, void *user);

/* Returns 1 and fills ev while events remain, 0 when the queue is empty. */
int lav_poll(lavagna *lv, lav_event *ev);
lav_buffer lav_pixels(lavagna *lv);
/* Only marked pixels reach the screen. */
void lav_dirty(lavagna *lv, int32_t x, int32_t y, int32_t width, int32_t height);
uint64_t lav_time_ns(const lavagna *lv);
void lav_set_title(lavagna *lv, const char *title);
/* Device pixels per point of the window's screen: 1, 2 or 3. */
int32_t lav_device_scale(const lavagna *lv);
void lav_quit(lavagna *lv);

typedef enum {
    LAV_CURSOR_ARROW,
    LAV_CURSOR_CROSSHAIR,
    LAV_CURSOR_HAND,
    LAV_CURSOR_GRAB,
} lav_cursor_kind;

void lav_cursor(lavagna *lv, lav_cursor_kind kind);

/* Whole files, UTF-8 paths. lav_file_read returns the file's size, or -1;
   nothing past cap is read, so a size over cap means it did not fit.
   lav_file_write replaces the file only once the new bytes are on disk. */
int64_t lav_file_read(lavagna *lv, const char *path, uint8_t *dst, size_t cap);
int lav_file_write(lavagna *lv, const char *path, const uint8_t *data, size_t len);

#endif
