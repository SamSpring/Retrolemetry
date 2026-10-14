#!/bin/sh
# Copy intact framework symlinks, then sign nested code from the inside out.
set -eu
[ "$#" = 2 ] || { echo 'Usage: embed_sparkle.sh APP FRAMEWORK' >&2; exit 2; }
APP="$1"
SOURCE="$2"
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
[ -d "$SOURCE" ] || { echo 'Sparkle framework is missing. Run swift package resolve.' >&2; exit 1; }
[ ! -e "$FRAMEWORK" ] || { echo 'Refusing to replace an existing framework.' >&2; exit 1; }
mkdir -p "$APP/Contents/Frameworks"
ditto --noextattr --norsrc "$SOURCE" "$FRAMEWORK"
for relative in Versions/B/XPCServices/Downloader.xpc Versions/B/XPCServices/Installer.xpc \
    Versions/B/Autoupdate Versions/B/Updater.app .; do
    target="$FRAMEWORK/$relative"
    [ -e "$target" ] || { echo "Unexpected Sparkle structure: $relative" >&2; exit 1; }
    if [ -n "${CODESIGN_IDENTITY:-}" ]; then
        codesign --force --sign "$CODESIGN_IDENTITY" --options runtime --timestamp --preserve-metadata=entitlements "$target"
    else
        # CI/local builds have no hardened-runtime library-validation requirement.
        codesign --force --sign - --timestamp=none --preserve-metadata=entitlements "$target"
    fi
done
codesign --verify --deep --strict "$FRAMEWORK"
