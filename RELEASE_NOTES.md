# Retrolemetry v1.0.0

Retrolemetry is a native macOS system console built for compact 960×540 secondary displays. It combines live system telemetry, vector-style animation, local weather, and precise display controls in a lightweight menu-bar app.

## Highlights

- Four animated views for telemetry, radar/weather, signal analysis, and oversized live metrics
- Automatic external-display selection with a remembered preferred display
- Green-phosphor and synthwave themes with configurable CRT-style effects
- Menu-bar synthwave switching, dual adjustable VHS tracking lines, and three scene transition styles
- A visual layout editor with module positioning, sizing, visibility, and typography controls
- Optional layout snapping and a no-scroll editing tray for typography, modules, and precise frame controls
- Separate typography scaling for primary values, secondary labels, and remaining chrome/status text
- A live Finnhub market panel with editable watch symbols and secure Keychain credential storage
- A dedicated market-watch scene with a rotating globe, separate clocks, two five-symbol ticker boards, a focus chart, and USD→ILS daily reference history
- Configurable Florida, Los Angeles, and London world clocks with automatic daylight-saving handling
- A richer weather view with upcoming hourly conditions, a configurable 3–7-day outlook, and weather-driven radar targets
- Configurable slideshow ordering and intervals, plus a responsive synthwave perspective grid with three animation patterns and selectable telemetry input
- Proportional output sizing for compact displays, Macs, iPad/Sidecar, phone-landscape adapters, and custom dimensions
- Physical-display calibration for globe and radar proportions
- Optional Launch at Login and BetterTouchTool-compatible show/hide automation

## Install

Download `Retrolemetry-1.0.0.zip`, move `Retrolemetry.app` to `/Applications`, and open it. Retrolemetry requires macOS 14 or later. Grant location permission only if you want local weather.

## Privacy

System telemetry stays on the Mac. If weather is enabled, an approximate coordinate is sent directly to Open-Meteo over HTTPS. Retrolemetry has no account, analytics, advertising, bundled tracking SDK, or weather API key.

If live market data is configured, ticker symbols are sent directly to Finnhub and the user's personal API key remains in macOS Keychain. The USD→ILS panel requests public daily reference-rate history from Frankfurter. No market-data credential is bundled with the app or repository.

## Known limitations

- The interface is composed at 960×540 and scales proportionally; narrow or portrait displays may show letterboxing.
- GPU utilization and temperature are unavailable because stable public macOS APIs are not provided for them.
- Launch at Login requires the bundled app to be installed in a stable location such as `/Applications`.

## Artifact status before publication

The current repository packaging path creates a valid app bundle with an ad-hoc signature by default. **v1.0.0 has not yet been Developer ID signed or notarized.** Replace this status only after Apple's notarization service succeeds and the ticket is stapled and validated.
