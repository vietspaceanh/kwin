# Patch KWin to workaround the stuttering scrolling issue in Firefox

## The Problem
When using KDE Plasma, I encountered an issue where scrolling web pages in Firefox is very stuttery, despite my monitor having a high refresh rate (165Hz).
The root cause (to the best of my knowledge) is the frame pacing mismatch between KWin and Firefox.
A natural and simple fix is to **enable VRR (Adaptive Sync)** in Display Configuration. There are 2 ways:

1. **Always enable VRR**: the cursor stutters, especially when moving from one window to another.
2. **Automatic**, i.e. VRR only triggers for specific windows. We can use this approach by setting Window Rule for Firefox to force Adaptive Sync.

However, the second approach has its own issue. When triggering fullscreen animation effects, e.g. Grid or Overview or Slide (changing virtual desktop), the Firefox window will be tearing/flickering/shaking due to refresh rate change. This patch is to disable VRR when we are in fullscreen effects.


## The Fix
VRR is disabled during fullscreen effects because the effect controls timing, not the window.

Apart from Adaptive Sync, running Firefox in XWayland further improves scrolling smoothness. However, it can cause cursor stutter. Therefore, cursor updates are updated to never be throttled by VRR to ensure fluid movement at all times.

### Changes made:

1. **`src/compositor.cpp`**: Add `hasFullScreenEffect` check to the VRR policy condition, so VRR is not activated when a fullscreen effect is active. Also removes VRR delay for hardware cursor plane updates so the cursor presents immediately.

2.  **`src/core/renderloop.cpp`**: Skip VRR delay for fullscreen repaints during active effects and bypassed the 30fps throttle for cursor-related repaints to resolve XWayland cursor stutter.


## Usage
Clone this branch, then run:
```bash
make build && make install
```

To revert to system KWin:
```bash
make revert
```

Check status:
```bash
make status
```

## Upgrading after a KWin update

When the system kWin is updated (e.g. via the package manager), rebase the patch onto the matching new version tag:
```bash
make upgrade                # auto-detects the installed KWin version
make upgrade VER=6.7.3      # or specify explicitly
```

After a successful upgrade:
```bash
make build && make install
```
