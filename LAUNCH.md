# Retrolemetry launch copy

Drafts for use after v1.0.0 is published. Confirm the release/download links work, check each community's current posting rules, and attach a clean native-resolution screenshot or short capture before posting.

## r/macapps

**Title:** Retrolemetry — a native system console for tiny secondary Mac displays

I built Retrolemetry for the 960×540 display in a Mac dock. Its console scales proportionally to other macOS-visible displays. It is a SwiftUI/AppKit menu-bar app with local CPU, memory, disk, network, GPU and battery-flow readings, optional weather and market data, and four animated views.

It remembers a dedicated display, waits safely if that screen is disconnected, supports Launch at Login, and includes a visual layout editor plus green-phosphor and synthwave themes. There is also a `SIGUSR1` toggle for BetterTouchTool automation.

The app code is open source under MIT. There is no Electron, account, analytics, or bundled credential. Weather uses Core Location plus Open-Meteo; optional live quotes use your own Finnhub key stored in Keychain. In-app updates use Sparkle with signed feeds and downloads.

GitHub / download: https://github.com/SamSpring/Retrolemetry/releases/tag/v1.0.0

I would especially appreciate feedback from people using unusual dock displays or compact HDMI screens.

## r/macOS

**Title:** I made a native macOS telemetry display for the tiny screen in my dock

Retrolemetry turns a compact secondary display into a live system console. It has CPU, memory, disk and network telemetry, animated weather and vector scenes, optional local weather and market data, two visual themes, and a layout editor. Its 960×540 composition scales proportionally to other display sizes.

The app is native SwiftUI/AppKit, runs from the menu bar, remembers its target display, and hides instead of jumping onto the main screen when that display disconnects. It includes signed in-app updates through Sparkle. The app code is MIT licensed, with no accounts or analytics.

Project and download: https://github.com/SamSpring/Retrolemetry/releases/tag/v1.0.0

## Show HN

**Title:** Show HN: Retrolemetry – a native macOS console for dedicated mini displays

Retrolemetry is an open-source SwiftUI/AppKit menu-bar app that turns a secondary display into a live system and vector console. It began on a 960×540 dock display and now scales to other display sizes.

I built it to solve the awkward parts of using a dock display: it remembers a specific monitor, restores itself after reconnection, can cover only that display's menu bar, and stays hidden rather than moving to the primary display when its target is absent. It includes real CPU, memory, disk, network, load and uptime data; four animated views; optional Open-Meteo weather; layout editing; and signal-based automation for BetterTouchTool.

The console is native SwiftUI/AppKit with Metal rendering; Sparkle 2 handles signed update checks, downloads, installation, and relaunch. No Electron, accounts, analytics, or embedded API keys. Optional Finnhub quotes use your own Keychain-protected key. macOS 14+; application code MIT licensed.

Code and release: https://github.com/SamSpring/Retrolemetry

I would welcome feedback on the display-selection behavior, packaging, and other small-screen hardware people want to support.

## Ko-fi page

**Page title:** Support Retrolemetry

Retrolemetry is a native, open-source macOS console for compact secondary displays. It began as a way to make the tiny screen in a Mac dock genuinely useful, with live system telemetry, animated vector views, local weather, and careful dedicated-display behavior.

If you enjoy the app, a tip helps cover Apple developer costs, test hardware, and time spent improving compatibility and polish. Retrolemetry remains MIT licensed and available on GitHub.

Download and source: https://github.com/SamSpring/Retrolemetry

Thank you for supporting small, focused Mac software.

## Short Ko-fi announcement

Retrolemetry v1.0.0 is out: a native, open-source macOS telemetry console for tiny secondary displays. Four animated views, optional local weather, display memory, layout controls, and no Electron or analytics. Download it here: https://github.com/SamSpring/Retrolemetry/releases/tag/v1.0.0
