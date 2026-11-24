#!/bin/sh
set -eu

root=$(CDPATH= cd "$(dirname "$0")" && pwd)
mkdir -p "$root/build"
stage=$(mktemp -d "$root/build/.package.XXXXXX")
trap 'rm -rf "$stage"' EXIT
trap 'exit 1' HUP INT TERM

app="$stage/image/常亮.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"

xcrun --sdk macosx swift -module-cache-path "$stage/cache/icon" \
    "$root/Resources/Cup.swift" "$stage/Cup.iconset"
iconutil -c icns "$stage/Cup.iconset" -o "$app/Contents/Resources/Cup.icns"

for arch in arm64 x86_64; do
    xcrun --sdk macosx swiftc -O -target "$arch-apple-macos13.0" \
        -module-cache-path "$stage/cache/$arch" "$root/KeepAwake.swift" \
        -o "$stage/KeepAwake-$arch"
done
xcrun lipo -create "$stage/KeepAwake-arm64" "$stage/KeepAwake-x86_64" \
    -output "$app/Contents/MacOS/KeepAwake"
codesign --force --sign - "$app"
codesign --verify --strict --all-architectures "$app"

ln -s /Applications "$stage/image/Applications"
hdiutil create -srcfolder "$stage/image" -volname "常亮" -fs HFS+ \
    -format UDZO "$stage/Changliang.dmg"
hdiutil verify -quiet "$stage/Changliang.dmg"
mv -f "$stage/Changliang.dmg" "$root/build/Changliang.dmg"
printf '已生成 %s\n' "$root/build/Changliang.dmg"
