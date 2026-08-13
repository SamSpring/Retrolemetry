# Releasing Retrolemetry

This checklist produces a downloadable macOS app from the Swift Package. Do not describe a release as notarized until `notarytool`, `stapler`, and Gatekeeper validation all succeed for the exact uploaded artifact.

## 1. Prepare the release

- Update `CHANGELOG.md` with the version and date.
- Update the version in `Resources/Info.plist` and confirm `RELEASE_NOTES.md`.
- Add privacy-safe screenshots under `assets/screenshots/`.
- Confirm the working tree is clean and GitHub Actions passes.

## 2. Build a universal app

Install the current full Xcode release and select it with `xcode-select`. Then run:

```sh
UNIVERSAL=1 VERSION=1.0.0 BUILD_NUMBER=1 \
  CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  ./scripts/package_app.sh
```

This creates `build/Retrolemetry.app` and `dist/Retrolemetry-1.0.0.zip`. The stable bundle identifier is `io.github.SamSpring.Retrolemetry`. The app bundle contains the location usage description required by Core Location. `SMAppService.mainApp` handles Launch at Login and does not require a separate helper target.

Verify the architecture and signature:

```sh
lipo -archs build/Retrolemetry.app/Contents/MacOS/Retrolemetry
codesign --verify --deep --strict --verbose=2 build/Retrolemetry.app
codesign -dvvv build/Retrolemetry.app
```

## 3. Notarize and staple

Create a notarytool keychain profile once using an Apple ID app-specific password or App Store Connect API key. Do not commit credentials.

```sh
NOTARY_PROFILE="retrolemetry-notary" VERSION=1.0.0 \
  ./scripts/notarize_app.sh build/Retrolemetry.app
```

The script submits a temporary zip, waits for Apple's result, staples the ticket to the app, validates it, and recreates `dist/Retrolemetry-1.0.0.zip` from the stapled app.

Run final Gatekeeper checks on the exact app and archive contents:

```sh
spctl --assess --type execute --verbose=4 build/Retrolemetry.app
xcrun stapler validate build/Retrolemetry.app
```

Test first launch, location permission, preferred-display reconnection, Launch at Login, menu controls, and `killall -USR1 Retrolemetry` on a clean macOS user account.

## 4. Publish

- Tag the release as `v1.0.0` only after validation.
- Create the GitHub Release from `RELEASE_NOTES.md`.
- Attach the final stapled `dist/Retrolemetry-1.0.0.zip` and checksums.
- Remove the pre-publication artifact warning from the public release notes only after notarization is confirmed.
