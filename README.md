# KWin VRR frame pacing patches

Patch set for KWin 6.8.2 that fixes stuttery Firefox scrolling on VRR setups: Firefox does not always deliver a frame every refresh cycle, which shows up as visible stutter while scrolling, and VRR removes that by letting the display follow the client, but compositor-driven animations and cursor updates do not fit the client-paced timing and judder or lag on their own.

## Changes

- Disable VRR while a compositor-driven animation runs, covering fullscreen effects and window minimize, unminimize, open and close.
- Present cursor, interactive move/resize and fullscreen effect updates without the VRR repaint throttle.

Changed files: `src/compositor.cpp`, `src/core/renderloop.cpp`, `src/effect/effecthandler.h`, `src/effect/effecthandler.cpp`.

## Usage

```bash
make build && make install   # install, then log out and back in
make status                  # build, system and backup state
make revert                  # restore the original KWin
```

`make install` backs the original binaries up once, and `/usr/bin/kwin_wayland.orig` and `/usr/lib/libkwin.so.orig` should be refreshed after a package update if `make revert` is to restore that version.

## Upgrading

```bash
make upgrade   # rebase onto the installed KWin version
make build
make install
```

`make upgrade` only rebases and does not build or install, and since a package update replaces `libkwin.so` with the unpatched build, the patched library has to be reinstalled afterwards even when no rebase was needed.
