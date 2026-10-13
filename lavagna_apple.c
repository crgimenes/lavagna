#include "lavagna_core.h"

#include <errno.h>
#include <fcntl.h>
#include <mach/mach_time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

enum {
    FILE_MODE = 0644,
};

uint64_t lavagna_now_ns(void) {
    static mach_timebase_info_data_t tb;
    if (tb.denom == 0) {
        mach_timebase_info(&tb);
    }
    return mach_absolute_time() * tb.numer / tb.denom;
}

int lavagna_alloc(lavagna *lv, int32_t w, int32_t h) {
    uint32_t *p = calloc((size_t)w * (size_t)h, sizeof *p);
    if (p == NULL) {
        return 0;
    }
    free(lv->pixels);
    lv->pixels = p;
    lv->width = w;
    lv->height = h;
    return 1;
}

int64_t lav_file_read(lavagna *lv, const char *path, uint8_t *dst, size_t cap) {
    (void)lv;
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        return -1;
    }
    struct stat st;
    if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode)) {
        (void)close(fd);
        return -1;
    }
    size_t want = (size_t)st.st_size < cap ? (size_t)st.st_size : cap;
    size_t got = 0;
    while (got < want) {
        ssize_t n = read(fd, dst + got, want - got);
        if (n < 0 && errno == EINTR) {
            continue;
        }
        if (n <= 0) {
            (void)close(fd);
            return -1;
        }
        got += (size_t)n;
    }
    (void)close(fd);
    return (int64_t)st.st_size;
}

/* A temporary file beside the target, synced, then renamed over it: a crash
   leaves the old file or the new one, never half of either. */
int lav_file_write(lavagna *lv, const char *path, const uint8_t *data, size_t len) {
    (void)lv;
    char tmp[PATH_CAP];
    int n = snprintf(tmp, sizeof tmp, "%s.XXXXXX", path);
    if (n < 0 || (size_t)n >= sizeof tmp) {
        return 0;
    }
    int fd = mkstemp(tmp);
    if (fd < 0) {
        return 0;
    }
    size_t done = 0;
    while (done < len) {
        ssize_t w = write(fd, data + done, len - done);
        if (w < 0 && errno == EINTR) {
            continue;
        }
        if (w < 0) {
            break;
        }
        done += (size_t)w;
    }
    int ok = done == len && fchmod(fd, FILE_MODE) == 0 && fsync(fd) == 0;
    ok = close(fd) == 0 && ok;
    if (!ok || rename(tmp, path) != 0) {
        (void)unlink(tmp);
        return 0;
    }
    return 1;
}

int lavagna_start(lavagna *lv) {
    lv->scale = 1;
    lv->device_scale = 1;
    if (!lavagna_valid(&lv->cfg)) {
        fprintf(stderr, "lavagna: invalid lav_config\n");
        return 0;
    }
    lv->follow = lv->cfg.width == 0;
    const char *events = getenv("LAVAGNA_EVENTS");
    if (events != NULL) {
        lv->replay = calloc(1, REPLAY_MAX + 1);
        if (lv->replay == NULL ||
            lav_file_read(lv, events, (uint8_t *)lv->replay, REPLAY_MAX) < 0) {
            fprintf(stderr, "lavagna: cannot read LAVAGNA_EVENTS %s\n", events);
            return 0;
        }
        lv->replay_next = lv->replay;
    }
    if (!lv->follow) {
        if (!lavagna_alloc(lv, lv->cfg.width, lv->cfg.height)) {
            fprintf(stderr, "lavagna: out of memory\n");
            return 0;
        }
        lavagna_push(lv, (lav_event){.type = LAV_EV_RESIZE, .time_ns = lavagna_now_ns()});
    }
    return 1;
}

/* ---- replay ---- */

/* The buffer as the program drew it, as a PPM: seeing the screen without
   asking the system to record it. */
static int shot(lavagna *lv, const char *path) {
    size_t n = (size_t)lv->width * (size_t)lv->height;
    uint8_t *rgb = malloc(n * 3 + 64);
    if (rgb == NULL) {
        return 0;
    }
    int head = snprintf((char *)rgb, 64, "P6\n%d %d\n255\n", lv->width, lv->height);
    for (size_t i = 0; i < n; i++) {
        uint32_t p = lv->pixels[i];
        rgb[(size_t)head + i * 3] = (uint8_t)(p >> 16u);
        rgb[(size_t)head + i * 3 + 1] = (uint8_t)(p >> 8u);
        rgb[(size_t)head + i * 3 + 2] = (uint8_t)p;
    }
    int ok = lav_file_write(lv, path, rgb, (size_t)head + n * 3);
    free(rgb);
    return ok;
}

