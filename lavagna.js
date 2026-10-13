// lavagna.js: the browser half of a lavagna program built for wasm32.
// lavagna("scribble.wasm", canvas) runs it on that canvas. The numbers
// below mirror lavagna.h.
"use strict";

const LAV = {
  POINTER_DOWN: 2, POINTER_MOVE: 3, POINTER_UP: 4, KEY_DOWN: 5, KEY_UP: 6,
  SCROLL: 9, PINCH: 10, PANEL: 11, ALERT: 12, POINTER_CANCEL: 13, SUSPEND: 14, OPEN: 15,
  MOD_SHIFT: 1, MOD_CTRL: 2, MOD_ALT: 4, MOD_CMD: 8,
  MOUSE: 0, PEN: 1, TOUCH: 2,
  PRESSURE_MAX: 65535,
  TEXT_ALERT: 0, TEXT_PANEL: 1,
};

// KeyboardEvent.code to lavagna's physical keys, named by the US layout.
const KEYS = (() => {
  const k = {
    Escape: 0x100, Enter: 0x101, Tab: 0x102, Backspace: 0x103, Delete: 0x104,
    ArrowLeft: 0x105, ArrowRight: 0x106, ArrowUp: 0x107, ArrowDown: 0x108,
    Home: 0x109, End: 0x10a, PageUp: 0x10b, PageDown: 0x10c,
    ShiftLeft: 0x10d, ShiftRight: 0x10d, ControlLeft: 0x10e, ControlRight: 0x10e,
    AltLeft: 0x10f, AltRight: 0x10f, MetaLeft: 0x110, MetaRight: 0x110,
    Space: 32, Minus: 45, Equal: 61, BracketLeft: 91, BracketRight: 93,
    Backslash: 92, Semicolon: 59, Quote: 39, Backquote: 96, Comma: 44,
    Period: 46, Slash: 47,
  };
  for (let i = 0; i < 26; i++) k["Key" + String.fromCharCode(65 + i)] = 97 + i;
  for (let i = 0; i < 10; i++) k["Digit" + i] = 48 + i;
  for (let i = 1; i <= 12; i++) k["F" + i] = 0x111 + i - 1;
  return k;
})();

