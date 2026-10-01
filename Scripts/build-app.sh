#!/bin/sh
# Assembles oc-dashbar.app from the SwiftPM binary. This is the whole build
# system: SwiftPM plus this script. No dependencies, no framework embedding.
#
#   Scripts/build-app.sh            # release build
#   Scripts/build-app.sh debug
#   Scripts/build-app.sh release 1.0.0   # release build, version stamped
#
# Produces build/oc-dashbar.app, ad-hoc signed. Per Apple TN2206 an unsigned,
# unquarantined local build runs fine; the signature is there so Keychain and
# TCC behave predictably once the app is stable enough to matter.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
config="${1:-release}"
# Second argument: the version stamped into the bundle. Scripts/release.sh
# passes the tag's version here so the bundle, the zip name, the release
# title and the tag agree. The default is what a development build carries.
version="${2:-0.1.0}"
app="$root/build/oc-dashbar.app"

bin_dir="$(cd "$root" && swift build -c "$config" --show-bin-path)"
# Build for real. `swift build --show-bin-path` only prints the path, so without
# this the script happily packages whatever binary happens to be sitting there.
(cd "$root" && swift build -c "$config")
bin="$bin_dir/oc-dashbar"
if [ ! -x "$bin" ]; then
    echo "build-app.sh: $bin not found after a successful build?" >&2
    exit 1
fi

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/oc-dashbar"
printf 'APPL????' >"$app/Contents/PkgInfo"

# App icon. Rasterised from Assets/AppIcon.svg on every build, into all ten
# iconset entries at their own size, straight from the vector. Nothing is
# downsampled from the 1024, so the 16px entries keep a hard chevron rather
# than the 1024's resampling mush. sips -z renders an SVG at whatever size it
# is handed, so no width or height has to be injected into the source first.
# sips and iconutil both live in /usr/bin, so this adds no dependency.
#
# The copy into Contents/Resources has to happen before codesign runs below.
# A resource added after signing breaks the seal, and the failure is a verify
# error on the next build rather than anything visible here.
icon_src="$root/Assets/AppIcon.svg"
iconset="$root/build/AppIcon.iconset"
rm -rf "$iconset"
mkdir -p "$iconset"
for entry in \
    icon_16x16:16 icon_16x16@2x:32 \
    icon_32x32:32 icon_32x32@2x:64 \
    icon_128x128:128 icon_128x128@2x:256 \
    icon_256x256:256 icon_256x256@2x:512 \
    icon_512x512:512 icon_512x512@2x:1024
do
    sips -s format png -z "${entry##*:}" "${entry##*:}" "$icon_src" \
        --out "$iconset/${entry%:*}.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$root/build/AppIcon.icns"
cp "$root/build/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"

# LSUIElement true is the load-bearing key: it keeps the app out of the Dock
# and gives it no app menu, which is what a menu bar widget wants.
# LSMinimumSystemVersion must be kept in step with platforms in Package.swift.
# CFBundleIconFile points at Contents/Resources/AppIcon.icns, written above.
# CFBundleIconName is deliberately absent. It is the asset-catalog hook, and
# this bundle has no catalog, so macOS resolves it to nothing and serves the
# generic app icon without a warning. Measured, not assumed.
# The heredoc below is unquoted so $version expands; keep other $ and
# backticks out of its body if this template ever changes.
cat >"$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>oc-dashbar</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>dev.joaosantos.oc-dashbar</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>oc-dashbar</string>
    <key>CFBundleDisplayName</key>
    <string>oc-dash</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$version</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$app"
codesign --verify --deep --strict --verbose=2 "$app"

echo "build-app.sh: built $app ($config, version $version)"
