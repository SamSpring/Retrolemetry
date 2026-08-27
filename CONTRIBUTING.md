# Contributing

Thanks for helping improve Retrolemetry. Focused fixes and documentation improvements are welcome.

## Before opening a pull request

1. Open an issue first for behavior changes or large features.
2. Keep the native SwiftUI/AppKit design and macOS 14 minimum unless a change is discussed.
3. Preserve the fixed 960×540 console and preferred-display fallback behavior.
4. Do not add analytics, credentials, private APIs, or third-party dependencies without prior discussion.
5. Build with `swift build -c release` and test the affected view on a secondary display when possible.

Use a clear commit message and explain user-visible effects, validation, and any signing or hardware limits in the pull request.

By contributing, you agree that your contribution is licensed under the project's MIT License.
