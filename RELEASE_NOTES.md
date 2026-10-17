# Retrolemetry v1.0.0

Retrolemetry is a native macOS system console designed around compact 960×540 secondary displays and scaled proportionally to other display sizes. It combines live system telemetry, vector-style animation, local weather, and precise display controls in a lightweight menu-bar app.

## Highlights

- Secure in-app update checks through the menu-bar menu, with verified downloads, installation and relaunch; optional automatic checks in Settings
- Four animated views: Market Watch, Weather, Signal Analysis, and Live System Metrics
- Automatic external-display selection with a remembered preferred display
- Green-phosphor and synthwave themes with configurable CRT-style effects
- Menu-bar synthwave switching, dual adjustable VHS tracking lines, and three scene transition styles
- A visual layout editor with module positioning, sizing, visibility, and typography controls
- Optional layout snapping and a no-scroll editing tray for typography, modules, and precise frame controls
- Separate typography scaling for primary values, secondary labels, and remaining chrome/status text
- Scene tabs in Settings and text scaling up to 300% without resetting saved layouts
- Five independent text-size groups for readings, all dim less-phosphorescent text, bright main text, and separate frame headers/footers; old saved sizes stay intact
- Double-click the live console to pause/resume the slideshow; horizontal scene navigation still works while paused
- A live Finnhub market panel with editable watch symbols and secure Keychain credential storage
- A dedicated market-watch scene with a rotating globe, separate clocks, two five-symbol ticker boards, a click-to-cycle Today/Week/Month/Year focus chart, and USD→ILS daily reference history
- Configurable Florida, Los Angeles, and London world clocks with automatic daylight-saving handling
- A richer weather view with upcoming hourly conditions, a configurable 3–7-day outlook, and weather-driven radar targets that cycle when the radar is clicked
- Automatic or manual Israel/North America/Europe forecast maps with regional rain probability, temperature, and wind arrows at six public locations (forecast models, not live radar imagery); Israel retains its Tel Aviv-Yafo outline
- Configurable slideshow ordering and intervals, plus a responsive synthwave perspective grid with three animation patterns and selectable telemetry input
- Proportional output sizing for compact displays, Macs, iPad/Sidecar, phone-landscape adapters, and custom dimensions
- Physical-display calibration for globe and radar proportions
- Optional Launch at Login and BetterTouchTool-compatible show/hide automation
- Stable one-gesture horizontal scene navigation that ignores trailing momentum reversals

## Install

Download `Retrolemetry-1.0.0.zip`, move `Retrolemetry.app` to `/Applications`, and open it. Retrolemetry requires macOS 14 or later. Grant location permission only if you want local weather.

## Privacy

System telemetry stays on the Mac. If weather is enabled, an approximate coordinate is sent directly to Open-Meteo over HTTPS. Retrolemetry has no account, analytics, advertising, bundled tracking SDK, or weather API key.

The selected Israel, North America, or Europe forecast map also requests six fixed public coordinates from Open-Meteo every 15 minutes. These regional forecast requests do not include the personal coordinate. Natural Earth supplies public-domain map artwork and the Tel Aviv city-coordinate dataset is © OpenStreetMap contributors under ODbL, separately from the MIT application code.

If live market data is configured, ticker symbols are sent directly to Finnhub and the user's personal API key remains in macOS Keychain. Focus-chart requests send the selected symbol to Yahoo's public chart endpoint. The USD→ILS panel requests public daily reference-rate history from Frankfurter. No market-data credential is bundled with the app or repository.

Update checks contact Retrolemetry's GitHub Pages feed and GitHub release downloads. No system profile, location, stock symbols, or personal API key is attached to those requests. GitHub receives ordinary network requests, including the network address and app/version user agent.

## Known limitations

- The interface is composed at 960×540 and scales proportionally; narrow or portrait displays may show letterboxing.
- GPU utilization depends on optional driver counters and shows N/A on unsupported hardware. Battery wattage is electrical flow through the battery, not total Mac or CPU/GPU consumption; voltage/current may be unavailable. Temperature sensors are not included.
- Launch at Login requires the bundled app to be installed in a stable location such as `/Applications`.

## Release integrity

Publication remains held for Samuel's final decision. The current candidate is the app-owner-accepted, updater-enabled universal build 28. Its exact retained archive includes the application license and map-data notices and has passed Developer ID signing, Apple notarization, stapled-ticket validation and Gatekeeper checks. The developer's 60 tests passed and all 47 protected settings remained unchanged. Isolated production-app installation, update, rejection, relaunch, synthetic settings/Keychain preservation and actual Launch at Login checks have now passed. The separate encrypted update-signing-key recovery backup was independently verified and locked. When published, `SHA256SUMS.txt` will identify the exact ZIP also used by the signed update feed. Earlier candidate archives must not be published, and these preparation results do not mean the public download or feed is live.
