import AppKit
import SwiftUI
import CoreGraphics
import ServiceManagement

@main
enum RetrolemetryApp {
    @MainActor private static var retainedDelegate: AppDelegate?

    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        retainedDelegate = delegate
        application.delegate = delegate
        application.run()
    }
}

struct OutputResolutionPreset: Identifiable {
    let id: String
    let title: String
    let size: CGSize?

    static let matchDisplay = OutputResolutionPreset(id: "display", title: "Match selected display (Recommended)", size: nil)
    static let custom = OutputResolutionPreset(id: "custom", title: "Custom size", size: nil)
    static let all: [OutputResolutionPreset] = [
        matchDisplay,
        .init(id: "960x540", title: "960 × 540 — novelty display", size: .init(width: 960, height: 540)),
        .init(id: "1280x720", title: "1280 × 720 — HD Mac/display", size: .init(width: 1280, height: 720)),
        .init(id: "1440x900", title: "1440 × 900 — Mac 16:10", size: .init(width: 1440, height: 900)),
        .init(id: "1680x1050", title: "1680 × 1050 — Mac 16:10", size: .init(width: 1680, height: 1050)),
        .init(id: "1920x1080", title: "1920 × 1080 — Full HD", size: .init(width: 1920, height: 1080)),
        .init(id: "2560x1600", title: "2560 × 1600 — Mac Retina 16:10", size: .init(width: 2560, height: 1600)),
        .init(id: "2560x1440", title: "2560 × 1440 — QHD", size: .init(width: 2560, height: 1440)),
        .init(id: "3840x2160", title: "3840 × 2160 — 4K", size: .init(width: 3840, height: 2160)),
        .init(id: "1024x768", title: "1024 × 768 — iPad 4:3", size: .init(width: 1024, height: 768)),
        .init(id: "1366x1024", title: "1366 × 1024 — iPad landscape", size: .init(width: 1366, height: 1024)),
        .init(id: "2048x1536", title: "2048 × 1536 — iPad Retina", size: .init(width: 2048, height: 1536)),
        .init(id: "2732x2048", title: "2732 × 2048 — large iPad", size: .init(width: 2732, height: 2048)),
        .init(id: "844x390", title: "844 × 390 — phone landscape", size: .init(width: 844, height: 390)),
        .init(id: "932x430", title: "932 × 430 — large phone landscape", size: .init(width: 932, height: 430)),
        custom
    ]

    static func find(_ id: String) -> OutputResolutionPreset {
        all.first(where: { $0.id == id }) ?? matchDisplay
    }
}

struct SettingsView: View {
    private enum Page: String, CaseIterable, Identifiable {
        case general = "General"
        case layout = "Layout Editor"
        var id: String { rawValue }
    }

