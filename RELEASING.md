# Releasing Retrolemetry

This checklist produces a downloadable macOS app from the Swift Package. Do not describe a release as notarized until `notarytool`, `stapler`, and Gatekeeper validation all succeed for the exact uploaded artifact.

Publication of v1.0.0 is currently held. Work remains on `agent/release-prep`, draft PR #1. Do not merge, tag, create a release, deploy Pages or install a QA build as a side effect of preparation.

The universal updater-enabled build 21 includes the application license and map-data notices and has passed signing, Apple notarization, stapling and Gatekeeper checks. The application source is unchanged from build 20, which passed unit tests and the native shared-code updater harness. Preserve retained candidate archives and their evidence rather than editing them. Exact production-app VM acceptance and a separately verified updater-key recovery backup remain pending. A host kernel panic interrupted VM preparation before Retrolemetry was installed in the guest; final VM acceptance is deferred until suitable storage is connected. Use a fresh standalone RAW VM on native APFS storage for the next acceptance session, and retain existing VM images and saved states. Do not treat the shared-code harness as final production-app acceptance.

## 1. Prepare the release

- Update `CHANGELOG.md` with the version and date.
- Update the version and increasing numeric build in `Resources/Info.plist` and confirm `RELEASE_NOTES.md`. The next candidate is build 21; never offer a lower build than an existing installed/released build.
- Add privacy-safe screenshots under `assets/screenshots/`.
- Confirm the working tree is clean and GitHub Actions passes.

## 2. Build a universal app

Install the current full Xcode release and select it with `xcode-select`. Then run:

```sh
UNIVERSAL=1 VERSION=1.0.0 BUILD_NUMBER=21 \
  CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  ./scripts/package_app.sh
```

This creates `build/Retrolemetry.app` and `dist/Retrolemetry-1.0.0.zip`. The stable bundle identifier is `io.github.SamSpring.Retrolemetry`. The app bundle contains the location usage description required by Core Location. `SMAppService.mainApp` handles Launch at Login and does not require a separate helper target.

Sparkle 2.10.0 is pinned in `Package.swift` and `Package.resolved`. The packager uses its official SwiftPM binary artifact, embeds the intact framework with symlinks, includes its license alongside the application license and data notices, then signs Downloader.xpc, Installer.xpc, Autoupdate, Updater.app and the framework, in that order, preserving helper entitlements. It signs the outer app last with hardened runtime and a secure timestamp. Public apps must not disable library validation. CI-only ad-hoc packages are not distribution builds.

The outer app is signed with `Resources/Retrolemetry.entitlements`, containing only `com.apple.security.personal-information.location`. Hardened Runtime requires this resource capability in addition to the Info.plist usage descriptions; it allows the normal macOS consent request, not silent authorization. Packaging and CI verify the entitlement in the actual signed app. Retained builds 21 and 22 predate this correction and must not be treated as weather-accepted release candidates. Build 23 includes the telemetry display refinements and this packaging correction; its own final native acceptance remains separate from earlier evidence.

Prefer `SWIFT_SCRATCH_PATH`, `OUTPUT_DIR` and `DIST_DIR` on non-cloud local storage. For example, set `SWIFT_SCRATCH_PATH=/private/tmp/retrolemetry-release-build` when the source is cloud-synced. The packaging script resolves and embeds Sparkle from that same scratch directory. Both QA/feed scripts accept `--sparkle-tools /private/tmp/retrolemetry-release-build/artifacts/sparkle/Sparkle/bin`. Validate a fresh extraction of the final ZIP, not just the staging app; cloud sync can damage unpacked frameworks. Keep the final archive immutable.

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

## 4. Prepare the signed update feed privately

The Retrolemetry-specific signing account is `io.github.SamSpring.Retrolemetry.sparkle`. The private key lives in macOS Keychain. Only `SUPublicEDKey` is committed. Never use Sparkle's default account or a SpaceBar key/feed. Never export a key to a source checkout, cloud folder, environment variable, build archive, chat or log.

The dedicated feed is `https://samspring.github.io/Retrolemetry/appcast.xml`, deployed with the existing `site/` GitHub Pages workflow. The committed feed is signed and empty while publication is held. `SURequireSignedFeed` and `SUVerifyUpdateBeforeExtraction` are enabled. A zero feed-failure expiration prevents falling back to an unverified feed even after prolonged failure. Changing any feed bytes requires re-signing.

