---
name: chromedp-alpine-container
description: |
  Fix Chrome/Chromium startup failures in Alpine Linux containers when using chromedp
  (or similar CDP tools). Use when: (1) chromedp fails with "websocket url timeout reached",
  (2) Chrome crashes with "ZINK: vkCreateInstance failed" or "eglInitialize SwANGLE failed"
  or "glx: failed to create drisw screen", (3) running Chrome non-headless on Xvfb in
  Alpine containers, (4) Chrome starts but DevTools connection times out. Root causes:
  missing mesa software GL drivers, missing dbus, and chromedp's default WSURLReadTimeout
  being too short for containers with GL fallback overhead.
author: Claude Code
version: 1.0.0
date: 2026-02-21
---

# Chrome/Chromedp in Alpine Containers

## Problem
Chrome/Chromium fails to start or chromedp times out connecting to DevTools when running
in Alpine Linux containers, especially when running non-headless on Xvfb for screen capture.

## Context / Trigger Conditions
- `websocket url timeout reached` from chromedp
- `MESA: error: ZINK: vkCreateInstance failed (VK_ERROR_INCOMPATIBLE_DRIVER)`
- `glx: failed to create drisw screen`
- `eglInitialize SwANGLE failed with error EGL_NOT_INITIALIZED`
- `Initialization of all EGL display types failed`
- `Failed to connect to the bus: Failed to connect to socket /var/run/dbus/system_bus_socket`
- Chrome works in headless mode but fails non-headless on Xvfb

## Solution

### 1. Install required Alpine packages

```dockerfile
RUN apk add --no-cache \
    chromium nss freetype harfbuzz ttf-freefont \
    mesa-dri-gallium mesa-gl \
    dbus \
    xvfb-run xorg-server
```

Key packages:
- `mesa-dri-gallium` — software GL rasterizer (llvmpipe/softpipe) Chrome needs
- `mesa-gl` — OpenGL library
- `dbus` — Chrome queries dbus for accessibility/services; without it, startup is slow

### 2. Start dbus before Chrome

```go
exec.Command("mkdir", "-p", "/var/run/dbus").Run()
exec.Command("dbus-daemon", "--system", "--nofork").Start()
```

### 3. Increase chromedp WSURLReadTimeout

Chrome takes longer to start in containers due to GL fallback attempts. The default
chromedp timeout is often too short:

```go
opts := append(chromedp.DefaultExecAllocatorOptions[:],
    chromedp.Flag("headless", false),
    chromedp.Flag("no-sandbox", true),
    chromedp.Flag("disable-gpu", true),
    chromedp.Flag("disable-software-rasterizer", true),
    chromedp.Flag("disable-dev-shm-usage", true),
    chromedp.WSURLReadTimeout(30 * time.Second),  // default is too short
)
```

### 4. Required Chrome flags for containers

```
--no-sandbox                 # Required when running as root
--disable-gpu                # No hardware GPU available
--disable-software-rasterizer # Avoid SwANGLE failures
--disable-dev-shm-usage      # /dev/shm is only 64MB in k8s by default
```

## Verification

Test Chrome starts and DevTools listens:

```sh
Xvfb :50 -screen 0 1280x720x24 -ac -nolisten tcp &
sleep 2
DISPLAY=:50 chromium-browser --no-sandbox --disable-gpu \
  --disable-software-rasterizer --remote-debugging-port=9222 about:blank 2>&1
# Should see: DevTools listening on ws://127.0.0.1:9222/devtools/browser/...
```

## Notes
- GL errors like `ZINK: vkCreateInstance failed` are warnings, not fatal — Chrome
  still runs after fallback, but fallback takes time (causing the timeout)
- `--disable-gpu` alone is NOT sufficient — Chrome still tries to initialize GL
  for compositing even with GPU disabled
- The dbus errors are non-fatal but cause Chrome to retry connections repeatedly,
  slowing startup
- Default k8s `/dev/shm` is 64MB; use `--disable-dev-shm-usage` or mount a larger
  emptyDir at `/dev/shm`
- `chromedp.Flag("headless", false)` removes the `--headless` flag that
  `DefaultExecAllocatorOptions` includes by default
