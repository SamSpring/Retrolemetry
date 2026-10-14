# Contributing

Thanks for helping improve Retrolemetry. Focused fixes and documentation improvements are welcome.

## Before opening a pull request

1. Open an issue first for behavior changes or large features.
2. Keep the native SwiftUI/AppKit design and macOS 14 minimum unless a change is discussed.
3. Preserve the 960×540 base composition, proportional output sizing, and preferred-display behavior.
4. Do not add analytics, credentials, private APIs, or third-party dependencies without prior discussion.
5. Run `swift test -c release --jobs 2` and test the affected view on a secondary display when possible. Use a scratch directory outside cloud-synced storage for local builds.

Sparkle is the existing update dependency. Changes to its feed, public key, verification policy, or packaging require release-owner review. Private signing keys and credentials must remain outside the repository. Native updater tests and release artifacts are separate from unit tests; do not describe an update as accepted solely because the unit suite passes.

Use a clear commit message and explain user-visible effects, validation, and any signing or hardware limits in the pull request.

By contributing, you agree that your contribution is licensed under the project's MIT License.
