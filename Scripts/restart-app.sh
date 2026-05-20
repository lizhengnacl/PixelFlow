#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="PixelFlow"
APP_DIR="$ROOT_DIR/.build/$APP_NAME.app"

"$ROOT_DIR/Scripts/build-app.sh"

if pgrep -x "$APP_NAME" >/dev/null; then
    pkill -TERM -x "$APP_NAME" || true

    for _ in {1..50}; do
        if ! pgrep -x "$APP_NAME" >/dev/null; then
            break
        fi
        sleep 0.1
    done

    if pgrep -x "$APP_NAME" >/dev/null; then
        pkill -KILL -x "$APP_NAME" || true

        for _ in {1..20}; do
            if ! pgrep -x "$APP_NAME" >/dev/null; then
                break
            fi
            sleep 0.1
        done
    fi
fi

open "$APP_DIR"
echo "Restarted $APP_DIR"
