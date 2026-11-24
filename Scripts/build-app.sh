#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
CONFIGURATION="${1:-debug}"
ICON_SOURCE="$ROOT_DIR/Sources/TeachLensCore/Resources/TeachLensAppIcon.png"

DIST_DISTRIBUTION="${TEACHLENS_DISTRIBUTION:-homebrew}"
case "$DIST_DISTRIBUTION" in
    homebrew)
        ENTITLEMENTS="$ROOT_DIR/Scripts/TeachLens.entitlements"
        distribution_swift_flags=()
        ;;
    appstore)
        ENTITLEMENTS="$ROOT_DIR/Scripts/TeachLens-AppStore.entitlements"
        distribution_swift_flags=(-Xswiftc -DTEACHLENS_APP_STORE)
        ;;
    *)
        echo "error: TEACHLENS_DISTRIBUTION must be 'homebrew' or 'appstore' (got '$DIST_DISTRIBUTION')." >&2
        exit 2
        ;;
esac

# Local builds default to 1.0 when TEACHLENS_VERSION is absent. An explicitly
# empty value still fails, which prevents a queued official build from silently
# using the development default. Restrict the value to dotted numeric
# components, optionally followed by a pre-release tag (1.3.0-beta.1), so it
# cannot inject content into the generated plist.
DISPLAY_VERSION="${TEACHLENS_VERSION-1.0}"
VERSION_PATTERN='^[0-9]+\.[0-9]+(\.[0-9]+)?(-(alpha|beta|rc)\.[0-9]+)?$'
if [[ ! "$DISPLAY_VERSION" =~ $VERSION_PATTERN ]]; then
    echo "error: TEACHLENS_VERSION must look like 1.0, 1.0.0 or 1.0.0-beta.1 (got '$DISPLAY_VERSION')." >&2
    exit 2
fi
# macOS bundle versions must be numeric: 1.3.0-beta.1 is stored as version
# and build 1.3.0, and the full label goes in TeachLensDisplayVersion, which
# the app shows in Settings and diagnostics.
VERSION="${DISPLAY_VERSION%%-*}"
BUILD_NUMBER="${TEACHLENS_BUILD_NUMBER:-$VERSION}"
BUILD_NUMBER_PATTERN='^[0-9]+(\.[0-9]+){0,2}$'
if [[ ! "$BUILD_NUMBER" =~ $BUILD_NUMBER_PATTERN ]]; then
    echo "error: TEACHLENS_BUILD_NUMBER must contain one to three numeric components (got '$BUILD_NUMBER')." >&2
    exit 2
fi
case "${TEACHLENS_REQUIRE_RELEASE_VERSION:-false}" in
    true|True|TRUE|1)
        if [[ "$VERSION" == "0.0.0" ]]; then
            echo "error: replace the 0.0.0 PR placeholder with the intended release version." >&2
            exit 2
        fi
        ;;
esac

# Signing identity controls which "flavor" of the app is produced.
#   - Ad-hoc (the default, "-"): a contributor build that cannot reproduce the
#     official Developer ID signature. It uses a distinct .dev bundle id so its
#     Screen Recording (and other TCC) grant is a separate entry that never
#     collides with the officially distributed io.github.fw1201.teachlens app.
#   - A real identity (e.g. "Developer ID Application: Your Name (TEAMID)"): the
#     official build, which keeps the canonical bundle id so its TCC grant is
#     stable across updates.
# Override any of these via the environment:
#   TEACHLENS_SIGN_IDENTITY, TEACHLENS_BUNDLE_ID, TEACHLENS_DISPLAY_NAME
SIGN_IDENTITY="${TEACHLENS_SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    BUNDLE_ID="${TEACHLENS_BUNDLE_ID:-io.github.fw1201.teachlens.dev}"
    DISPLAY_NAME="${TEACHLENS_DISPLAY_NAME:-TeachLens (Dev)}"
    SIGN_DESC="ad-hoc"
