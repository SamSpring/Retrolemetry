import AppKit
import SwiftUI
import CoreGraphics
import ServiceManagement

@main
struct DockTelemetryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

struct SettingsView: View {
    @ObservedObject private var layouts = LayoutStore.shared
    @AppStorage("DockTelemetry.cycleDuration") private var cycleDuration = 24.0
    @AppStorage("DockTelemetry.automaticCycleEnabled") private var automaticCycleEnabled = true
    @AppStorage("DockTelemetry.coverMenuBar") private var coverMenuBar = true
    @AppStorage("DockTelemetry.crtEnabled") private var crtEnabled = true
    @AppStorage("DockTelemetry.bloomStrength") private var bloomStrength = 0.72
    @AppStorage("DockTelemetry.scanlineStrength") private var scanlineStrength = 0.22
    @AppStorage("DockTelemetry.noiseStrength") private var noiseStrength = 0.32
    @AppStorage("DockTelemetry.vhsTrackingEnabled") private var vhsTrackingEnabled = true
    @AppStorage("DockTelemetry.phosphorBackgroundTint") private var phosphorBackgroundTint = 0.12
    @AppStorage("DockTelemetry.visualStyle") private var visualStyleRaw = ConsoleStyle.phosphor.rawValue
    @AppStorage("DockTelemetry.globeWidthCorrection") private var globeWidthCorrection = 1.10
    @AppStorage("DockTelemetry.globeHeightCorrection") private var globeHeightCorrection = 1.00
    @AppStorage("DockTelemetry.radarWidthCorrection") private var radarWidthCorrection = 1.10
    @AppStorage("DockTelemetry.radarHeightCorrection") private var radarHeightCorrection = 0.9254
    @State private var selectedDisplayID = 0
    @State private var displayRefresh = UUID()
    @State private var launchAtLogin = false
    @State private var launchError: String?
    @State private var exportMessage: String?

    private var screens: [NSScreen] {
        _ = displayRefresh
        return NSScreen.screens.sorted {
            if $0.displayID == NSScreen.main?.displayID { return true }
            if $1.displayID == NSScreen.main?.displayID { return false }
            return $0.localizedName < $1.localizedName
        }
    }

