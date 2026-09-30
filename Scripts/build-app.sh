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

# LSUIElement true is the load-bearing key: it keeps the app out of the Dock
# and gives it no app menu, which is what a menu bar widget wants.
# LSMinimumSystemVersion must be kept in step with platforms in Package.swift.
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