else
    BUNDLE_ID="${TEACHLENS_BUNDLE_ID:-io.github.fw1201.teachlens}"
    DISPLAY_NAME="${TEACHLENS_DISPLAY_NAME:-TeachLens}"
    SIGN_DESC="$SIGN_IDENTITY"
fi

# Name the .app bundle after the display name so a contributor's
# "TeachLens (Dev).app" never collides with the official "TeachLens.app" on disk.
# Two identically named bundles get conflated by LaunchServices and appear as a
# single row in System Settings > Screen Recording, making it impossible to
# grant the dev build its own permission.
APP_NAME="${TEACHLENS_APP_NAME:-${DISPLAY_NAME}.app}"
APP_PATH="$ROOT_DIR/.build/$APP_NAME"

cd "$ROOT_DIR"

# Architectures. Release builds ship a Universal binary (Apple Silicon + Intel)
# so the download runs natively on both; debug builds stay native for speed.
# Override with TEACHLENS_ARCHS (space-separated, e.g. "arm64"); set it to empty to
# use the toolchain default. A modern macOS agent cross-compiles the x86_64 slice
# from Apple Silicon, so no second build machine is needed.
if [[ -n "${TEACHLENS_ARCHS+set}" ]]; then
    archs=(${=TEACHLENS_ARCHS})
elif [[ "$CONFIGURATION" == "release" ]]; then
    archs=(arm64 x86_64)
else
    archs=()
fi
arch_flags=()
for a in $archs; do arch_flags+=(--arch $a); done

