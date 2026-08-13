# Retrolemetry

A lightweight native macOS console made for a dedicated 960×540 novelty dock display. It uses SwiftUI Canvas and AppKit only—no Electron, web view, bundled assets, or external CRT filter.

Released under the [MIT License](LICENSE).

## Included in this first version

- Exact 960×540 borderless black window
- Remembers a display by its macOS display ID; initially chooses the smallest connected external display
- Repositions itself when that display reconnects
- Settings includes a default-display picker with monitor name, resolution, and connection type
- If an explicitly selected display is disconnected, the console waits hidden instead of opening on the main monitor
- Covers the menu bar on the 960×540 display by default without hiding the menu bar on the main Mac display
- Live CPU, memory, disk, network, load-average, and uptime telemetry
- Four scenes—System Telemetry, Sector Scan, Signal Analysis, and data-only Live System Metrics—with optional automatic cycling
- Segmented meters, CPU history, blinking indicators, a rotating wireframe globe, radar, Lissajous scope, and vector terrain
- Global visual-style toggle: classic green phosphor or cyan/magenta synthwave, applied live to every scene
- Adjustable green background tint in phosphor mode, ranging from true black to a deep green wash
- Visual layout editor with static scene previews, draggable and resizable modules, visibility toggles, per-scene reset, immediate saving, and global font sizing
- Correct 3D globe rotation plus prominent, independent sphere width and height calibration controls for the physical display
- Independent radar width/height calibration, primary and secondary typography controls, and exportable settings backups
- Direct-click layout editing with deterministic movement and isolated corner-handle resizing
- Built-in adjustable bloom, high-definition scan bands, independently adjustable phosphor noise, vignette, and an optional moving VHS tracking band in both styles
- 60 Hz procedural animation with a reduced curve workload for smoother motion
- Larger radar telemetry, trace panels, and labels for the physical 960×540 screen
- Menu-bar waveform icon with Show/Hide, Move Display, Settings, and Quit
- Optional native macOS Launch at Login registration
- Horizontal mouse-wheel navigation between scenes, with no scroll bars
- Smooth pan/wipe transitions between scenes
- Real CPU, memory, disk, and network data integrated throughout
- Full-screen data-only scene with oversized metrics and CPU, memory, and network history
- Radar scene weather panel with current temperature, feels-like temperature, humidity, wind, rain, and 12-hour temperature/precipitation graphs
- `SIGUSR1` toggle for BetterTouchTool automation

GPU utilization and temperatures are intentionally omitted: macOS does not expose them through a stable public API suitable for a lightweight App Store-safe implementation.

## Run

Open `Package.swift` in Xcode and run the internal `DockTelemetry` executable, or from Terminal:

```sh
swift run DockTelemetry
```

Use full Xcode or a Command Line Tools installation whose Swift compiler and macOS SDK versions match.

## Controls

- **1–4:** select a scene; **4** opens the data-only Live System Metrics view
- **0** or **A:** resume automatic 24-second cycling
- Disable **Automatically cycle scenes** in Settings to keep the current scene fixed while retaining horizontal scrolling and keys 1–4
- Menu-bar icon → **Show / Hide Console**
- **⌘⇧D:** toggle while the menu is open/active

## Layout editor

Open the menu-bar icon → **Settings…** → **Layout Editor**. Choose a scene, then:

- Click and drag any outlined module to move it
- Drag the yellow lower-right handle to resize it
- Use the module checkboxes to show or remove individual blocks
- Adjust **Font size** for all scenes
- Use **Reset this view** to restore only the selected scene

Every edit is saved immediately and applied to the live dock display. The permanent header, footer, and outer frame remain locked so the console chrome cannot be accidentally lost.

For BetterTouchTool, add a **Run Shell Script / Task** action:

```sh
killall -USR1 DockTelemetry
```

That hides the window to reveal Wallspace underneath, or shows it again on the preferred dock display. The app keeps running while hidden, so the return is immediate.

The waveform-icon **Settings…** panel lets you choose the default display, enable Launch at Login, enable or disable the slideshow, switch every scene between phosphor and synthwave styles, change the automatic scene interval, tune the built-in CRT effect, and turn menu-bar covering on or off.

Local weather uses macOS Core Location and the Open-Meteo forecast API. The first launch of this version asks for location permission. Weather data comes directly from the forecast service because macOS does not expose the Weather app's saved locations or displayed forecast to third-party apps.
