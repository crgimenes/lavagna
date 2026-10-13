# lavagna

A window, a pixel buffer, input and time for small programs written in C.

The platform owns `main` and the loop. A program defines two functions and
includes nothing but `lavagna.h`, which needs only the freestanding headers:

```c
#include "lavagna.h"

void lav_setup(lav_config *cfg) {
    cfg->title = "hello";
    cfg->width = 128; /* 0 x 0 follows the window in device pixels */
    cfg->height = 96;
    cfg->scale = 6;
}

void lav_frame(lavagna *lv, void *user) {
    lav_event ev;
    while (lav_poll(lv, &ev)) {
        if (ev.type == LAV_EV_CLOSE) {
            lav_quit(lv);
        }
    }
}
```

`lav_frame` runs once per display refresh. The buffer is `0xAARRGGBB`, kept
between frames, and only the regions passed to `lav_dirty` reach the screen.
A fixed-size buffer is shown at the largest integer scale that fits the
window, centered, with no smoothing.

Input arrives as events: pointer samples in buffer pixels (uncoalesced, with
pen pressure), scroll and pinch, physical keys named by the US layout, menu
items the program declares in `lav_config`, and a close request the program
confirms with `lav_quit`.

Native pieces a tool needs come through the same queue: open and save panels
(`lav_open_panel`, `lav_save_panel`, answered by `LAV_EV_PANEL`), alerts with
up to three buttons and an optional text field (`lav_alert`, answered by
`LAV_EV_ALERT`). They are asynchronous on every platform, since on iPadOS the
document picker is. Files are read whole (`lav_file_read`) and written by
replacing them only once the new bytes are on disk (`lav_file_write`).
`lav_cursor`, `lav_set_title`, `lav_set_edited` and `lav_device_scale` cover
the window. `lav_clipboard_set_image` and `lav_clipboard_get_image` move
images through the system clipboard (PNG and TIFF on macOS, `UIImage` on
iOS; not yet in the browser), converted by the system itself.

## Testing without a person

`LAVAGNA_EVENTS=file` replays input from a file instead of the user, one line
per event, each with the frame it arrives in:

```
# frame verb arguments [+shift] [+alt] [+cmd] [+ctrl]
10 down 504 182          # pointer down at buffer pixel (504, 182); "right" for the other button
11 move 528 182
12 up 528 182
13 key b                 # down and up; keydown / keyup for holding (space, shift)
14 menu 17               # a menu item's id
15 alert 103 0 walk 1-2  # the answer to lav_alert: id, button, text
16 panel 201 out.gesso   # the answer to a panel: id, path (or "cancel")
16 open in.gesso         # a file handed to the app, as from the Finder
17 scroll 0 -40 600 400 +cmd
18 pinch 120 600 400
19 close
30 shot frame30.ppm      # the buffer after frame 30 is drawn
31 quit
```

While replaying, panels and alerts do not open: the file answers them. A
`shot` writes the buffer as a PPM, which is how a program's screen is checked
without asking the system for screen recording. A pointer line with `touch`
arrives as a finger; `N cancel` sends `LAV_EV_POINTER_CANCEL`.

In the simulator the variable goes through `simctl`:

```
xcrun simctl install booted build/ios-sim/scribble.app
SIMCTL_CHILD_LAVAGNA_EVENTS=$PWD/events.txt xcrun simctl launch --console booted br.eti.crg.lavagna.scribble
```

## Layout

| File | What |
|---|---|
| `lavagna.h` | the API, freestanding |
| `lavagna_core.c`, `lavagna_core.h` | what every backend shares, free of libc: queue, dirty region, layout |
| `lavagna_apple.c` | what macOS and iOS share: clock, files, the replay |
| `lavagna_metal.m` | the buffer as a Metal texture, drawn at its integer scale |
| `lavagna_image.c` | pixels to and from CoreGraphics, for the clipboard |
| `lavagna_macos.m` | AppKit: window, mouse, keyboard, menus, panels, alerts |
| `lavagna_ios.m` | UIKit: scene, touch and Pencil, gestures, keyboard, menu bar, picker, alerts |
| `lavagna_wasm.c`, `lavagna.js` | the browser: the C side exports frame/event, the JavaScript side owns the canvas |

## Platforms

| Platform | Status |
|---|---|
| macOS 14+ (Cocoa, Metal) | working |
| iOS / iPadOS 17+ (UIKit, Metal) | working in the simulator; not yet on a device |
| wasm (any browser with WebAssembly) | working |

On iOS the first finger or the Pencil is the pointer (Pencil force as
pressure, every coalesced sample), two fingers pan (`LAV_EV_SCROLL`) and pinch
(`LAV_EV_PINCH`), and a press a two-finger gesture takes over ends with
`LAV_EV_POINTER_CANCEL`. A hardware keyboard sends the same keys as on the
Mac, and the declared menus become the iPadOS menu bar with their shortcuts.
Going to the background sends `LAV_EV_SUSPEND` and runs a frame at once, so
the program can save before iOS ends it. The open panel is the document
picker (the program reads a copy); the save panel, for now, writes to the
app's Documents, visible in Files.

In a browser the program and `lavagna_core.c` and `lavagna_wasm.c` build into
one `.wasm` with no C library (the examples are under 4 KB), and
`lavagna.js` runs it on a canvas: pointer events with their coalesced
samples and pen pressure, the wheel (a trackpad pinch arrives as one with
ctrlKey), physical keys by `KeyboardEvent.code`, a fixed buffer scaled by an
integer with `image-rendering: pixelated`. Files live in localStorage by
path; the open panel is a file input whose file is copied there; alerts are
`prompt` and `confirm`. A hidden page sends `LAV_EV_SUSPEND`.

## Building

| Target | What it does |
|---|---|
| `make` | `build/macos/liblavagna.a`, and `build/scribble.app` and `build/pixels.app` from `examples/` |
| `make ios` | `build/ios-sim/liblavagna.a` and the examples for the iOS simulator, signed ad hoc |
| `make wasm` | `build/wasm`: the examples as `.wasm`, `lavagna.js` and `index.html` (`?p=pixels`) |
| `make size` | executable sizes |
| `make fmt` / `make fmt-check` | clang-format |
| `make tidy` / `make check` | clang-tidy and cppcheck, warnings as errors |
| `make freestanding` | the examples as wasm32 objects, `-ffreestanding -nostdlib` |
| `make qa` | all of the above |

clang-format, clang-tidy and the wasm32 build come from LLVM under
`/opt/homebrew/opt/llvm/bin`; `LLVM=` points elsewhere.

## License

MIT