    @ObservedObject private var layouts = LayoutStore.shared
    @AppStorage("DockTelemetry.cycleDuration") private var cycleDuration = 30.0
    @AppStorage("DockTelemetry.automaticCycleEnabled") private var automaticCycleEnabled = true
    @AppStorage("DockTelemetry.sceneOrder") private var sceneOrderRaw = SceneOrder.defaultValue
    @AppStorage("DockTelemetry.coverMenuBar") private var coverMenuBar = true
    @AppStorage("DockTelemetry.crtEnabled") private var crtEnabled = true
    @AppStorage("DockTelemetry.bloomStrength") private var bloomStrength = 0.72
    @AppStorage("DockTelemetry.scanlineStrength") private var scanlineStrength = 0.22
    @AppStorage("DockTelemetry.noiseStrength") private var noiseStrength = 0.32
    @AppStorage("DockTelemetry.vhsTrackingEnabled") private var vhsTrackingEnabled = true
    @AppStorage("DockTelemetry.trackingLine1Thickness") private var trackingLine1Thickness = 1.5
    @AppStorage("DockTelemetry.trackingLine2Thickness") private var trackingLine2Thickness = 8.0
    @AppStorage("DockTelemetry.phosphorBackgroundTint") private var phosphorBackgroundTint = 0.12
    @AppStorage("DockTelemetry.visualStyle") private var visualStyleRaw = ConsoleStyle.phosphor.rawValue
    @AppStorage("DockTelemetry.sceneTransitionStyle") private var transitionStyleRaw = SceneTransitionStyle.pan.rawValue
    @AppStorage("DockTelemetry.marketSymbols") private var marketSymbols = MarketSymbols.defaultValue
    @AppStorage("DockTelemetry.marketClock1") private var marketClock1 = "America/New_York"
    @AppStorage("DockTelemetry.marketClock2") private var marketClock2 = "America/Los_Angeles"
    @AppStorage("DockTelemetry.marketClock3") private var marketClock3 = "Europe/London"
    @AppStorage("DockTelemetry.weatherForecastDays") private var weatherForecastDays = 5
    @AppStorage("DockTelemetry.radarWidthCorrection") private var radarWidthCorrection = 1.10
    @AppStorage("DockTelemetry.radarHeightCorrection") private var radarHeightCorrection = 0.9254
    @AppStorage("DockTelemetry.outputResolutionPreset") private var outputResolutionPreset = OutputResolutionPreset.matchDisplay.id
    @AppStorage("DockTelemetry.customOutputWidth") private var customOutputWidth = 960
    @AppStorage("DockTelemetry.customOutputHeight") private var customOutputHeight = 540
    @AppStorage("DockTelemetry.globeWidthCorrection") private var globeWidthCorrection = 1.10
    @AppStorage("DockTelemetry.globeHeightCorrection") private var globeHeightCorrection = 0.9254
    @State private var selectedDisplayID = 0
    @State private var displayRefresh = UUID()
    @State private var launchAtLogin = false
    @State private var launchError: String?
    @State private var exportMessage: String?
    @State private var marketKeyDraft = ""
    @State private var marketKeyConfigured = false
    @State private var marketCredentialMessage: String?
    @State private var cycleDurationDraft = ""
    @State private var page: Page = .general

    private var screens: [NSScreen] {
        _ = displayRefresh
        return NSScreen.screens.sorted {
            if $0.displayID == NSScreen.main?.displayID { return true }
            if $1.displayID == NSScreen.main?.displayID { return false }
            return $0.localizedName < $1.localizedName
        }
    }

