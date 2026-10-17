# Changelog

All notable changes to Retrolemetry will be documented here. This project follows [Semantic Versioning](https://semver.org/).

## Unreleased

The first public release is planned as v1.0.0. Its release date will be recorded when it is published.

- Matched memory/disk used/free amounts to their dim labels and removed the space before GB/TB without changing the central percentages or saved layout
- Centered memory/disk headings and percentages at their original fit, with larger used/free readouts alongside them instead of reducing the main type
- Added bounded local-forecast retries for transient server/connection failures and cancellation of superseded requests, with privacy-safe error diagnostics
- Fixed missing location-access signing capability in hardened app bundles so macOS can request the user's consent for weather; packaging and CI now check the signed entitlement
- Added current CPU/memory percentages to Signal Analysis traces and real used/free amounts to the memory/disk tiles
- Split the metrics network history into TX above/RX below a shared center line, with pink/cyan synthwave traces, a TX current reading and an RX lower readout; saved module IDs and frames stay unchanged
- Bundled the application's MIT license and map-data notices alongside Sparkle's license
- Added Sparkle 2.10.0 update checks, verified download/install/relaunch, a dedicated Retrolemetry signing key and signed HTTPS feed, and an automatic-check setting; existing preferences, layouts, credentials and login identity remain unchanged
- Embedded and signed Sparkle's nested helpers before outer app signing; added private feed preparation, reproducible dependency locking and isolated native updater QA
- Added the approved split phosphor-green/synthwave app icon, transparent native edges and all standard/Retina icon sizes; the menu-bar waveform stays unchanged
- Renamed Headers/main text to Main text and made Dark texts control every dim text element across all scenes, including dim titles, clock labels, and ticker columns; saved settings and module frames remain unchanged
- Added double-click slideshow start/stop without triggering a stock/radar single-click action; manual scrolling remains available while paused
- Split typography into Metrics/Stats, Dark texts, Main text, Frame header, and Frame footer with independent global/per-view controls and backward-compatible saved sizes
- Added automatic weather-region selection using existing location coverage, plus manual Israel/North America/Europe selection in General and Weather layout settings
- Added cached, bounded regional vector maps and region-specific six-location forecast batches; region switches cancel outdated requests and cannot show another region's weather points
- Replaced Settings scene dropdowns with tabs and extended all typography controls to 300%, without changing saved values or module frames
- Fixed the Signal Analysis network I/O border to occupy its saved module frame instead of creating extra inset horizontal edges
- Added a bounded GPU-drawn Israel map, with only Tel Aviv-Yafo outlined inside it, and six geographically positioned forecast samples for rain probability, temperature, and wind speed/direction
- Replaced pseudo-spatial weather contacts with actual regional Open-Meteo forecasts, refreshed in one batch every 15 minutes; missing/stale data stays unavailable and decorative contacts remain labeled as demo
- Added complete globe meridians, continent outlines, an approximate-weather-location pulse, and offline weekday trading-region lights
- Kept native vectors throughout scene switches and synchronized their progress with the text, masks, and transition effects
- Added ticker-row focus selection without changing stock symbols or chart timeframes
- Standardized typography roles and added global/per-view controls without resetting existing font values or layouts
- Removed hidden-module editor outlines and matched curved/effected previews and drag coordinates to the live view
- Expanded only the outer frame's vertical clearance so 200% frame text fits without moving saved modules
- Moved steady-scene globe, radar, signal/grid, and CRT grain/tracking animation to bounded native Metal layers instead of rebuilding SwiftUI paths each frame
- Removed duplicate per-frame signal-grid state updates; retained metric smoothing, animation choices, calibration, and typography
- Removed hidden-console rendering work and limited in-flight GPU frames and effect-buffer resolution
- Replaced the Signal Analysis memory-at-horizon option with real GPU history, retaining existing horizon selections
- Added optional GPU utilization, GPU-history, and battery power/voltage modules to Live System Metrics
- Read GPU counters once per second and battery flow every five seconds through public IOKit functions, with explicit unavailable states and no CPU-load proxy
- Preserved custom module frames while offering an expanded six-tile/four-graph metrics default
- Kept radar and globe shape calibration exclusively on their corresponding layout-editor pages without resetting saved corrections
- Reduced CPU use by limiting animation clocks to moving elements instead of rebuilding complete scenes every frame
- Reused CRT noise textures and batched stationary scanline/grid drawing while preserving the visual controls
- Added a 15/30/60 fps performance selector, defaulting to 30 fps, and paused animation while hidden, occluded, or asleep
- Consolidated system samples into one snapshot update and reduced disk-capacity checks to once every 30 seconds
- Added a Signal Analysis display selector for the spinning signal or a live GPU-history silhouette along the grid horizon
- Added optional GPU-rendered CRT tube curvature with a global strength slider and matching curved-screen click coordinates
- Added click-to-cycle Today, Week, Month, and Year ranges to the Market Watch focus chart
- Stabilized horizontal scene scrolling so each direct gesture moves once and momentum cannot reverse it
- Added click-to-cycle target modes directly on the live weather radar
- Kept full-system graph traces below their title and value headers at every typography scale
- Enlarged daily weather low and high temperatures and reserved enough width to prevent truncation
- Restored the green phosphor background tint control without making scene transitions transparent
- Restored the preferred external display by saved identity when macOS reassigns temporary display IDs

### Earlier release-preparation changes

#### Added

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

#### Changed

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
