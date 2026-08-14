#!/bin/sh
set -eu

APP_NAME="Retrolemetry"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
CONFIGURATION="${CONFIGURATION:-release}"
OUTPUT_DIR="${OUTPUT_DIR:-build}"
DIST_DIR="${DIST_DIR:-dist}"
INFO_PLIST="Resources/Info.plist"

OUTPUT_APP="$OUTPUT_DIR/$APP_NAME.app"
STAGING_DIR=$(mktemp -d "${TMPDIR:-/tmp}/retrolemetry-package.XXXXXX")
trap 'rm -rf "$STAGING_DIR"' EXIT HUP INT TERM
APP_BUNDLE="$STAGING_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"

if [ -n "${PREBUILT_BINARY:-}" ]; then
    BINARY="$PREBUILT_BINARY"
elif [ "${UNIVERSAL:-0}" = "1" ]; then
    swift build -c "$CONFIGURATION" --arch arm64 --arch x86_64
    BIN_DIR=$(swift build -c "$CONFIGURATION" --arch arm64 --arch x86_64 --show-bin-path)
    BINARY="$BIN_DIR/$APP_NAME"
else
    swift build -c "$CONFIGURATION"
    BIN_DIR=$(swift build -c "$CONFIGURATION" --show-bin-path)
    BINARY="$BIN_DIR/$APP_NAME"
fi

mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$OUTPUT_DIR" "$DIST_DIR"
cp "$BINARY" "$CONTENTS/MacOS/$APP_NAME"
cp "$INFO_PLIST" "$CONTENTS/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS/Info.plist"
xattr -cr "$APP_BUNDLE"

if [ -n "${CODESIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_BUNDLE"
    echo "Signed with Developer ID identity: $CODESIGN_IDENTITY"
else
    codesign --force --sign - "$APP_BUNDLE"
    echo "Applied an ad-hoc signature. This build is not notarized."
fi

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
