#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$(dirname "$PROJECT_DIR")"
APP_DIR="$OUTPUT_DIR/Task Manager.app"
cd "$PROJECT_DIR"
swift build -c release --arch arm64
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
python3 Scripts/MakeIcon.py "$APP_DIR/Contents/Resources/AppIcon.icns"
python3 Scripts/VerifyIcon.py "$APP_DIR/Contents/Resources/AppIcon.icns"
cp -R Assets/Fonts "$APP_DIR/Contents/Resources/"
cp .build/release/TaskManager "$APP_DIR/Contents/MacOS/TaskManager"
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleExecutable</key><string>TaskManager</string>
<key>CFBundleIdentifier</key><string>local.codex.TaskManager</string>
<key>CFBundleName</key><string>Task Manager</string>
<key>CFBundleDisplayName</key><string>Task Manager</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.1</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP_DIR"
printf '%s\n' "$APP_DIR"
