#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release --product TimeSteward
APP="dist/时间安排管家.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/TimeSteward "$APP/Contents/MacOS/TimeSteward"
mkdir -p dist/AppIcon.iconset
swift Scripts/icon.swift dist/icon-1024.png
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" dist/icon-1024.png --out "dist/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  doubled=$((size * 2))
  sips -z "$doubled" "$doubled" dist/icon-1024.png --out "dist/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns dist/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.timesteward.desktop</string>
<key>CFBundleName</key><string>时间安排管家</string>
<key>CFBundleDisplayName</key><string>时间安排管家</string>
<key>CFBundleExecutable</key><string>TimeSteward</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
mkdir -p dist/Installer
ditto "$APP" "dist/Installer/时间安排管家.app"
if [ ! -L dist/Installer/Applications ]; then ln -s /Applications dist/Installer/Applications; fi
hdiutil create -volname "时间安排管家" -srcfolder dist/Installer -ov -format UDZO "dist/时间安排管家.dmg"
mkdir -p dist/PackageRoot
ditto "$APP" "dist/PackageRoot/时间安排管家.app"
pkgbuild --root dist/PackageRoot --identifier local.timesteward.desktop --version 0.1.0 --install-location /Applications "dist/时间安排管家.pkg"
echo "已生成本机测试应用、DMG 和 PKG：dist/"
