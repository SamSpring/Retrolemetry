#!/bin/sh
set -eu

APP_NAME="Retrolemetry"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)}"
CONFIGURATION="${CONFIGURATION:-release}"
OUTPUT_DIR="${OUTPUT_DIR:-build}"
DIST_DIR="${DIST_DIR:-dist}"
INFO_PLIST="Resources/Info.plist"
SWIFT_SCRATCH_PATH="${SWIFT_SCRATCH_PATH:-.build}"

OUTPUT_APP="$OUTPUT_DIR/$APP_NAME.app"
STAGING_DIR=$(mktemp -d "${TMPDIR:-/tmp}/retrolemetry-package.XXXXXX")
trap 'rm -rf "$STAGING_DIR"' EXIT HUP INT TERM
APP_BUNDLE="$STAGING_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"

if [ -n "${PREBUILT_BINARY:-}" ]; then
    BINARY="$PREBUILT_BINARY"
elif [ "${UNIVERSAL:-0}" = "1" ]; then
    swift build --scratch-path "$SWIFT_SCRATCH_PATH" -c "$CONFIGURATION" --arch arm64 --arch x86_64
    BIN_DIR=$(swift build --scratch-path "$SWIFT_SCRATCH_PATH" -c "$CONFIGURATION" --arch arm64 --arch x86_64 --show-bin-path)
    BINARY="$BIN_DIR/$APP_NAME"
else
    swift build --scratch-path "$SWIFT_SCRATCH_PATH" -c "$CONFIGURATION"
    BIN_DIR=$(swift build --scratch-path "$SWIFT_SCRATCH_PATH" -c "$CONFIGURATION" --show-bin-path)
    BINARY="$BIN_DIR/$APP_NAME"
fi

mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$OUTPUT_DIR" "$DIST_DIR"
cp "$BINARY" "$CONTENTS/MacOS/$APP_NAME"
cp "$INFO_PLIST" "$CONTENTS/Info.plist"
cp LICENSE "$CONTENTS/Resources/Retrolemetry-LICENSE.txt"
cp NOTICE.txt "$CONTENTS/Resources/Retrolemetry-NOTICE.txt"

# SwiftPM links Sparkle but does not assemble the .app. Keep helpers, symlinks
# and signatures intact, and re-sign nested code before signing the outer app.
SPARKLE_FRAMEWORK="${SPARKLE_FRAMEWORK:-$SWIFT_SCRATCH_PATH/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework}"
sh scripts/embed_sparkle.sh "$APP_BUNDLE" "$SPARKLE_FRAMEWORK"
cp "${SPARKLE_LICENSE:-$SWIFT_SCRATCH_PATH/artifacts/sparkle/Sparkle/LICENSE}" "$CONTENTS/Resources/Sparkle-LICENSE.txt"

# Generate all standard/Retina sizes from the approved transparent icon master.
swift scripts/render_app_icon.swift Resources/AppIcon.png "$STAGING_DIR/AppIcon.iconset"
iconutil --convert icns --output "$CONTENTS/Resources/AppIcon.icns" "$STAGING_DIR/AppIcon.iconset"

# Native SwiftUI CRT curvature uses a small Metal shader, compiled once at packaging.
if [ -n "${PREBUILT_METALLIB:-}" ]; then
    cp "$PREBUILT_METALLIB" "$CONTENTS/Resources/default.metallib"
else
xcrun -sdk macosx metal -std=metal3.1 -mmacosx-version-min=14.0 -c Resources/CRT.metal -o "$STAGING_DIR/CRT.air"
xcrun -sdk macosx metallib "$STAGING_DIR/CRT.air" -o "$CONTENTS/Resources/default.metallib"
fi
# A source run from this build directory can use the same precompiled GPU library.
if [ -z "${PREBUILT_BINARY:-}" ]; then
    cp "$CONTENTS/Resources/default.metallib" "$BIN_DIR/default.metallib"
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS/Info.plist"
xattr -cr "$APP_BUNDLE"

if [ -n "${CODESIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp --entitlements Resources/Retrolemetry.entitlements --sign "$CODESIGN_IDENTITY" "$APP_BUNDLE"
    echo "Signed with Developer ID identity: $CODESIGN_IDENTITY"
else
    codesign --force --entitlements Resources/Retrolemetry.entitlements --sign - "$APP_BUNDLE"
    echo "Applied an ad-hoc signature. This build is not notarized."
fi

# Hardened apps need this declared resource capability before Core Location can
# display its normal user-consent prompt. It does not grant location permission.
codesign --display --entitlements - --xml "$APP_BUNDLE" > "$STAGING_DIR/signed-entitlements.plist"
test "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.personal-information.location' "$STAGING_DIR/signed-entitlements.plist")" = true

case "$DIST_DIR" in
    /*) ARCHIVE="$DIST_DIR/$APP_NAME-$VERSION.zip" ;;
    *) ARCHIVE="$PWD/$DIST_DIR/$APP_NAME-$VERSION.zip" ;;
esac
rm -f "$ARCHIVE"
(cd "$STAGING_DIR" && COPYFILE_DISABLE=1 /usr/bin/zip -qry "$ARCHIVE" "$APP_NAME.app")
rm -rf "$OUTPUT_APP"
ditto --norsrc "$APP_BUNDLE" "$OUTPUT_APP"
xattr -cr "$OUTPUT_APP"

echo "Created $OUTPUT_APP"
echo "Created $ARCHIVE"
