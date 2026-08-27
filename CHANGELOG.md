# Changelog

All notable changes to Retrolemetry will be documented here. This project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

- Added click-to-cycle Today, Week, Month, and Year ranges to the Market Watch focus chart
- Stabilized horizontal scene scrolling so each direct gesture moves once and momentum cannot reverse it
- Added click-to-cycle target modes directly on the live weather radar
- Kept full-system graph traces below their title and value headers at every typography scale
- Enlarged daily weather low and high temperatures and reserved enough width to prevent truncation
- Restored the green phosphor background tint control without making scene transitions transparent

## [1.0.0] - 2026-08-14

### Added

- First public macOS release preparation
- Four animated telemetry and vector scenes
- Dedicated 960×540 display selection and reconnection behavior
- Layout, typography, theme, and physical-display calibration controls
- Optional Core Location and Open-Meteo weather panel
- Menu-bar controls, Launch at Login, settings export, and `SIGUSR1` automation
- A menu-bar synthwave toggle and independent thickness controls for two moving VHS tracking lines
- Dynamic Show/Hide menu text, keyboard equivalents, and separate BetterTouchTool signals for visibility and theme
- Pan, diagonal wipe, and CRT sync-roll scene transitions
- A third typography control for chrome, status, and remaining interface text
- A live Finnhub market panel with editable symbols and a Keychain-protected personal API key
- A dedicated market-watch layout with no system meters competing for space
- Three configurable world clocks on the market panel, defaulting to Florida, Los Angeles, and London
- A restored rotating market globe, separate clock module, two five-symbol ticker boards, and a compact USD→ILS daily reference graph
- Configurable slideshow ordering, 15/30/60/180-second presets, and a custom interval field
- Optional CPU-driven synthwave perspective grid for Signal Analysis
- Match-display, common Mac/iPad/phone-landscape, and custom output sizing with proportional 960×540 rendering
- A combined 12-hour weather forecast and configurable 3–7-day daily outlook
- Reproducible `.app` bundle packaging, Developer ID signing hooks, and notarization workflow
- Optional 5/10/20-pixel snapping for moving and resizing modules in the layout editor
- Signal-grid animation controls for motion, telemetry source, pattern, and response speed
- Weather-driven radar targets for precipitation, temperature, and wind, plus optional target pulsing

### Changed

- Public package, product, target, executable, and process name standardized as Retrolemetry
- Existing `DockTelemetry.*` preference keys retained to preserve settings for early builds
- Scene changes now keep both views on screen for a continuous edge-to-edge pan
- The System Telemetry globe area now presents live quotes, daily changes, ranges, and accumulating price traces
- Signal Analysis now uses a slower, stable perspective grid that travels toward the horizon
- Wipe transitions are fully opaque, and Sync Roll now collapses and restores the CRT image at the center line
- Settings navigation and the layout editor inspector were reorganized for clearer editing at practical window sizes
- All three typography controls now support scaling up to 200%
- Settings now use one AppKit-owned window, preventing duplicate windows after backup export and eliminating unused top space
- Signal grids now span beyond the viewport, show the selected live input in the header, and use stronger data-driven terrain motion with a synthwave-pink horizon
- The layout editor now uses its lower workspace for typography, modules, and selected-module controls instead of a narrow scrolling sidebar

[Unreleased]: https://github.com/SamSpring/Retrolemetry/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/SamSpring/Retrolemetry/releases/tag/v1.0.0