async function lavagna(url, canvas) {
  let ex = null;
  const dec = new TextDecoder();
  const enc = new TextEncoder();
  const ctx = canvas.getContext("2d");
  const bytes = (p, n) => new Uint8Array(ex.memory.buffer, p, n);
  const str = (p) => {
    if (p === 0) return null;
    const b = new Uint8Array(ex.memory.buffer, p);
    let n = 0;
    while (b[n] !== 0) n++;
    return dec.decode(b.subarray(0, n));
  };
  const put = (which, s) => {
    const cap = ex.text_capacity(which) - 1;
    let b = enc.encode(s);
    if (b.length > cap) b = b.subarray(0, cap);
    const dst = bytes(ex.text_buffer(which), b.length + 1);
    dst.set(b);
    dst[b.length] = 0;
  };
  const send = (type, o = {}) => ex.event(type, o.x | 0, o.y | 0, o.button | 0, o.pointer | 0,
    o.pressure | 0, o.mods | 0, o.key | 0, o.sx | 0, o.sy | 0, o.zoom | 0, o.id | 0);
  const store = (path) => "lavagna:" + path;

  const imports = {
    lavagna: {
      present(rgba, w, h, x, y, dw, dh) {
        if (canvas.width !== w || canvas.height !== h) {
          canvas.width = w;
          canvas.height = h;
          fit();
        }
        const img = new ImageData(new Uint8ClampedArray(ex.memory.buffer, rgba, w * h * 4), w, h);
        ctx.putImageData(img, 0, 0, x, y, dw, dh);
      },
      title(p) { document.title = str(p); },
      cursor(k) { canvas.style.cursor = ["default", "crosshair", "grab", "grabbing"][k] || "default"; },
      // window.prompt and confirm, after the frame: blocking inside one
      // would stop the program mid-call.
      alert(id, title, message, b0, b1, b2, n, text) {
        const head = str(title) + (str(message) ? "\n\n" + str(message) : "");
        const names = [str(b0), str(b1), str(b2)].slice(0, n);
        const initial = str(text);
        setTimeout(() => {
          let button = 0;
          if (initial !== null) {
            const r = window.prompt(head, initial);
            button = r === null ? Math.max(n - 1, 0) : 0;
            put(LAV.TEXT_ALERT, r === null ? "" : r);
          } else if (n >= 2) {
            const ok = window.confirm(head + "\n\nOK: " + names[0] + "    Cancel: " + names[n - 1]);
            button = ok ? 0 : n - 1;
          } else {
            window.alert(head);
          }
          send(LAV.ALERT, { button, id });
        }, 0);
      },
      file_read(path, dst, cap) {
        const v = localStorage.getItem(store(str(path)));
        if (v === null) return -1;
        const n = Math.min(v.length, cap);
        const b = bytes(dst, n);
        for (let i = 0; i < n; i++) b[i] = v.charCodeAt(i);
        return v.length;
      },
      file_write(path, data, len) {
        const b = bytes(data, len);
        let s = "";
        for (let i = 0; i < len; i += 8192) {
          s += String.fromCharCode.apply(null, b.subarray(i, Math.min(i + 8192, len)));
        }
        try {
          localStorage.setItem(store(str(path)), s);
          return 1;
        } catch (e) {
          return 0;
        }
      },
      // The file chosen is copied into localStorage under its name, which
      // becomes the path the program reads.
      open_panel(id, ext) {
        const input = document.createElement("input");
        input.type = "file";
        input.accept = "." + str(ext);
        input.onchange = async () => {
          const f = input.files[0];
          if (!f) {
            send(LAV.PANEL, { button: 0, id });
            return;
          }
          const b = new Uint8Array(await f.arrayBuffer());
          let s = "";
          for (let i = 0; i < b.length; i += 8192) {
            s += String.fromCharCode.apply(null, b.subarray(i, Math.min(i + 8192, b.length)));
          }
          localStorage.setItem(store(f.name), s);
          put(LAV.TEXT_PANEL, f.name);
          send(LAV.PANEL, { button: 1, id });
        };
        input.click();
      },
    },
  };

  const res = await fetch(url);
  const { instance } = await WebAssembly.instantiate(await res.arrayBuffer(), imports);
  ex = instance.exports;
  const mode = ex.setup();
  if (mode < 0) throw new Error("lavagna: the program's setup is invalid");
  const fixed = mode === 1;

  canvas.style.touchAction = "none";
  canvas.style.imageRendering = "pixelated";
  // A fixed buffer is shown at the largest integer scale that fits, in
  // device pixels; one that follows the window fills it.
  function fit() {
    const dpr = window.devicePixelRatio || 1;
    const box = canvas.parentElement.getBoundingClientRect();
    const dw = Math.max(1, Math.round(box.width * dpr));
    const dh = Math.max(1, Math.round(box.height * dpr));
    if (fixed) {
      const w = ex.buffer_width();
      const h = ex.buffer_height();
      const s = Math.max(1, Math.floor(Math.min(dw / w, dh / h)));
      canvas.style.width = (w * s) / dpr + "px";
      canvas.style.height = (h * s) / dpr + "px";
    } else {
      canvas.style.width = box.width + "px";
      canvas.style.height = box.height + "px";
    }
    ex.resize(dw, dh, Math.round(dpr));
  }
  new ResizeObserver(fit).observe(canvas.parentElement);
  fit();

  const mods = (e) => (e.shiftKey ? LAV.MOD_SHIFT : 0) | (e.ctrlKey ? LAV.MOD_CTRL : 0) |
    (e.altKey ? LAV.MOD_ALT : 0) | (e.metaKey ? LAV.MOD_CMD : 0);
  const at = (e) => {
    const r = canvas.getBoundingClientRect();
    return {
      x: Math.floor(((e.clientX - r.left) / r.width) * ex.buffer_width()),
      y: Math.floor(((e.clientY - r.top) / r.height) * ex.buffer_height()),
    };
  };
  const buttonOf = (b) => (b === 2 ? 1 : b === 1 ? 2 : 0);
  const kind = (e) => (e.pointerType === "pen" ? LAV.PEN : e.pointerType === "touch" ? LAV.TOUCH : LAV.MOUSE);
  let held = 0;
  const pointer = (type, e, button) => {
    const p = at(e);
    const down = type !== LAV.POINTER_UP && held !== 0;
    let pressure = down ? LAV.PRESSURE_MAX : 0;
    if (down && e.pointerType === "pen") pressure = Math.round(e.pressure * LAV.PRESSURE_MAX);
    send(type, { ...p, button, pointer: kind(e), pressure, mods: mods(e) });
  };
  canvas.addEventListener("pointerdown", (e) => {
    if (!e.isPrimary) return;
    try {
      canvas.setPointerCapture(e.pointerId);
    } catch (err) {
      // a pointer the browser does not know (a synthetic one) is not captured
    }
    held = 1;
    pointer(LAV.POINTER_DOWN, e, buttonOf(e.button));
    e.preventDefault();
  });
  canvas.addEventListener("pointermove", (e) => {
    if (!e.isPrimary) return;
    const button = (e.buttons & 2) !== 0 ? 1 : (e.buttons & 4) !== 0 ? 2 : 0;
    // Every sample since the last event; none at all for a synthetic one.
    const list = e.getCoalescedEvents ? e.getCoalescedEvents() : [];
    for (const c of list.length > 0 ? list : [e]) {
      pointer(LAV.POINTER_MOVE, c, button);
    }
  });
  canvas.addEventListener("pointerup", (e) => {
    if (!e.isPrimary) return;
    held = 0;
    pointer(LAV.POINTER_UP, e, buttonOf(e.button));
  });
  canvas.addEventListener("pointercancel", (e) => {
    if (!e.isPrimary) return;
    held = 0;
    pointer(LAV.POINTER_CANCEL, e, 0);
  });
  canvas.addEventListener("contextmenu", (e) => e.preventDefault());
  // A trackpad pinch reaches the page as a wheel with ctrlKey set.
  canvas.addEventListener("wheel", (e) => {
    e.preventDefault();
    const p = at(e);
    if (e.ctrlKey) {
      send(LAV.PINCH, { ...p, zoom: Math.round(-e.deltaY * 10) });
      return;
    }
    const k = (e.deltaMode === 1 ? 16 : 1) * (window.devicePixelRatio || 1);
    send(LAV.SCROLL, { ...p, sx: Math.round(-e.deltaX * k), sy: Math.round(-e.deltaY * k), mods: mods(e) });
  }, { passive: false });
  const key = (type) => (e) => {
    const k = KEYS[e.code];
    if (k === undefined) return;
    if (!e.metaKey && !e.ctrlKey) e.preventDefault();
    send(type, { key: k, mods: mods(e) });
  };
  window.addEventListener("keydown", key(LAV.KEY_DOWN));
  window.addEventListener("keyup", key(LAV.KEY_UP));
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "hidden") {
      send(LAV.SUSPEND);
      ex.frame(performance.now());
    }
  });

  requestAnimationFrame(function tick(t) {
    if (ex.frame(t)) return;
    requestAnimationFrame(tick);
  });
  return ex;
}
