#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
swift build --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security -c release
BIN_DIR=$(swift build --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security -c release --show-bin-path)
APP="$PWD/dist/LightSnap.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/LightSnap" "$APP/Contents/MacOS/LightSnap"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LightSnap</string>
<key>CFBundleIdentifier</key><string>dev.lightsnap.mac</string>
<key>CFBundleName</key><string>LightSnap</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleVersion</key><string>4</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Pass a real signing identity when available to keep a certificate-based app identity.
# Local ad-hoc builds require Accessibility re-authorization after binary changes.
if [[ -n "${LIGHTSNAP_SIGN_IDENTITY:-}" ]]; then
  codesign --force --sign "$LIGHTSNAP_SIGN_IDENTITY" --options runtime --timestamp --identifier dev.lightsnap.mac "$APP"
else
  codesign --force --sign - --identifier dev.lightsnap.mac "$APP"
fi
echo "Built: $APP"
