#!/bin/bash
# Đóng gói SiriRemoteMac thành SiriRemoteMac.app (kiến trúc máy này, thêm bản còn lại nếu build được) và SiriRemoteMac.dmg
# Chạy trên Mac:  chmod +x build_app.sh && ./build_app.sh
set -euo pipefail
cd "$(dirname "$0")"

APP="SiriRemoteMac.app"
rm -rf "$APP" build SiriRemoteMac.dmg
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build

HOST="$(uname -m)"                      # arm64 hoặc x86_64
OTHER="x86_64"; [ "$HOST" = "x86_64" ] && OTHER="arm64"

echo "→ Biên dịch cho $HOST"
swiftc -Osize -whole-module-optimization -target "$HOST-apple-macos13" Sources/*.swift -o "build/SiriRemoteMac-$HOST"

echo "→ Thử biên dịch thêm cho $OTHER (bỏ qua nếu thiếu thư viện)"
if swiftc -Osize -whole-module-optimization -target "$OTHER-apple-macos13" Sources/*.swift -o "build/SiriRemoteMac-$OTHER" >/dev/null 2>&1; then
    lipo -create "build/SiriRemoteMac-$HOST" "build/SiriRemoteMac-$OTHER" -output "$APP/Contents/MacOS/SiriRemoteMac"
    echo "   → bản universal"
else
    cp "build/SiriRemoteMac-$HOST" "$APP/Contents/MacOS/SiriRemoteMac"
    echo "   → chỉ có bản $HOST (đủ để chạy trên máy này)"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>SiriRemoteMac</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>local.siriremotemac</string>
    <key>CFBundleName</key><string>SiriRemoteMac</string>
    <key>CFBundleDisplayName</key><string>SiriRemoteMac</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Biểu tượng app: icon/AppIcon.png (1024x1024) → AppIcon.icns
if [ -f icon/AppIcon.png ]; then
    echo "→ Tạo biểu tượng"
    ICONSET="build/AppIcon.iconset"; mkdir -p "$ICONSET"
    for sz in 16 32 128 256 512; do
        sips -z $sz $sz icon/AppIcon.png --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null
        sips -z $((sz*2)) $((sz*2)) icon/AppIcon.png --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

# Xóa thuộc tính mở rộng (quarantine, Finder info, iCloud...) mà codesign không chấp nhận
xattr -cr "$APP" 2>/dev/null || true
find "$APP" -name '._*' -delete 2>/dev/null || true

IDENTITY="${SIGN_IDENTITY:-SiriRemoteMac Local}"
if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "→ Ký bằng chứng chỉ \"$IDENTITY\" (quyền Accessibility được giữ qua các lần build)"
    codesign --force --deep --sign "$IDENTITY" "$APP"
else
    echo "⚠ Chưa có chứng chỉ \"$IDENTITY\": ký ad-hoc, macOS sẽ hỏi lại quyền sau MỖI lần build."
    echo "  Tạo một lần: Keychain Access → Certificate Assistant → Create a Certificate"
    echo "  (Name: $IDENTITY, Self Signed Root, Code Signing)"
    codesign --force --deep --sign - "$APP"
fi

echo "→ Tạo file .dmg"
mkdir -p build/dmg
cp -R "$APP" build/dmg/
ln -s /Applications build/dmg/Applications
hdiutil create -volname "SiriRemoteMac" -srcfolder build/dmg -ov -format UDZO SiriRemoteMac.dmg >/dev/null

rm -rf build
echo "Xong: $APP và SiriRemoteMac.dmg"