After notarizing/stapling the exact final ZIP, prepare a NEW private folder outside the checkout:

```sh
python3 scripts/prepare_appcast.py /private/release/Retrolemetry-1.0.0.zip /private/release/feed-1.0.0
```

Use your own existing local paths. This script does not upload anything. It verifies the archived identity, universal architectures, macOS minimum, Developer ID/hardened-runtime signature, stapled ticket, Gatekeeper acceptance and matching Keychain public key. It generates and verifies both feed and archive signatures, validates the exact enclosure URL/length/build and writes a checksum/validation receipt. macOS may request local Keychain authorization for the official Sparkle signing tools.

For later versions, pass `--previous /private/release/previous-feed`. Keep old entries and immutable download URLs; use a strictly greater build number and a new version/archive name. Delta updates are disabled for the initial workflow. Never edit a generated feed without re-signing it.

Back up the Retrolemetry key separately using Publisher's protected recovery workflow: export directly into a mounted password-encrypted image outside the repository/cloud staging, reopen it, reproduce an archive signature, and lock/eject it. Do not modify or reuse SpaceBar's updater-key backup. The shared Developer ID certificate may be used; the updater key may not. Keychain storage alone is not proof of an independently verified recovery backup.

## 5. Updater acceptance

```sh
swift test -c release --jobs 2
python3 scripts/test_updater.py --output /private/tmp/retrolemetry-unique-updater-qa
```

The native harness shares `AppUpdater.swift`, uses a unique QA bundle ID, synthetic settings, temporary non-Keychain signing keys and a loopback-only allowlisted server. It invokes the real Check for Updates menu action, clicks Sparkle's normal Install Update / Install and Relaunch controls, verifies the new launch, and checks that tampered archives, wrong-key archives and wrong-key feeds leave the older signed app and layout/settings intact. It never launches the production console, accesses Finnhub/location or registers login items. Keep failed runs and logs; a timeout is incomplete, not a pass. Temporary test keys are deleted on exit.

That harness is a real native updater test, but is not final acceptance of the exact notarized production app. Before publishing, repeat in an isolated clean Mac account/VM with the stable production bundle ID: a signed/notarized QA-only older build → the exact final candidate; equal/no-update; tampered/wrong-key rejection; relaunch; layout/typography/display preferences; synthetic Keychain data; and Launch at Login continuity. Use Sparkle's documented **guest-only** `SUFeedURL` override for an allowlisted private test feed. Never point the host's installed app at QA feeds or upload QA-only builds. Do not alter quarantine or bypass Gatekeeper. This does not authorize restarting SpaceBar's suspended VM; coordinate a separately approved guest session with Publisher.

## 6. Publish — only after Samuel authorizes it

- Tag the release as `v1.0.0` only after validation.
- Create the GitHub Release from `RELEASE_NOTES.md`.
- Attach the final stapled `dist/Retrolemetry-1.0.0.zip` and checksums.
- Download the public ZIP normally, verify its checksum, signature and Gatekeeper state, and confirm it is byte-identical to the appcast enclosure archive.
- Copy ONLY the reviewed signed `appcast.xml` into `site/`. Update `site/release.json` with the new final checksum and verified state, replacing stale pre-updater metadata.
- Run `swift scripts/verify_appcast.swift Resources/Info.plist site/appcast.xml` and `python3 scripts/validate_site.py --release`.
- Deploy the existing manual Pages workflow from approved `main` only after the public Release download exists. Do not upload private feed staging, QA fixtures, validation logs, certificates or keys.
- Fetch the HTTPS feed back after deployment and verify its signature and exact public archive. Private loopback QA does not prove the public endpoint is live.
- Remove the pre-publication warning from public release notes only after final acceptance and notarization are confirmed.
- Move the changelog's unreleased changes under `1.0.0` with the actual publication date.

The site defaults to a source link and a preparation notice. Its Download button and signature/checksum wording activate only when `site/release.json` contains the verified public release metadata. Keep those flags false until the public ZIP is fetched and checked. The manual Pages workflow deploys only from `main`.
