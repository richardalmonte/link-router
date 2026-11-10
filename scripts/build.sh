#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$DIR/build"
APP_DIR="$BUILD_DIR/LinkRouter.app"

echo "🔨 Building LinkRouter for macOS..."
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$DIR/Info.plist" "$APP_DIR/Contents/Info.plist"

if [ -f "$DIR/assets/AppIcon.icns" ]; then
    cp "$DIR/assets/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

swiftc -O "$DIR/src/main.swift" -o "$APP_DIR/Contents/MacOS/LinkRouter"

echo "✅ Build successful! Bundle located at: $APP_DIR"