    var body: some View {
        TabView {
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
                Text("The console stays exactly 960×540 and draws above the menu bar only on its own display.")
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
                    Text("15 seconds").tag(15.0)
                    Text("24 seconds").tag(24.0)
                    Text("40 seconds").tag(40.0)
                }
                .pickerStyle(.segmented)
                .disabled(!automaticCycleEnabled)
                Text("When disabled, horizontal mouse scrolling and keys 1–4 still change scenes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Typography") {
                LabeledContent("Primary values") {
                    Slider(value: $layouts.fontScale, in: 0.75...1.45).frame(width: 220)
                }
                Text("Primary \(Int(layouts.fontScale * 100))%")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                LabeledContent("Secondary text") {
                    Slider(value: $layouts.secondaryFontScale, in: 0.65...1.45).frame(width: 220)
                }
                Text("Labels and headings \(Int(layouts.secondaryFontScale * 100))%")
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
                    Toggle("Moving VHS tracking line", isOn: $vhsTrackingEnabled)
                }
                Text("The selected style applies to every telemetry, weather, and vector scene.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Sphere shape") {
                LabeledContent("Sphere width") {
                    Slider(value: $globeWidthCorrection, in: 0.70...1.35)
                        .frame(width: 220)
                }
                HStack {
                    Text("NARROWER")
                    Spacer()
                    Text("\(String(format: "%.0f%%", globeWidthCorrection * 100))")
                    Spacer()
                    Text("WIDER")
                }
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                LabeledContent("Sphere height") {
                    Slider(value: $globeHeightCorrection, in: 0.70...1.35)
                        .frame(width: 220)
                }
                HStack {
                    Text("SHORTER")
                    Spacer()
                    Text("\(String(format: "%.0f%%", globeHeightCorrection * 100))")
                    Spacer()
                    Text("TALLER")
                }
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                Text("Adjust width and height while looking at the physical dock display until the sphere is circular. Both controls are always visible at the top of Layout Editor.")
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
            Section("Settings backup") {
                Button("Export Settings Backup…") { exportSettings() }
                if let exportMessage {
                    Text(exportMessage).font(.caption).foregroundStyle(.secondary)
                }
                Text("Exports layouts, module visibility, display choice, typography, slideshow, visual style, CRT, and roundness settings.")
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
          .padding(12)
          .tabItem { Label("General", systemImage: "gearshape") }

          LayoutEditorView()
              .tabItem { Label("Layout Editor", systemImage: "rectangle.3.group") }
        }
        .frame(width: 920, height: 650)
        .onAppear {
            selectedDisplayID = UserDefaults.standard.integer(forKey: DisplayPreference.idKey)
            launchAtLogin = SMAppService.mainApp.status == .enabled
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
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let bundleID = Bundle.main.bundleIdentifier ?? "com.sam.docktelemetry"
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
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: DisplayWindowController?
    private var settingsController: SettingsWindowController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            "DockTelemetry.cycleDuration": 40.0,
            "DockTelemetry.automaticCycleEnabled": true,
            "DockTelemetry.coverMenuBar": true,
            "DockTelemetry.crtEnabled": true,
            "DockTelemetry.bloomStrength": 0.80466796875,
            "DockTelemetry.scanlineStrength": 0.8629296875,
            "DockTelemetry.noiseStrength": 0.82953125,
            "DockTelemetry.vhsTrackingEnabled": true,
            "DockTelemetry.phosphorBackgroundTint": 0.3661328125,
            "DockTelemetry.globeWidthCorrection": 1.10,
            "DockTelemetry.globeHeightCorrection": 0.9254256185,
            "DockTelemetry.radarWidthCorrection": 1.10,
            "DockTelemetry.radarHeightCorrection": 0.9254256185,
            "DockTelemetry.fontScale": 1.45,
            "DockTelemetry.secondaryFontScale": 1.0,
            "DockTelemetry.visualStyle": ConsoleStyle.phosphor.rawValue
        ])
        NSApp.setActivationPolicy(.accessory)
        controller = DisplayWindowController()
        controller?.show()
        installStatusItem()
        installSignalToggle()
        closeLegacySettingsWindow()
    }

    func applicationShouldRestoreState(_ app: NSApplication) -> Bool { false }

    private func closeLegacySettingsWindow() {
        DispatchQueue.main.async {
            NSApp.windows
                .filter { $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" }
                .forEach { $0.close() }
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "waveform.path.ecg.rectangle", accessibilityDescription: "Retrolemetry")
        item.button?.toolTip = "Retrolemetry"

        let menu = NSMenu()
        let toggle = NSMenuItem(title: "Show / Hide Console", action: #selector(toggleConsole), keyEquivalent: "d")
        toggle.target = self
        toggle.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(toggle)
        let move = NSMenuItem(title: "Move to Preferred Display", action: #selector(moveConsole), keyEquivalent: "")
        move.target = self
        menu.addItem(move)
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Retrolemetry", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
    }

    private func installSignalToggle() {
        signal(SIGUSR1, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        source.setEventHandler { [weak self] in self?.controller?.toggle() }
        source.resume()
        SignalHolder.shared.source = source
    }

    @objc private func toggleConsole() { controller?.toggle() }
    @objc private func moveConsole() { controller?.moveToPreferredDisplay(force: true) }
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
    var source: DispatchSourceSignal?
}

@MainActor
final class DisplayWindowController {
    private let window: ConsoleWindow
    private var screenObserver: NSObjectProtocol?
    private var defaultsObserver: NSObjectProtocol?
    private var requestedVisible = true

    init() {
        let root = ConsoleView()
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
            Task { @MainActor in self?.displayConfigurationChanged() }
        }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applyWindowLevel()
                self?.moveToPreferredDisplay(force: true)
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
            let origin = NSPoint(
                x: frame.midX - 480,
                y: frame.midY - 270
            )
            window.setFrame(NSRect(origin: origin, size: NSSize(width: 960, height: 540)), display: true)
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

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 650),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.title = "Retrolemetry Settings"
        window.identifier = NSUserInterfaceItemIdentifier("DockTelemetry.Settings")
        window.contentView = NSHostingView(rootView: SettingsView())
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