static const struct {
    const char *name;
    uint32_t key;
} key_names[] = {
    {"escape", LAV_KEY_ESCAPE}, {"enter", LAV_KEY_ENTER},
    {"tab", LAV_KEY_TAB},       {"backspace", LAV_KEY_BACKSPACE},
    {"delete", LAV_KEY_DELETE}, {"left", LAV_KEY_LEFT},
    {"right", LAV_KEY_RIGHT},   {"up", LAV_KEY_UP},
    {"down", LAV_KEY_DOWN},     {"space", ' '},
    {"shift", LAV_KEY_SHIFT},   {"alt", LAV_KEY_ALT},
    {"cmd", LAV_KEY_CMD},       {"ctrl", LAV_KEY_CTRL},
};

static uint32_t key_named(const char *s) {
    for (size_t i = 0; i < sizeof key_names / sizeof key_names[0]; i++) {
        if (strcmp(s, key_names[i].name) == 0) {
            return key_names[i].key;
        }
    }
    return s[1] == '\0' ? (uint32_t)(unsigned char)s[0] : 0;
}

static lav_event_type pointer_verb(const char *verb) {
    if (strcmp(verb, "down") == 0) {
        return LAV_EV_POINTER_DOWN;
    }
    if (strcmp(verb, "move") == 0) {
        return LAV_EV_POINTER_MOVE;
    }
    if (strcmp(verb, "up") == 0) {
        return LAV_EV_POINTER_UP;
    }
    return LAV_EV_NONE;
}

enum {
    WORDS_MAX = 8,
    LINE_CAP = PATH_CAP + 64,
};

/* A replay line split at spaces; raw keeps it whole for an alert's text. */
typedef struct {
    char raw[LINE_CAP];
    char buf[LINE_CAP];
    char *word[WORDS_MAX];
    int n;
} words;

static void split(const char *src, size_t len, words *w) {
    if (len >= LINE_CAP) {
        len = LINE_CAP - 1;
    }
    memcpy(w->raw, src, len);
    w->raw[len] = '\0';
    memcpy(w->buf, w->raw, len + 1);
    w->n = 0;
    char *p = w->buf;
    while (*p != '\0' && w->n < WORDS_MAX) {
        while (*p == ' ' || *p == '\t' || *p == '\r') {
            *p++ = '\0';
        }
        if (*p == '\0') {
            break;
        }
        w->word[w->n++] = p;
        while (*p != '\0' && *p != ' ' && *p != '\t' && *p != '\r') {
            p++;
        }
    }
}

/* Word i as a whole decimal number. */
static int num(const words *w, int i, int32_t *out) {
    if (i >= w->n) {
        return 0;
    }
    char *end = NULL;
    errno = 0;
    long v = strtol(w->word[i], &end, 10);
    if (end == w->word[i] || *end != '\0' || errno != 0 || v < INT32_MIN || v > INT32_MAX) {
        return 0;
    }
    *out = (int32_t)v;
    return 1;
}

static int has(const words *w, const char *word) {
    for (int i = 0; i < w->n; i++) {
        if (strcmp(w->word[i], word) == 0) {
            return 1;
        }
    }
    return 0;
}

static uint32_t mods_named(const words *w) {
    uint32_t m = 0;
    m |= has(w, "+shift") ? LAV_MOD_SHIFT : 0;
    m |= has(w, "+alt") ? LAV_MOD_ALT : 0;
    m |= has(w, "+cmd") ? LAV_MOD_CMD : 0;
    m |= has(w, "+ctrl") ? LAV_MOD_CTRL : 0;
    return m;
}

/* The raw text after the first n words. */
static const char *after_words(const char *t, int n) {
    for (int k = 0; k < n; k++) {
        while (*t == ' ') {
            t++;
        }
        while (*t != ' ' && *t != '\0') {
            t++;
        }
    }
    while (*t == ' ') {
        t++;
    }
    return t;
}

static void replay_pointer(lavagna *lv, const words *w, lav_event ev) {
    if (!num(w, 2, &ev.x) || !num(w, 3, &ev.y)) {
        return;
    }
    ev.button = has(w, "right") ? LAV_BUTTON_SECONDARY : LAV_BUTTON_PRIMARY;
    ev.pointer = has(w, "touch") ? LAV_POINTER_TOUCH : LAV_POINTER_MOUSE;
    if (ev.type == LAV_EV_POINTER_DOWN) {
        lv->replay_down = 1;
    } else if (ev.type == LAV_EV_POINTER_UP) {
        lv->replay_down = 0;
    }
    ev.pressure = lv->replay_down ? LAV_PRESSURE_MAX : 0;
    lavagna_push(lv, ev);
}

