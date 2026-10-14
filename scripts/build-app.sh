#!/usr/bin/env bash
# Builds Emma.app (a menu bar app) from the Swift package and signs it ad-hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
APP="build/Emma.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Emma" "$APP/Contents/MacOS/Emma"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Kokoro TTS sidecar, launched by the app with uv.
cp sidecars/kokoro/tts_server.py "$APP/Contents/Resources/tts_server.py"

# SwiftPM resource bundles from dependencies (tokenizer configs etc.)
find "$BIN_DIR" -maxdepth 1 -name "*.bundle" -exec cp -R {} "$APP/Contents/Resources/" \;

codesign --force --deep --sign - "$APP"
echo "Built $APP"

# Install to /Applications so Spotlight, Launchpad and the Dock can find it.
osascript -e 'quit app "Emma"' 2>/dev/null || true
# The app used to be called Jarvis; remove that copy too.
osascript -e 'quit app "Jarvis"' 2>/dev/null || true
rm -rf /Applications/Emma.app /Applications/Jarvis.app build/Jarvis.app
cp -R "$APP" /Applications/Emma.app
echo "Installed /Applications/Emma.app"
