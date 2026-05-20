#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/.build/PixelFlow.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
MODULE_CACHE="$ROOT_DIR/.build/module-cache"

mkdir -p "$MODULE_CACHE"

cd "$ROOT_DIR"
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/.build/release/PixelFlow" "$MACOS_DIR/PixelFlow"
cp "$ROOT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Packaging/PixelFlow.icns" "$RESOURCES_DIR/PixelFlow.icns"

echo "Built $APP_DIR"