static void replay_key(lavagna *lv, const words *w, lav_event ev, const char *verb) {
    if (w->n < 3) {
        return;
    }
    ev.key = key_named(w->word[2]);
    if (ev.key == 0) {
        return;
    }
    ev.type = strcmp(verb, "keyup") == 0 ? LAV_EV_KEY_UP : LAV_EV_KEY_DOWN;
    lavagna_push(lv, ev);
    if (strcmp(verb, "key") == 0) {
        ev.type = LAV_EV_KEY_UP;
        lavagna_push(lv, ev);
    }
}

/* One line of the replay: "frame verb args [+shift] [+alt] [+cmd] [+ctrl]".
   Coordinates are buffer pixels. */
static void replay_line(lavagna *lv, const words *w, int *quit) {
    const char *verb = w->word[1];
    int32_t a = 0;
    int32_t b = 0;
    lav_event ev = {.time_ns = lavagna_now_ns(), .mods = mods_named(w)};
    ev.type = pointer_verb(verb);
    if (ev.type != LAV_EV_NONE) {
        replay_pointer(lv, w, ev);
    } else if (strcmp(verb, "key") == 0 || strcmp(verb, "keydown") == 0 ||
               strcmp(verb, "keyup") == 0) {
        replay_key(lv, w, ev, verb);
    } else if (strcmp(verb, "menu") == 0 && num(w, 2, &a)) {
        ev.type = LAV_EV_MENU;
        ev.id = (uint32_t)a;
        lavagna_push(lv, ev);
    } else if (strcmp(verb, "alert") == 0 && num(w, 2, &a) && num(w, 3, &b)) {
        lavagna_copy_text(lv->alert_text, TEXT_CAP, after_words(w->raw, 4));
        ev.type = LAV_EV_ALERT;
        ev.id = (uint32_t)a;
        ev.button = (uint8_t)b;
        lavagna_push(lv, ev);
    } else if (strcmp(verb, "panel") == 0 && num(w, 2, &a) && w->n >= 4) {
        lavagna_copy_text(lv->panel_path, PATH_CAP, w->word[3]);
        ev.type = LAV_EV_PANEL;
        ev.id = (uint32_t)a;
        ev.button = strcmp(w->word[3], "cancel") != 0;
        lavagna_push(lv, ev);
    } else if (strcmp(verb, "scroll") == 0 && num(w, 2, &ev.scroll_x) && num(w, 3, &ev.scroll_y) &&
               num(w, 4, &ev.x) && num(w, 5, &ev.y)) {
        ev.type = LAV_EV_SCROLL;
        lavagna_push(lv, ev);
    } else if (strcmp(verb, "pinch") == 0 && num(w, 2, &ev.zoom) && num(w, 3, &ev.x) &&
               num(w, 4, &ev.y)) {
        ev.type = LAV_EV_PINCH;
        lavagna_push(lv, ev);
    } else if (strcmp(verb, "open") == 0 && w->n >= 3) {
        lavagna_copy_text(lv->panel_path, PATH_CAP, w->word[2]);
        ev.type = LAV_EV_OPEN;
        lavagna_push(lv, ev);
    } else if (strcmp(verb, "cancel") == 0) {
        ev.type = LAV_EV_POINTER_CANCEL;
        lavagna_push(lv, ev);
    } else if (strcmp(verb, "close") == 0) {
        ev.type = LAV_EV_CLOSE;
        lavagna_push(lv, ev);
    } else if (strcmp(verb, "quit") == 0) {
        *quit = 1;
    }
}

int lavagna_replay(lavagna *lv, int after_draw) {
    int quit = 0;
    static words w;
    while (lv->replay_next != NULL && *lv->replay_next != '\0') {
        char *line = lv->replay_next;
        char *eol = strchr(line, '\n');
        split(line, eol != NULL ? (size_t)(eol - line) : strlen(line), &w);
        int32_t frame = 0;
        if (line[0] == '#' || w.n < 2 || !num(&w, 0, &frame)) {
            lv->replay_next = eol != NULL ? eol + 1 : NULL;
            continue;
        }
        if ((uint32_t)frame > lv->frames) {
            break;
        }
        int is_shot = strcmp(w.word[1], "shot") == 0;
        int is_quit = strcmp(w.word[1], "quit") == 0;
        if ((is_shot || is_quit) != after_draw) {
            break;
        }
        if (is_shot && w.n >= 3 && !shot(lv, w.word[2])) {
            fprintf(stderr, "lavagna: cannot write the shot %s\n", w.word[2]);
            exit(1);
        }
        if (!is_shot) {
            replay_line(lv, &w, &quit);
        }
        lv->replay_next = eol != NULL ? eol + 1 : NULL;
    }
    return quit;
}
