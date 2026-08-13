#!/bin/sh
set -eu

APP_BUNDLE="${1:-build/Retrolemetry.app}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
DIST_DIR="${DIST_DIR:-dist}"
VERSION="${VERSION:-1.0.0}"

if [ -z "$NOTARY_PROFILE" ]; then
    echo "Set NOTARY_PROFILE to a notarytool keychain profile." >&2
    exit 1
fi

if [ ! -d "$APP_BUNDLE" ]; then
    echo "App bundle not found: $APP_BUNDLE" >&2
    exit 1
fi

mkdir -p "$DIST_DIR"
case "$DIST_DIR" in
    /*) DIST_PATH="$DIST_DIR" ;;
    *) DIST_PATH="$PWD/$DIST_DIR" ;;
esac
SUBMISSION="$DIST_PATH/Retrolemetry-$VERSION-notarization.zip"
FINAL_ARCHIVE="$DIST_PATH/Retrolemetry-$VERSION.zip"
APP_PARENT=$(cd "$(dirname "$APP_BUNDLE")" && pwd)
APP_BASENAME=$(basename "$APP_BUNDLE")

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
rm -f "$SUBMISSION"
(cd "$APP_PARENT" && COPYFILE_DISABLE=1 /usr/bin/zip -qry "$SUBMISSION" "$APP_BASENAME")
xcrun notarytool submit "$SUBMISSION" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"
rm -f "$FINAL_ARCHIVE"
(cd "$APP_PARENT" && COPYFILE_DISABLE=1 /usr/bin/zip -qry "$FINAL_ARCHIVE" "$APP_BASENAME")

echo "Created notarized archive $FINAL_ARCHIVE"
