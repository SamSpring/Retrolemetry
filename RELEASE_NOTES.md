# Retrolemetry v1.0.0

Retrolemetry is a native macOS system console built for compact 960×540 secondary displays. It combines live system telemetry, vector-style animation, local weather, and precise display controls in a lightweight menu-bar app.

## Highlights

- Four animated views for telemetry, radar/weather, signal analysis, and oversized live metrics
- Automatic external-display selection with a remembered preferred display
- Green-phosphor and synthwave themes with configurable CRT-style effects
- A visual layout editor with module positioning, sizing, visibility, and typography controls
- Physical-display calibration for globe and radar proportions
- Optional Launch at Login and BetterTouchTool-compatible show/hide automation

## Install

Download `Retrolemetry-1.0.0.zip`, move `Retrolemetry.app` to `/Applications`, and open it. Retrolemetry requires macOS 14 or later. Grant location permission only if you want local weather.

## Privacy

System telemetry stays on the Mac. If weather is enabled, an approximate coordinate is sent directly to Open-Meteo over HTTPS. Retrolemetry has no account, analytics, advertising, bundled tracking SDK, or weather API key.

## Known limitations

- The interface is fixed at 960×540 and may not fit smaller displays.
- GPU utilization and temperature are unavailable because stable public macOS APIs are not provided for them.
- Launch at Login requires the bundled app to be installed in a stable location such as `/Applications`.

## Artifact status before publication

The current repository packaging path creates a valid app bundle with an ad-hoc signature by default. **v1.0.0 has not yet been Developer ID signed or notarized.** Replace this status only after Apple's notarization service succeeds and the ticket is stapled and validated.