# SwiftPM's multi-arch (Universal) build routes through Xcode's xcbuild, which is
# only present with a full Xcode install — not the standalone Command Line Tools.
# CI agents have full Xcode; a contributor on CLT-only would otherwise hard-fail,
# so fall back to a native build with a warning.
if (( ${#arch_flags} > 0 )) && ! xcodebuild -version >/dev/null 2>&1; then
    echo "warning: Universal build needs full Xcode (xcodebuild); building native only." >&2
    archs=()
    arch_flags=()
fi

swift build -c "$CONFIGURATION" $arch_flags $distribution_swift_flags
BIN_DIR="$(swift build -c "$CONFIGURATION" $arch_flags $distribution_swift_flags --show-bin-path)"

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

cp "$BIN_DIR/TeachLens" "$APP_PATH/Contents/MacOS/TeachLens"
# Copy the SwiftPM-generated resources directly into Contents/Resources.
# A code-signed .app may only contain Contents/ at its root, so the nested
# TeachLens_TeachLensCore.bundle cannot live at the app root (codesign fails
# with "unsealed contents present in the bundle root"). Flattening the bundle's
# resources into Contents/Resources lets the app resolve them via Bundle.main
# (see AppIcon.loadImage) while keeping the bundle codesign-valid.
#
# The bundle's internal layout differs by build system: a native `swift build`
# (llbuild) emits a FLAT bundle with resources at its root, while a Universal
# `--arch` build (xcbuild) emits a STRUCTURED bundle with resources under
# Contents/Resources. Copy from whichever layout is present so the icons land
# flat in the app's Contents/Resources in both cases (otherwise Bundle.main
# can't find them, the code falls through to Bundle.module, and it fatal-errors
# on launch).
RESOURCE_BUNDLE="$BIN_DIR/TeachLens_TeachLensCore.bundle"
if [[ -d "$RESOURCE_BUNDLE/Contents/Resources" ]]; then
    cp -R "$RESOURCE_BUNDLE/Contents/Resources/." "$APP_PATH/Contents/Resources/"
else
    cp -R "$RESOURCE_BUNDLE/." "$APP_PATH/Contents/Resources/"
fi

if [[ -f "$ICON_SOURCE" ]] && command -v sips >/dev/null && command -v iconutil >/dev/null; then
    ICONSET="$(mktemp -d)/TeachLens.iconset"
    mkdir -p "$ICONSET"
    sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET/icon_16x16.png" >/dev/null
    sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
    sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_32x32.png" >/dev/null
    sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
    sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET/icon_128x128.png" >/dev/null
    sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
    sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_256x256.png" >/dev/null
    sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
    sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_512x512.png" >/dev/null
    sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
    iconutil -c icns "$ICONSET" -o "$APP_PATH/Contents/Resources/TeachLens.icns"
fi

# The commit shown in Settings ▸ Check & Test, so testers can tell builds apart.
COMMIT="${TEACHLENS_COMMIT:-$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)}"
COMMIT="${COMMIT//[^0-9A-Za-z]/}"

cat > "$APP_PATH/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>$DISPLAY_NAME</string>
    <key>CFBundleExecutable</key>
    <string>TeachLens</string>
    <key>CFBundleIconFile</key>
    <string>TeachLens</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$DISPLAY_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>TeachLensDisplayVersion</key>
    <string>$DISPLAY_VERSION</string>
    <key>TeachLensCommit</key>
    <string>$COMMIT</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSCameraUsageDescription</key>
    <string>TeachLens shows your webcam as a picture-in-picture overlay when you enable it for screen recordings.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>TeachLens uses your microphone for enabled screen recording audio and optional snip dictation.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>TeachLens transcribes speech you record while dragging a snip when snip dictation is enabled.</string>
    <key>TeachLensDistribution</key>
    <string>$DIST_DISTRIBUTION</string>
</dict>
</plist>
PLIST

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    # Ad-hoc sign the completed bundle so macOS privacy services see the real
    # CFBundleIdentifier and sealed bundle layout. The explicit designated
    # requirement keeps local TCC grants stable across rebuilds without using a
    # signing certificate. The .dev bundle id keeps this grant separate from the
    # officially distributed app so the two never fight over one TCC record.
    # Entitlements are embedded even for ad-hoc builds so the ESRP re-sign in
    # the official pipeline preserves them, and so local hardened-runtime tests
    # can still reach the camera and microphone.
    #
    # Restricted entitlements (com.apple.developer.*, e.g. speech-recognition)
    # need a provisioning profile; on an ad-hoc signature macOS refuses to
    # launch the app ("Launchd job spawn failed", POSIX 162). Strip them here.
    # Speech recognition outside the sandbox only needs the Info.plist usage
    # description, so dictation and captions keep working.
    ADHOC_ENTITLEMENTS="$(mktemp -d)/entitlements.plist"
    cp "$ENTITLEMENTS" "$ADHOC_ENTITLEMENTS"
    for key in $(/usr/libexec/PlistBuddy -c "Print" "$ADHOC_ENTITLEMENTS" | sed -n 's/^ *\(com\.apple\.developer\.[^ ]*\) = .*/\1/p'); do
        /usr/libexec/PlistBuddy -c "Delete :$key" "$ADHOC_ENTITLEMENTS"
    done
    codesign --force --deep --sign - \
        --entitlements "$ADHOC_ENTITLEMENTS" \
        --requirements "=designated => identifier \"$BUNDLE_ID\"" \
        "$APP_PATH" >/dev/null
    rm -f "$ADHOC_ENTITLEMENTS"
else
    # Official build: sign with the provided Developer ID identity and enable
    # the hardened runtime so the app can be notarized. codesign derives the
    # designated requirement from the certificate, so the TCC grant stays
    # stable across signed updates. The entitlements grant camera/microphone
    # access under the hardened runtime.
    codesign --force --options runtime --sign "$SIGN_IDENTITY" \
        --entitlements "$ENTITLEMENTS" \
        "$APP_PATH" >/dev/null
fi

echo "$APP_PATH"
echo "  bundle id:    $BUNDLE_ID" >&2
echo "  display name: $DISPLAY_NAME" >&2
echo "  version:      $DISPLAY_VERSION ($VERSION)" >&2
echo "  build:        $BUILD_NUMBER" >&2
echo "  distribution: $DIST_DISTRIBUTION" >&2
echo "  signed with:  $SIGN_DESC" >&2
echo "  architectures: $(lipo -archs "$APP_PATH/Contents/MacOS/TeachLens" 2>/dev/null || echo unknown)" >&2