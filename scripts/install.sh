#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$DIR/scripts/build.sh"

DEST_DIR="$HOME/Applications"
mkdir -p "$DEST_DIR"

echo "📦 Installing LinkRouter to $DEST_DIR/LinkRouter.app..."
rm -rf "$DEST_DIR/LinkRouter.app"
cp -R "$DIR/build/LinkRouter.app" "$DEST_DIR/"

CONFIG_DIR="$HOME/.config/link-router"
mkdir -p "$CONFIG_DIR"
if [ ! -f "$CONFIG_DIR/config.json" ]; then
    echo "⚙️ Creating initial config at $CONFIG_DIR/config.json..."
    cp "$DIR/config.example.json" "$CONFIG_DIR/config.json"
fi

echo "🔄 Registering with macOS LaunchServices..."
LS_REGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -f "$LS_REGISTER" ]; then
    "$LS_REGISTER" -f "$DEST_DIR/LinkRouter.app"
fi

touch "$DEST_DIR/LinkRouter.app"

echo ""
echo "🎉 LinkRouter installed successfully!"
echo ""
echo "Next step:"
echo "1. Open System Settings > Desktop & Dock > Default web browser."
echo "2. Select 'LinkRouter'."
echo ""
echo "To customize rules, edit: ~/.config/link-router/config.json"
echo "To view routing logs, check: ~/.config/link-router/router.log"