    @ViewBuilder private var marketClockOptions: some View {
        ForEach(MarketClockZone.options) { zone in
            Text(zone.title).tag(zone.id)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Settings page", selection: $page) {
                    ForEach(Page.allCases) { page in
                        Text(page.rawValue).tag(page)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 300)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.bar)

            Divider()

            if page == .general {
              Form {
            Section("Display") {
                Picker("Default display", selection: $selectedDisplayID) {
                    Text("Automatic — smallest external display").tag(0)
                    ForEach(screens, id: \.displayID) { screen in
                        Text(screen.displayLabel).tag(Int(screen.displayID))
                    }
                }
                .onChange(of: selectedDisplayID) {
                    saveDisplaySelection(selectedDisplayID)
                }
                Toggle("Cover the menu bar on the dock display", isOn: $coverMenuBar)
                Picker("Console size", selection: $outputResolutionPreset) {
                    ForEach(OutputResolutionPreset.all) { preset in
                        Text(preset.title).tag(preset.id)
                    }
                }
                if outputResolutionPreset == OutputResolutionPreset.custom.id {
                    HStack {
                        TextField("Width", value: $customOutputWidth, format: .number)
                        Text("×")
                        TextField("Height", value: $customOutputHeight, format: .number)
                    }
                    .frame(maxWidth: 320)
                    .onChange(of: customOutputWidth) { customOutputWidth = min(7680, max(320, customOutputWidth)) }
                    .onChange(of: customOutputHeight) { customOutputHeight = min(4320, max(240, customOutputHeight)) }
                }
                Text("The 960×540 layout scales proportionally and is centered without stretching. Match Display works best for Macs and iPad Sidecar. Phone presets work when another app exposes the phone to macOS as an external display.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Startup") {
                Toggle("Launch Retrolemetry at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { updateLaunchAtLogin($0) }
                ))
                if let launchError {
                    Text(launchError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Section("Automatic scenes") {
                Toggle("Automatically cycle scenes", isOn: $automaticCycleEnabled)
                Picker("Change scene every", selection: $cycleDuration) {
                    Text("15 sec").tag(15.0)
                    Text("30 sec").tag(30.0)
                    Text("60 sec").tag(60.0)
                    Text("3 min").tag(180.0)
                }
                .pickerStyle(.segmented)
                .disabled(!automaticCycleEnabled)
                HStack {
                    TextField("Custom seconds", text: $cycleDurationDraft)
                        .frame(width: 130)
                        .onSubmit { applyCustomInterval() }
                    Button("Apply Interval") { applyCustomInterval() }
                    Text("5–3600 seconds")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(!automaticCycleEnabled)
                Picker("Scene transition", selection: $transitionStyleRaw) {
                    ForEach(SceneTransitionStyle.allCases) { style in
                        Text(style.title).tag(style.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                Text("Slideshow order")
                    .font(.headline)
                ForEach(Array(SceneOrder.parse(sceneOrderRaw).enumerated()), id: \.element) { index, scene in
                    HStack {
                        Text("\(index + 1).  \(scene.title)")
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Button { moveSceneOrder(at: index, by: -1) } label: {
                            Image(systemName: "chevron.up")
                        }
                        .disabled(index == 0)
                        Button { moveSceneOrder(at: index, by: 1) } label: {
                            Image(systemName: "chevron.down")
                        }
                        .disabled(index == ConsoleScene.allCases.count - 1)
                    }
                }
                Text("When disabled, horizontal mouse scrolling and keys 1–4 still change scenes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Live market data") {
                TextField("Symbols", text: $marketSymbols)
                    .font(.system(.body, design: .monospaced))
                HStack {
                    Button("Apply Symbols") { applyMarketSymbols() }
                    Text("Up to 12 symbols; the first five appear in ticker A and the next five in ticker B.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                SecureField(marketKeyConfigured ? "Paste a replacement Finnhub API key" : "Finnhub API key", text: $marketKeyDraft)
                HStack {
                    Button(marketKeyConfigured ? "Replace API Key" : "Save API Key") { saveMarketKey() }
                        .disabled(marketKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if marketKeyConfigured {
                        Button("Remove API Key", role: .destructive) { removeMarketKey() }
                    }
                    Text(marketKeyConfigured ? "KEYCHAIN: CONFIGURED" : "KEYCHAIN: NOT CONFIGURED")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .foregroundStyle(marketKeyConfigured ? Color.green : Color.secondary)
                }
                if let marketCredentialMessage {
                    Text(marketCredentialMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("The API key is stored in macOS Keychain, never in preferences or settings backups. Quotes are requested directly from Finnhub every 12 seconds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Clock 1", selection: $marketClock1) { marketClockOptions }
                Picker("Clock 2", selection: $marketClock2) { marketClockOptions }
                Picker("Clock 3", selection: $marketClock3) { marketClockOptions }
                Text("World clocks automatically follow each location's daylight-saving rules.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Weather forecast") {
                Stepper("Daily outlook: \(weatherForecastDays) days", value: $weatherForecastDays, in: 3...7)
                Text("The weather screen always shows the next 12 hourly points plus the selected number of daily forecast rows.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Typography") {
                LabeledContent("Primary values") {
                    Slider(value: $layouts.fontScale, in: 0.75...2.0).frame(width: 260)
                }
                Text("Primary \(Int(layouts.fontScale * 100))%")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                LabeledContent("Secondary text") {
                    Slider(value: $layouts.secondaryFontScale, in: 0.65...2.0).frame(width: 260)
                }
                Text("Labels and headings \(Int(layouts.secondaryFontScale * 100))%")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                LabeledContent("Other text") {
                    Slider(value: $layouts.auxiliaryFontScale, in: 0.65...2.0).frame(width: 260)
                }
                Text("Chrome, status, and remaining text \(Int(layouts.auxiliaryFontScale * 100))%")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Section("Visual style") {
                Toggle("Synthwave colors", isOn: Binding(
                    get: { visualStyleRaw == ConsoleStyle.synthwave.rawValue },
                    set: { visualStyleRaw = $0 ? ConsoleStyle.synthwave.rawValue : ConsoleStyle.phosphor.rawValue }
                ))
                HStack {
                    Text(visualStyleRaw == ConsoleStyle.synthwave.rawValue ? "CYAN  /  MAGENTA  /  MIDNIGHT" : "GREEN PHOSPHOR  /  BLACK")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                    Spacer()
                    Circle()
                        .fill(visualStyleRaw == ConsoleStyle.synthwave.rawValue ? Color.cyan : Color.green)
                        .frame(width: 10, height: 10)
                    Circle()
                        .fill(visualStyleRaw == ConsoleStyle.synthwave.rawValue ? Color.pink : Color.green.opacity(0.45))
                        .frame(width: 10, height: 10)
                }
                if visualStyleRaw == ConsoleStyle.phosphor.rawValue {
                    LabeledContent("Green background tint") {
                        Slider(value: $phosphorBackgroundTint, in: 0...1)
                            .frame(width: 220)
                    }
                    Text("Zero is true black; maximum adds a deep green phosphor wash.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Bloom, scanlines, noise, and vignette", isOn: $crtEnabled)
                if crtEnabled {
                    LabeledContent("Bloom") {
                        Slider(value: $bloomStrength, in: 0...1).frame(width: 220)
                    }
                    LabeledContent("Scanlines") {
                        Slider(value: $scanlineStrength, in: 0...1).frame(width: 220)
                    }
                    LabeledContent("Noise") {
                        Slider(value: $noiseStrength, in: 0...1).frame(width: 220)
                    }
                    Toggle("Moving VHS tracking lines", isOn: $vhsTrackingEnabled)
                    if vhsTrackingEnabled {
                        LabeledContent("Line 1 thickness") {
                            Slider(value: $trackingLine1Thickness, in: 0.5...18).frame(width: 220)
                        }
                        Text(String(format: "%.1f px", trackingLine1Thickness))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                        LabeledContent("Line 2 thickness") {
                            Slider(value: $trackingLine2Thickness, in: 1...36).frame(width: 220)
                        }
                        Text(String(format: "%.1f px", trackingLine2Thickness))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                Text("The selected style applies to every telemetry, weather, and vector scene.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Radar shape") {
                LabeledContent("Radar width") {
                    Slider(value: $radarWidthCorrection, in: 0.70...1.35).frame(width: 220)
                }
                Text("Width \(String(format: "%.0f%%", radarWidthCorrection * 100))")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                LabeledContent("Radar height") {
                    Slider(value: $radarHeightCorrection, in: 0.70...1.35).frame(width: 220)
                }
                Text("Height \(String(format: "%.0f%%", radarHeightCorrection * 100))")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Section("Globe shape") {
                LabeledContent("Globe width") {
                    Slider(value: $globeWidthCorrection, in: 0.70...1.35).frame(width: 220)
                }
                LabeledContent("Globe height") {
                    Slider(value: $globeHeightCorrection, in: 0.70...1.35).frame(width: 220)
                }
                Text("Use these only to compensate for unusual physical display scaling; equal values keep the globe mathematically round.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Settings backup") {
                Button("Export Settings Backup…") { exportSettings() }
                if let exportMessage {
                    Text(exportMessage).font(.caption).foregroundStyle(.secondary)
                }
                Text("Exports layouts, module visibility, display choice, market symbols, typography, slideshow, visual style, CRT, and radar calibration. API keys are never exported.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Text("Keys 1–4 choose a scene. Press 0 or A to resume cycling when automatic scenes are enabled. Horizontal mouse scrolling always moves between scenes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
              }
              .formStyle(.grouped)
            } else {
              LayoutEditorView()
            }
        }
        .frame(minWidth: 1040, maxWidth: .infinity, minHeight: 720, maxHeight: .infinity, alignment: .top)
        .onAppear {
            selectedDisplayID = UserDefaults.standard.integer(forKey: DisplayPreference.idKey)
            launchAtLogin = SMAppService.mainApp.status == .enabled
            marketKeyConfigured = MarketKeychain.apiKey() != nil
            cycleDurationDraft = String(format: "%.0f", cycleDuration)
        }
        .onChange(of: cycleDuration) {
            cycleDurationDraft = String(format: "%.0f", cycleDuration)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            displayRefresh = UUID()
        }
    }

    private func saveDisplaySelection(_ id: Int) {
        guard id != 0,
              let screen = NSScreen.screens.first(where: { Int($0.displayID) == id }) else {
            DisplayPreference.clear()
            return
        }
        DisplayPreference.save(screen)
    }

    private func applyMarketSymbols() {
        let parsed = MarketSymbols.parse(marketSymbols)
        marketSymbols = (parsed.isEmpty ? MarketSymbols.parse(MarketSymbols.defaultValue) : parsed).joined(separator: ", ")
        NotificationCenter.default.post(name: .marketConfigurationDidChange, object: nil)
        marketCredentialMessage = "Market symbols updated."
    }

    private func applyCustomInterval() {
        guard let value = Double(cycleDurationDraft.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            cycleDurationDraft = String(format: "%.0f", cycleDuration)
            return
        }
        cycleDuration = min(3600, max(5, value))
        cycleDurationDraft = String(format: "%.0f", cycleDuration)
    }

    private func moveSceneOrder(at index: Int, by offset: Int) {
        var scenes = SceneOrder.parse(sceneOrderRaw)
        let destination = index + offset
        guard scenes.indices.contains(index), scenes.indices.contains(destination) else { return }
        scenes.swapAt(index, destination)
        sceneOrderRaw = SceneOrder.encode(scenes)
    }

    private func saveMarketKey() {
        do {
            try MarketKeychain.save(apiKey: marketKeyDraft)
            marketKeyDraft = ""
            marketKeyConfigured = true
            marketCredentialMessage = "Finnhub API key saved securely."
        } catch {
            marketCredentialMessage = "Could not save the API key: \(error.localizedDescription)"
        }
    }

    private func removeMarketKey() {
        MarketKeychain.delete()
        marketKeyDraft = ""
        marketKeyConfigured = false
        marketCredentialMessage = "Finnhub API key removed."
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        launchError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            launchError = "macOS could not update Login Items: \(error.localizedDescription)"
        }
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.title = "Export Retrolemetry Settings"
        panel.nameFieldStringValue = "Retrolemetry-Settings-Backup.plist"
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            saveSettingsBackup(to: url)
        }
        if let parent = NSApp.keyWindow {
            panel.beginSheetModal(for: parent, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }

    private func saveSettingsBackup(to url: URL) {
        let bundleID = Bundle.main.bundleIdentifier ?? "io.github.SamSpring.Retrolemetry"
        var values = UserDefaults.standard.persistentDomain(forName: bundleID) ?? [:]
        values = values.filter { $0.key.hasPrefix("DockTelemetry.") }
        values["DockTelemetry.backupFormat"] = 1
        values["DockTelemetry.backupCreatedAt"] = Date()
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
            try data.write(to: url, options: .atomic)
            exportMessage = "Saved \(url.lastPathComponent)"
        } catch {
            exportMessage = "Export failed: \(error.localizedDescription)"
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var controller: DisplayWindowController?
    private var settingsController: SettingsWindowController?
    private var statusItem: NSStatusItem?
    private weak var consoleMenuItem: NSMenuItem?
    private weak var styleMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        migrateLegacyPreferences()
        // Keep the legacy key namespace so early-build settings survive the public rename.
        UserDefaults.standard.register(defaults: [
            "DockTelemetry.cycleDuration": 30.0,
            "DockTelemetry.automaticCycleEnabled": true,
            "DockTelemetry.sceneOrder": SceneOrder.defaultValue,
            "DockTelemetry.coverMenuBar": true,
            "DockTelemetry.crtEnabled": true,
            "DockTelemetry.bloomStrength": 0.80466796875,
            "DockTelemetry.scanlineStrength": 0.8629296875,
            "DockTelemetry.noiseStrength": 0.82953125,
            "DockTelemetry.vhsTrackingEnabled": true,
            "DockTelemetry.trackingLine1Thickness": 1.5,
            "DockTelemetry.trackingLine2Thickness": 8.0,
            "DockTelemetry.phosphorBackgroundTint": 0.3661328125,
            "DockTelemetry.globeWidthCorrection": 1.10,
            "DockTelemetry.globeHeightCorrection": 0.9254256185,
            "DockTelemetry.radarWidthCorrection": 1.10,
            "DockTelemetry.radarHeightCorrection": 0.9254256185,
            "DockTelemetry.signalSynthwaveGrid": false,
            "DockTelemetry.signalGridAnimationEnabled": true,
            "DockTelemetry.signalGridMetric": SignalGridMetric.cpu.rawValue,
            "DockTelemetry.signalGridPattern": SignalGridPattern.recede.rawValue,
            "DockTelemetry.signalGridResponse": SignalGridResponse.medium.rawValue,
            "DockTelemetry.layoutSnapEnabled": false,
            "DockTelemetry.layoutSnapStep": 10.0,
            "DockTelemetry.outputResolutionPreset": OutputResolutionPreset.matchDisplay.id,
            "DockTelemetry.customOutputWidth": 960,
            "DockTelemetry.customOutputHeight": 540,
            "DockTelemetry.fontScale": 1.45,
            "DockTelemetry.secondaryFontScale": 1.0,
            "DockTelemetry.auxiliaryFontScale": 1.0,
            "DockTelemetry.sceneTransitionStyle": SceneTransitionStyle.pan.rawValue,
            "DockTelemetry.marketSymbols": MarketSymbols.defaultValue,
            "DockTelemetry.marketClock1": "America/New_York",
            "DockTelemetry.marketClock2": "America/Los_Angeles",
            "DockTelemetry.marketClock3": "Europe/London",
            "DockTelemetry.weatherForecastDays": 5,
            "DockTelemetry.visualStyle": ConsoleStyle.phosphor.rawValue
        ])
        NSApp.setActivationPolicy(.accessory)
        installStatusItem()
        controller = DisplayWindowController()
        controller?.show()
        installSignalToggle()
    }

    private func migrateLegacyPreferences() {
        let defaults = UserDefaults.standard
        for domainName in ["com.sam.docktelemetry", "DockTelemetry"] {
            guard let legacyValues = defaults.persistentDomain(forName: domainName) else { continue }
            for (key, value) in legacyValues where key.hasPrefix("DockTelemetry.") {
                if defaults.object(forKey: key) == nil {
                    defaults.set(value, forKey: key)
                }
            }
        }
    }

    func applicationShouldRestoreState(_ app: NSApplication) -> Bool { false }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(
            systemSymbolName: "waveform.path.ecg",
            accessibilityDescription: "Retrolemetry"
        ) ?? NSImage(
            systemSymbolName: "waveform",
            accessibilityDescription: "Retrolemetry"
        )
        icon?.isTemplate = true
        item.button?.image = icon
        item.button?.imagePosition = .imageOnly
        item.button?.toolTip = "Retrolemetry"

        let menu = NSMenu()
        let toggle = NSMenuItem(title: "Hide Console", action: #selector(toggleConsole), keyEquivalent: "d")
        toggle.target = self
        toggle.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(toggle)
        consoleMenuItem = toggle
        let move = NSMenuItem(title: "Move to Preferred Display", action: #selector(moveConsole), keyEquivalent: "")
        move.target = self
        menu.addItem(move)
        menu.addItem(.separator())
        let style = NSMenuItem(title: "Synthwave Colors", action: #selector(toggleVisualStyle), keyEquivalent: "s")
        style.target = self
        style.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(style)
        styleMenuItem = style
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Retrolemetry", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        menu.delegate = self
        item.menu = menu
        statusItem = item
        updateConsoleMenuItem()
        updateStyleMenuItem()
    }

    private func installSignalToggle() {
        signal(SIGUSR1, SIG_IGN)
        signal(SIGUSR2, SIG_IGN)
        let displaySource = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        displaySource.setEventHandler { [weak self] in self?.toggleConsole() }
        displaySource.resume()
        let styleSource = DispatchSource.makeSignalSource(signal: SIGUSR2, queue: .main)
        styleSource.setEventHandler { [weak self] in self?.toggleVisualStyle() }
        styleSource.resume()
        SignalHolder.shared.displaySource = displaySource
        SignalHolder.shared.styleSource = styleSource
    }

    @objc private func toggleConsole() {
        controller?.toggle()
        updateConsoleMenuItem()
    }
    @objc private func moveConsole() { controller?.moveToPreferredDisplay(force: true) }
    @objc private func toggleVisualStyle() {
        let defaults = UserDefaults.standard
        let isSynthwave = defaults.string(forKey: "DockTelemetry.visualStyle") == ConsoleStyle.synthwave.rawValue
        defaults.set(
            isSynthwave ? ConsoleStyle.phosphor.rawValue : ConsoleStyle.synthwave.rawValue,
            forKey: "DockTelemetry.visualStyle"
        )
        updateStyleMenuItem()
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateConsoleMenuItem()
        updateStyleMenuItem()
    }

    private func updateConsoleMenuItem() {
        consoleMenuItem?.title = controller?.isRequestedVisible == true ? "Hide Console" : "Show Console"
    }

    private func updateStyleMenuItem() {
        let isSynthwave = UserDefaults.standard.string(forKey: "DockTelemetry.visualStyle") == ConsoleStyle.synthwave.rawValue
        styleMenuItem?.state = isSynthwave ? .on : .off
    }

    @objc private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if settingsController == nil {
            settingsController = SettingsWindowController()
        }
        settingsController?.show()
    }
    @objc private func quit() { NSApp.terminate(nil) }
}

private final class SignalHolder {
    static let shared = SignalHolder()
    var displaySource: DispatchSourceSignal?
    var styleSource: DispatchSourceSignal?
}

@MainActor
final class DisplayWindowController {
    private let window: ConsoleWindow
    private var screenObserver: NSObjectProtocol?
    private var defaultsObserver: NSObjectProtocol?
    private var requestedVisible = true

    var isRequestedVisible: Bool { requestedVisible }

    init() {
        let root = AdaptiveConsoleRoot()
        window = ConsoleWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: root)
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.level = Self.consoleLevel
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isMovableByWindowBackground = false
        window.setContentSize(NSSize(width: 960, height: 540))

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let owner = self else { return }
            Task { @MainActor in owner.displayConfigurationChanged() }
        }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let owner = self else { return }
            Task { @MainActor in
                owner.applyWindowLevel()
                owner.moveToPreferredDisplay(force: true)
            }
        }
        applyWindowLevel()
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
    }

    func show() {
        requestedVisible = true
        if moveToPreferredDisplay(force: false) {
            window.orderFrontRegardless()
        } else {
            window.orderOut(nil)
        }
    }

    func toggle() {
        if window.isVisible || requestedVisible {
            requestedVisible = false
            window.orderOut(nil)
        } else {
            show()
        }
    }

    @discardableResult
    func moveToPreferredDisplay(force: Bool) -> Bool {
        guard let target = preferredScreen() else {
            window.orderOut(nil)
            return false
        }
        if force || window.screen?.displayID != target.displayID || !window.isVisible {
            let frame = target.frame
            let size = outputSize(for: target)
            let origin = NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.midY - size.height / 2
            )
            window.setFrame(NSRect(origin: origin, size: size), display: true)
        }
        if requestedVisible { window.orderFrontRegardless() }
        return true
    }

    private func displayConfigurationChanged() {
        guard requestedVisible else { return }
        _ = moveToPreferredDisplay(force: true)
    }

    private func applyWindowLevel() {
        window.level = UserDefaults.standard.bool(forKey: "DockTelemetry.coverMenuBar")
            ? Self.consoleLevel
            : .normal
    }

    private func outputSize(for screen: NSScreen) -> NSSize {
        let defaults = UserDefaults.standard
        let preset = OutputResolutionPreset.find(defaults.string(forKey: "DockTelemetry.outputResolutionPreset") ?? "display")
        guard preset.id != OutputResolutionPreset.matchDisplay.id else { return screen.frame.size }

        let requested: CGSize
        if preset.id == OutputResolutionPreset.custom.id {
            requested = CGSize(
                width: min(7680, max(320, defaults.integer(forKey: "DockTelemetry.customOutputWidth"))),
                height: min(4320, max(240, defaults.integer(forKey: "DockTelemetry.customOutputHeight")))
            )
        } else {
            requested = preset.size ?? CGSize(width: 960, height: 540)
        }
        let fit = min(1, screen.frame.width / requested.width, screen.frame.height / requested.height)
        return NSSize(width: requested.width * fit, height: requested.height * fit)
    }

    private static var consoleLevel: NSWindow.Level {
        NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
    }

    private func preferredScreen() -> NSScreen? {
        let stored = UInt32(UserDefaults.standard.integer(forKey: DisplayPreference.idKey))
        if stored != 0, let match = NSScreen.screens.first(where: { $0.displayID == stored }) {
            return match
        }
        if stored != 0 {
            guard let restored = DisplayPreference.restoredScreen() else { return nil }
            DisplayPreference.save(restored)
            return restored
        }

        let external = NSScreen.screens.filter { CGDisplayIsBuiltin($0.displayID) == 0 }
        return external.min(by: { ($0.frame.width * $0.frame.height) < ($1.frame.width * $1.frame.height) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}

private struct AdaptiveConsoleRoot: View {
    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / 960, proxy.size.height / 540)
            ZStack {
                Color.black
                ConsoleView()
                    .frame(width: 960, height: 540)
                    .scaleEffect(scale)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .background(Color.black)
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.title = "Retrolemetry Settings"
        window.identifier = NSUserInterfaceItemIdentifier("Retrolemetry.Settings")
        window.contentView = NSHostingView(rootView: SettingsView())
        window.contentMinSize = NSSize(width: 1040, height: 720)
        window.isReleasedWhenClosed = false
        window.delegate = self
    }

    func show() {
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}

enum DisplayPreference {
    static let idKey = "DockTelemetry.preferredDisplayID"
    private static let nameKey = "DockTelemetry.preferredDisplayName"
    private static let widthKey = "DockTelemetry.preferredDisplayWidth"
    private static let heightKey = "DockTelemetry.preferredDisplayHeight"

    static func save(_ screen: NSScreen) {
        let defaults = UserDefaults.standard
        defaults.set(Int(screen.displayID), forKey: idKey)
        defaults.set(screen.localizedName, forKey: nameKey)
        defaults.set(Int(screen.frame.width.rounded()), forKey: widthKey)
        defaults.set(Int(screen.frame.height.rounded()), forKey: heightKey)
    }

    static func clear() {
        let defaults = UserDefaults.standard
        [idKey, nameKey, widthKey, heightKey].forEach { defaults.removeObject(forKey: $0) }
    }

    static func restoredScreen() -> NSScreen? {
        let defaults = UserDefaults.standard
        let name = defaults.string(forKey: nameKey)
        let width = defaults.integer(forKey: widthKey)
        let height = defaults.integer(forKey: heightKey)
        return NSScreen.screens.first {
            let sameName = name != nil && $0.localizedName == name
            let sameSize = Int($0.frame.width.rounded()) == width && Int($0.frame.height.rounded()) == height
            return sameName && sameSize
        }
    }
}

private final class ConsoleWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    var displayLabel: String {
        let role = CGDisplayIsBuiltin(displayID) != 0 ? "Built-in" : "External"
        return "\(localizedName) — \(Int(frame.width))×\(Int(frame.height)) (\(role))"
    }
}
