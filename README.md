# Retrolemetry

Retrolemetry turns a small secondary Mac display into a native, animated system console. It is designed around a 960×540 dock screen, stays out of the Dock, and uses SwiftUI and AppKit—no Electron or web view.

> Screenshots are coming with the first release. Image sources belong in [`assets/screenshots`](assets/screenshots/).

## Features

### Live console

- CPU, memory, disk, network, load average, and uptime telemetry
- Four views: System Telemetry, Sector Scan, Signal Analysis, and Live System Metrics
- Animated segmented meters, history traces, radar, vector terrain, Lissajous scope, and wireframe globe
- Green-phosphor and synthwave themes, plus adjustable bloom, scan bands, noise, vignette, and VHS tracking
- Local weather conditions and 12-hour temperature and precipitation graphs

### Dedicated-display behavior

- Exact 960×540 borderless window
- Automatically chooses the smallest external display, or remembers a display selected in Settings
- Returns to that display after reconnection
- Waits hidden when an explicitly selected display is disconnected instead of falling back to the main Mac display
- Can cover the menu bar on the dock display without changing the main display

### Customization and control

- Optional automatic scene cycling and horizontal mouse-wheel navigation
- Keys `1`–`4` select a scene; `0` or `A` resumes automatic cycling
- Visual layout editor with drag, resize, visibility, typography, and per-view reset controls
- Globe and radar aspect-ratio calibration for unusual physical screens
- Settings export, menu-bar controls, Launch at Login, and a `SIGUSR1` automation toggle

GPU utilization and temperatures are intentionally omitted because macOS does not provide stable public APIs suitable for this lightweight implementation.

## Requirements

- macOS 14 Sonoma or later
- A 960×540 secondary display for the intended layout (the app can run on other displays, but the console remains 960×540)
- Apple silicon or Intel, depending on the architecture included in the downloaded release

## Install from GitHub Releases

1. Download the latest `Retrolemetry-*.zip` from [GitHub Releases](https://github.com/SamSpring/Retrolemetry/releases).
2. Unzip it and move `Retrolemetry.app` to `/Applications`.
3. Open Retrolemetry. Grant location access only if you want local weather.
4. Use the waveform icon in the menu bar to choose the dock display and adjust Settings.

The release page should state whether a build is signed and notarized. A locally built or unsigned archive may trigger additional macOS security prompts; the repository does not claim notarization until a release has actually completed Apple's notarization service.

## Build from source

Open `Package.swift` in Xcode and run the `Retrolemetry` executable, or use Terminal:

```sh
swift run Retrolemetry
```

To produce a standard app bundle and zip in `build/` and `dist/`:

```sh
./scripts/package_app.sh
```

Use Xcode or Command Line Tools whose Swift compiler and macOS SDK versions match. The packaging script applies an ad-hoc signature unless `CODESIGN_IDENTITY` is set to a Developer ID Application identity.

## Controls and automation

- `1`–`4`: select a scene
- `0` or `A`: resume automatic cycling
- Horizontal mouse wheel: move between scenes
- Menu-bar waveform: show/hide, move display, open Settings, or quit
- `⌘⇧D`: show or hide while the menu is active

For BetterTouchTool, add a **Run Shell Script / Task** action:

```sh
killall -USR1 Retrolemetry
```

The signal hides the console to reveal the content underneath, or restores it to the preferred display. The process remains running, so the response is immediate.

## Display setup and Launch at Login

Retrolemetry starts as a menu-bar accessory app and centers its fixed-size window on the selected display. If no display is selected, it chooses the smallest connected external display. You can turn off menu-bar covering or change the target in Settings.

**Launch Retrolemetry at login** uses Apple's `SMAppService.mainApp`. It is intended for an installed `.app` bundle in `/Applications`; it is not available when running the raw Swift Package executable from Terminal.

## Privacy and weather

Retrolemetry has no accounts, analytics, advertising, or bundled tracking SDKs. System telemetry is read and displayed locally.

Weather is optional. When location access is allowed, Core Location provides an approximate coordinate and Retrolemetry sends that coordinate to the [Open-Meteo](https://open-meteo.com/) forecast API over HTTPS. The app does not include an API key and does not store a location history. Denying location access leaves the weather panel unavailable without affecting system telemetry.

## Support

If Retrolemetry is useful to you, you can support future development here: **[Ko-fi link coming soon]**.

Bug reports and focused feature requests are welcome in [GitHub Issues](https://github.com/SamSpring/Retrolemetry/issues).

## Development

Small, behavior-preserving fixes are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md). Maintainers can find signing, notarization, and release packaging steps in [RELEASING.md](RELEASING.md).

Retrolemetry is available under the [MIT License](LICENSE).
