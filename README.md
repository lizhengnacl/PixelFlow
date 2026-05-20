# PixelFlow

PixelFlow is a lightweight macOS menu bar app that visualizes upload/download traffic and optional system metrics with pixel-art menu bar icons.

## Requirements

- macOS 13 Ventura or newer
- Xcode 16 command line tools or compatible Swift toolchain

## Commands

### Development

Run the app directly from SwiftPM:

```sh
swift run PixelFlow
```

This is useful for quick development checks. Because this path does not launch the
packaged `.app`, normal menu bar behavior that depends on `LSUIElement` or
login-item registration should be verified with the app bundle.

### Debugging

Build and run the debug executable:

```sh
swift build -c debug
swift run PixelFlow
```

For local UI debugging, rebuild and restart the menu bar app with one command:

```sh
./Scripts/restart-app.sh
```

### Build

Build a release `.app` bundle:

```sh
./Scripts/build-app.sh
```

Open the built app:

```sh
open .build/PixelFlow.app
```

### Install

Install the built app for the current user:

```sh
./Scripts/build-app.sh
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/PixelFlow.app"
cp -R .build/PixelFlow.app "$HOME/Applications/PixelFlow.app"
open "$HOME/Applications/PixelFlow.app"
```

## MVP Features

- Two menu bar icons: upload faces right, download faces left
- Pixel-art idle, walk, and run animation states
- Animation speed and color react continuously to measured traffic
- System network counters sampled through macOS routing interface stats
- Low-pass smoothing to avoid jitter
- Optional pixel-art indicators for memory usage, disk usage, CPU temperature, fan speed, CPU usage, and GPU usage
- Per-item visibility toggles for upload/download and system metrics in the Display Items menu
- Shared menu with live upload/download rates, launch-at-login toggle, about, and quit

## Notes

The current build script creates a development `.app` for the host architecture. Use Xcode archive or a dedicated release pipeline when producing a signed universal binary.
