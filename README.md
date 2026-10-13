# lavagna

A window, a pixel buffer, input and time for small games written in C.

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
pen pressure), scroll and pinch, physical keys named by the US layout, and a
close request the program confirms with `lav_quit`.

Files are read whole (`lav_file_read`) and written by replacing them only
once the new bytes are on disk (`lav_file_write`). `lav_cursor`,
`lav_set_title` and `lav_device_scale` cover the window. On macOS the menu
bar is the standard one: About, Hide, Quit and the Window menu.

## Testing without a person

`LAVAGNA_EVENTS=file` replays input from a file instead of the user, one line
per event, each with the frame it arrives in:

```
# frame verb arguments [+shift] [+alt] [+cmd] [+ctrl]
10 down 504 182          # pointer down at buffer pixel (504, 182); "right" for the other button
11 move 528 182
12 up 528 182
13 key b                 # down and up; keydown / keyup for holding (space, shift)
14 scroll 0 -40 600 400 +cmd
15 pinch 120 600 400
16 close
30 shot frame30.ppm      # the buffer after frame 30 is drawn
31 quit
```

A `shot` writes the buffer as a PPM, which is how a program's screen is
checked without asking the system for screen recording. A pointer line with `touch`
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
| `lavagna_macos.m` | AppKit: window, mouse, keyboard, the standard menu bar |
| `lavagna_ios.m` | UIKit: scene, touch and Pencil, gestures, keyboard |
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
Mac. Going to the background sends `LAV_EV_SUSPEND` and runs a frame at
once, so the program can save before iOS ends it.

In a browser the program and `lavagna_core.c` and `lavagna_wasm.c` build into
one `.wasm` with no C library (the examples are under 4 KB), and
`lavagna.js` runs it on a canvas: pointer events with their coalesced
samples and pen pressure, the wheel (a trackpad pinch arrives as one with
ctrlKey), physical keys by `KeyboardEvent.code`, a fixed buffer scaled by an
integer with `image-rendering: pixelated`. Files live in localStorage by
path. A hidden page sends `LAV_EV_SUSPEND`.

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
