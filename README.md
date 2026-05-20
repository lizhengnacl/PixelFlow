# PixelFlow

PixelFlow is a lightweight macOS menu bar app that visualizes upload and download traffic with two independent pixel-art animations.

## Requirements

- macOS 13 Ventura or newer
- Xcode 16 command line tools or compatible Swift toolchain

## Run From Source

```sh
swift run PixelFlow
```

Running from SwiftPM is useful during development. For normal menu bar usage, build the `.app` bundle so `LSUIElement` and login-item registration are available:

```sh
./Scripts/build-app.sh
open .build/PixelFlow.app
```

## MVP Features

- Two menu bar icons: upload faces right, download faces left
- Pixel-art idle, walk, and run animation states
- Animation speed and color react continuously to measured traffic
- System network counters sampled through macOS routing interface stats
- Low-pass smoothing to avoid jitter
- Shared menu with live upload/download rates, launch-at-login toggle, about, and quit

## Notes

The current build script creates a development `.app` for the host architecture. Use Xcode archive or a dedicated release pipeline when producing a signed universal binary.
