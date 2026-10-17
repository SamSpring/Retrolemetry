import SwiftUI

struct ModuleFrame: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var visible: Bool = true

    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct SceneModule: Identifiable, Hashable {
    let id: String
    let name: String
}

enum LayoutDefaults {
    static func modules(for scene: ConsoleScene) -> [SceneModule] {
        switch scene {
        case .system:
            [
                module("marketFocus", "Market focus chart"), module("globe", "Rotating globe"),
                module("marketClocks", "World clocks"), module("marketTickerA", "Ticker board A"),
                module("marketTickerB", "Ticker board B"), module("fxGraph", "USD to ILS graph")
            ]
        case .radar:
            [module("radar", "Radar"), module("weatherHeader", "Weather header"), module("weatherStats", "Weather conditions"), module("temperature", "Hourly forecast"), module("precipitation", "Daily forecast"), module("weatherStatus", "Weather status")]
        case .signal:
            [module("scope", "Signal scope"), module("signalHeader", "Channel header"), module("cpuTrace", "CPU trace"), module("memoryTrace", "Memory trace"), module("networkTrace", "Network trace"), module("ioReadout", "Network I/O")]
        case .fullMetrics:
            [module("metricCPU", "CPU tile"), module("metricGPU", "GPU tile"), module("metricMemory", "Memory tile"), module("metricDisk", "Disk tile"), module("metricNetwork", "Network tile"), module("metricPower", "Power / voltage tile"), module("graphCPU", "CPU graph"), module("graphGPU", "GPU graph"), module("graphMemory", "Memory graph"), module("graphNetwork", "Network TX / RX graph"), module("statusUptime", "Uptime"), module("statusLoad", "Load averages"), module("statusTX", "Network RX")]
        }
    }

    static func frames(for scene: ConsoleScene) -> [String: ModuleFrame] {
        switch scene {
        case .system:
            return [
                "marketFocus": frame(30, 60, 360, 260),
                "globe": frame(410, 60, 240, 260),
                "marketClocks": frame(670, 60, 260, 120),
                "fxGraph": frame(670, 200, 260, 120),
                "marketTickerA": frame(30, 340, 430, 150),
                "marketTickerB": frame(480, 340, 450, 150)
            ]
        case .radar:
            return [
                "radar": frame(25, 55, 438.8523, 429.6496), "weatherHeader": frame(480, 58, 455, 60),
                "weatherStats": frame(480, 130, 455, 62), "temperature": frame(480, 204, 455, 92),
                "precipitation": frame(480, 307, 455, 138),
                "weatherStatus": frame(480, 457, 455, 30)
            ]
        case .signal:
            return [
                "scope": frame(50, 78, 860, 320), "signalHeader": frame(62, 90, 836, 25),
                "cpuTrace": frame(62, 418, 200, 78), "memoryTrace": frame(274, 418, 200, 78),
                "networkTrace": frame(486, 418, 200, 78), "ioReadout": frame(698, 418, 217.7964, 77.9483)
            ]
        case .fullMetrics:
            let tileW = (904.0 - 5 * 12) / 6
            let tileStep = tileW + 12
            return [
                "metricCPU": frame(28, 55, tileW, 132), "metricGPU": frame(28 + tileStep, 55, tileW, 132),
                "metricMemory": frame(28 + tileStep * 2, 55, tileW, 132), "metricDisk": frame(28 + tileStep * 3, 55, tileW, 132),
                "metricNetwork": frame(28 + tileStep * 4, 55, tileW, 132), "metricPower": frame(28 + tileStep * 5, 55, tileW, 132),
                "graphCPU": frame(28, 199, 217, 184), "graphGPU": frame(257, 199, 217, 184),
                "graphMemory": frame(486, 199, 217, 184), "graphNetwork": frame(715, 199, 217, 184),
                "statusUptime": frame(28, 395, 290.7309, 108.1884),
                "statusLoad": frame(333, 394.7723, 292.7358, 107.8150),
                "statusTX": frame(638, 395, 287.8994, 107.7403)
            ]
        }
    }

    /// Preserve hand-arranged layouts. Newly added modules start hidden there so they
    /// cannot cover existing modules; untouched old defaults can adopt the expanded layout.
    static func merging(_ saved: [String: ModuleFrame], for scene: ConsoleScene) -> [String: ModuleFrame] {
        var defaults = frames(for: scene)
        if scene == .fullMetrics, saved["metricGPU"] == nil {
            let legacy = legacyMetricsFrames
            if saved.allSatisfy({ legacy[$0.key] == $0.value }) { return defaults }
            for id in ["metricGPU", "metricPower", "graphGPU"] { defaults[id]?.visible = false }
        }
        return defaults.merging(saved) { _, saved in saved }
    }

    private static var legacyMetricsFrames: [String: ModuleFrame] {
        [
            "metricCPU": frame(28, 55, 217, 116), "metricMemory": frame(257, 55, 217, 116),
            "metricDisk": frame(486, 55, 217, 116), "metricNetwork": frame(715, 55, 217, 116),
            "graphCPU": frame(28, 183, 293, 200), "graphMemory": frame(333, 183, 293, 200),
            "graphNetwork": frame(638, 183, 294, 200),
            "statusUptime": frame(28, 395, 290.7309, 108.1884),
            "statusLoad": frame(333, 394.7723, 292.7358, 107.8150),
            "statusTX": frame(638, 395, 287.8994, 107.7403)
        ]
    }

    private static func module(_ id: String, _ name: String) -> SceneModule { SceneModule(id: id, name: name) }
    private static func frame(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> ModuleFrame {
        ModuleFrame(x: x, y: y, width: width, height: height)
    }
}

@MainActor
final class LayoutStore: ObservableObject {
    static let shared = LayoutStore()
    @Published private(set) var layouts: [String: [String: ModuleFrame]] = [:]
    @Published private var interactionPreview: InteractionPreview?
    @Published var fontScale: Double {
        didSet { defaults.set(fontScale, forKey: "DockTelemetry.fontScale") }
    }
    @Published var secondaryFontScale: Double {
        didSet { defaults.set(secondaryFontScale, forKey: "DockTelemetry.secondaryFontScale") }
    }
    @Published var auxiliaryFontScale: Double {
        didSet { defaults.set(auxiliaryFontScale, forKey: "DockTelemetry.auxiliaryFontScale") }
    }
    @Published var globalTypographyEnabled: Bool {
        didSet { defaults.set(globalTypographyEnabled, forKey: "DockTelemetry.typography.global") }
    }
    @Published private var sceneTypography: [String: ConsoleTypography] = [:]
    @Published private var globalTypographyGroups: [String: Double] = [:]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        fontScale = defaults.object(forKey: "DockTelemetry.fontScale") as? Double ?? 1.45
        secondaryFontScale = defaults.object(forKey: "DockTelemetry.secondaryFontScale") as? Double ?? 1
        auxiliaryFontScale = defaults.object(forKey: "DockTelemetry.auxiliaryFontScale") as? Double ?? 1
        globalTypographyEnabled = defaults.object(forKey: "DockTelemetry.typography.global") as? Bool ?? true
        if let data = defaults.data(forKey: "DockTelemetry.typography.groups.v2"),
           let saved = try? JSONDecoder().decode([String: Double].self, from: data) {
            globalTypographyGroups = saved.filter { $0.value.isFinite && (0.65...3).contains($0.value) }
        }
        for scene in ConsoleScene.allCases {
            if let data = defaults.data(forKey: "DockTelemetry.typography.v1.\(scene.rawValue)"),
               let saved = try? JSONDecoder().decode(ConsoleTypography.self, from: data) {
                sceneTypography[sceneKey(scene)] = saved
            }
        }
        for scene in ConsoleScene.allCases { layouts[sceneKey(scene)] = load(scene) }
    }

    func typography(for scene: ConsoleScene) -> ConsoleTypography {
        let global = ConsoleTypography(primary: fontScale, secondary: secondaryFontScale, other: auxiliaryFontScale, groups: globalTypographyGroups)
        return globalTypographyEnabled ? global : (sceneTypography[sceneKey(scene)] ?? global)
    }

    func setFontScale(_ value: Double, role: ConsoleFontRole, scene: ConsoleScene) {
        let value = min(3, max(role == .primary ? 0.75 : 0.65, value))
        if globalTypographyEnabled {
            globalTypographyGroups[role.rawValue] = value
            if let data = try? JSONEncoder().encode(globalTypographyGroups) {
                defaults.set(data, forKey: "DockTelemetry.typography.groups.v2")
            }
        } else {
            var typography = typography(for: scene)
            typography[role] = value
            sceneTypography[sceneKey(scene)] = typography
            if let data = try? JSONEncoder().encode(typography) {
                defaults.set(data, forKey: "DockTelemetry.typography.v1.\(scene.rawValue)")
            }
        }
    }

    func frame(_ scene: ConsoleScene, _ module: String) -> ModuleFrame {
        if interactionPreview?.scene == scene, interactionPreview?.module == module,
           let previewFrame = interactionPreview?.frame {
            return previewFrame
        }
        return layouts[sceneKey(scene)]?[module] ?? LayoutDefaults.frames(for: scene)[module] ?? ModuleFrame(x: 40, y: 80, width: 200, height: 100)
    }

    func update(_ scene: ConsoleScene, module: String, frame: ModuleFrame) {
        var sceneLayout = layouts[sceneKey(scene)] ?? LayoutDefaults.frames(for: scene)
        sceneLayout[module] = constrained(frame)
        layouts[sceneKey(scene)] = sceneLayout
        save(scene, sceneLayout)
    }

    /// Preview drag and resize changes in memory, then save once at mouse-up.
    func previewInteraction(_ scene: ConsoleScene, module: String, frame: ModuleFrame) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            interactionPreview = InteractionPreview(scene: scene, module: module, frame: constrained(frame))
        }
    }

    func commitInteraction() {
        guard let preview = interactionPreview else { return }
        var sceneLayout = layouts[sceneKey(preview.scene)] ?? LayoutDefaults.frames(for: preview.scene)
        sceneLayout[preview.module] = preview.frame
        layouts[sceneKey(preview.scene)] = sceneLayout
        interactionPreview = nil
        save(preview.scene, sceneLayout)
    }

    func cancelInteraction() {
        interactionPreview = nil
    }

    func setVisible(_ visible: Bool, scene: ConsoleScene, module: String) {
        var value = frame(scene, module)
        value.visible = visible
        update(scene, module: module, frame: value)
    }

    func reset(_ scene: ConsoleScene) {
        let defaults = LayoutDefaults.frames(for: scene)
        layouts[sceneKey(scene)] = defaults
        save(scene, defaults)
    }

    private func constrained(_ value: ModuleFrame) -> ModuleFrame {
        var result = value
        result.width = min(930, max(70, result.width))
        result.height = min(470, max(38, result.height))
        result.x = min(945 - result.width, max(15, result.x))
        result.y = min(505 - result.height, max(45, result.y))
        return result
    }

    private func sceneKey(_ scene: ConsoleScene) -> String { String(scene.rawValue) }
    private func storageKey(_ scene: ConsoleScene) -> String {
        scene == .system
            ? "DockTelemetry.layout.v5.\(scene.rawValue)"
            : "DockTelemetry.layout.v3.\(scene.rawValue)"
    }

    private func load(_ scene: ConsoleScene) -> [String: ModuleFrame] {
        guard let data = defaults.data(forKey: storageKey(scene)),
              let saved = try? JSONDecoder().decode([String: ModuleFrame].self, from: data) else {
            return LayoutDefaults.frames(for: scene)
        }
        return LayoutDefaults.merging(saved, for: scene)
    }

    private func save(_ scene: ConsoleScene, _ layout: [String: ModuleFrame]) {
        guard let data = try? JSONEncoder().encode(layout) else { return }
        defaults.set(data, forKey: storageKey(scene))
    }

    private struct InteractionPreview {
        let scene: ConsoleScene
        let module: String
        let frame: ModuleFrame
    }
}

struct LayoutModuleContainer<Content: View>: View {
    @ObservedObject private var layouts = LayoutStore.shared
    let scene: ConsoleScene
    let module: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        let value = layouts.frame(scene, module)
        if value.visible {
            content()
                .frame(width: value.width, height: value.height)
                .clipped()
                .position(x: value.x + value.width / 2, y: value.y + value.height / 2)
        }
    }
}

struct LayoutEditorView: View {
    @ObservedObject private var layouts = LayoutStore.shared
    @StateObject private var marketPreview = MarketModel(preview: true)
    @ObservedObject private var weatherLocation = WeatherLocation.shared
    @AppStorage("DockTelemetry.visualStyle") private var visualStyleRaw = ConsoleStyle.phosphor.rawValue
    @AppStorage("DockTelemetry.crtEnabled") private var crtEnabled = true
    @AppStorage("DockTelemetry.crtTubeEnabled") private var crtTubeEnabled = false
    @AppStorage("DockTelemetry.crtTubeStrength") private var crtTubeStrength = 0.35
    @AppStorage("DockTelemetry.phosphorBackgroundTint") private var phosphorTint = 0.12
    @AppStorage("DockTelemetry.bloomStrength") private var bloom = 0.72
    @AppStorage("DockTelemetry.scanlineStrength") private var scanlines = 0.22
    @AppStorage("DockTelemetry.noiseStrength") private var noise = 0.32
    @AppStorage("DockTelemetry.vhsTrackingEnabled") private var tracking = true
    @AppStorage("DockTelemetry.trackingLine1Thickness") private var firstLine = 1.5
    @AppStorage("DockTelemetry.trackingLine2Thickness") private var secondLine = 8.0
    @State private var previewEffects = true
    @AppStorage("DockTelemetry.radarWidthCorrection") private var radarWidthCorrection = 1.10
    @AppStorage("DockTelemetry.radarHeightCorrection") private var radarHeightCorrection = 0.9254
    @AppStorage("DockTelemetry.radarTargetMode") private var radarTargetModeRaw = RadarTargetMode.precipitation.rawValue
    @AppStorage("DockTelemetry.radarTargetPulse") private var radarTargetPulse = true
    @AppStorage(WeatherRegionSelection.preferenceKey) private var regionSelectionRaw = WeatherRegionSelection.automatic.rawValue
    @AppStorage("DockTelemetry.globeWidthCorrection") private var globeWidthCorrection = 1.10
    @AppStorage("DockTelemetry.globeHeightCorrection") private var globeHeightCorrection = 0.9254
    @AppStorage("DockTelemetry.signalSynthwaveGrid") private var signalSynthwaveGrid = false
    @AppStorage("DockTelemetry.signalDisplayMode") private var signalDisplayModeRaw = SignalDisplayMode.spinning.rawValue
    @AppStorage("DockTelemetry.signalGridAnimationEnabled") private var signalGridAnimationEnabled = true
    @AppStorage("DockTelemetry.signalGridMetric") private var signalGridMetricRaw = SignalGridMetric.cpu.rawValue
    @AppStorage("DockTelemetry.signalGridPattern") private var signalGridPatternRaw = SignalGridPattern.recede.rawValue
    @AppStorage("DockTelemetry.signalGridResponse") private var signalGridResponseRaw = SignalGridResponse.medium.rawValue
    @AppStorage("DockTelemetry.layoutSnapEnabled") private var snapEnabled = false
    @AppStorage("DockTelemetry.layoutSnapStep") private var snapStep = 10.0
    @State private var scene: ConsoleScene = .system
    @State private var selection = "marketFocus"
    @State private var interactionModule: String?
    @State private var interactionStart: ModuleFrame?
    @State private var interactionKind: InteractionKind?
    private let scale = 0.68

    private enum InteractionKind: Equatable { case move, resize }

    init(initialScene: ConsoleScene = .system) {
        _scene = State(initialValue: initialScene)
        _selection = State(initialValue: LayoutDefaults.modules(for: initialScene).first?.id ?? "")
    }

    var body: some View {
        return VStack(spacing: 14) {
            HStack {
                Picker("View", selection: $scene) {
                    ForEach(ConsoleScene.allCases, id: \.self) { Text($0.tabTitle).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                .frame(width: 440)
                .onChange(of: scene) {
                    layouts.cancelInteraction()
                    clearInteraction()
                    selection = LayoutDefaults.modules(for: scene).first?.id ?? ""
                }
                Spacer()
                Toggle("Preview CRT effects", isOn: $previewEffects)
                Button("Reset this view") { layouts.reset(scene) }
            }

            HStack(alignment: .top, spacing: 14) {
                editorCanvas
                editorInspector
            }
            editorBottomTray
        }
        .padding(18)
    }

    private var editorInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Layout") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Snap while dragging", isOn: $snapEnabled)
                    Picker("Grid", selection: $snapStep) {
                        Text("5 px").tag(5.0)
                        Text("10 px").tag(10.0)
                        Text("20 px").tag(20.0)
                    }
                    .disabled(!snapEnabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if scene == .signal {
                GroupBox("Signal Analysis") {
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("Display", selection: $signalDisplayModeRaw) {
                            ForEach(SignalDisplayMode.allCases) { mode in
                                Text(mode.title).tag(mode.rawValue)
                            }
                        }
                        Toggle("Synthwave perspective grid", isOn: $signalSynthwaveGrid)
                        Group {
                            Toggle("Animate grid", isOn: $signalGridAnimationEnabled)
                            Picker("Pattern", selection: $signalGridPatternRaw) {
                                ForEach(SignalGridPattern.allCases) { pattern in
                                    Text(pattern.title).tag(pattern.rawValue)
                                }
                            }
                            Picker("Respond to", selection: $signalGridMetricRaw) {
                                ForEach(SignalGridMetric.allCases) { metric in
                                    Text(metric.title).tag(metric.rawValue)
                                }
                            }
                            Picker("Frequency response", selection: $signalGridResponseRaw) {
                                ForEach(SignalGridResponse.allCases) { response in
                                    Text(response.title).tag(response.rawValue)
                                }
                            }
                            Text("GPU uses optional driver utilization counters. Unsupported Macs show N/A, not system load.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .disabled(!signalSynthwaveGrid)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if scene == .radar {
                GroupBox("Radar") {
                    VStack(spacing: 9) {
                        WeatherRegionPicker()
                        editorSlider("Width", value: $radarWidthCorrection, range: 0.70...1.35)
                        editorSlider("Height", value: $radarHeightCorrection, range: 0.70...1.35)
                        Picker("Targets", selection: $radarTargetModeRaw) {
                            ForEach(RadarTargetMode.allCases) { mode in
                                Text(mode.title).tag(mode.rawValue)
                            }
                        }
                        Toggle("Pulse targets", isOn: $radarTargetPulse)
                        Text("Automatic uses your weather location; manual selection needs no location permission. Six regional forecast points refresh every 15 minutes—not live radar echoes. Click the radar to cycle targets.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } else if scene == .system {
                GroupBox("Globe shape") {
                    VStack(spacing: 9) {
                        editorSlider("Width", value: $globeWidthCorrection, range: 0.70...1.35)
                        editorSlider("Height", value: $globeHeightCorrection, range: 0.70...1.35)
                    }
                }
            } else if scene == .fullMetrics {
                GroupBox("GPU and power") {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("GPU reports the busiest available device. Power and voltage describe battery flow, not total Mac power.")
                        Text("New modules start hidden in custom layouts to avoid overlaps. Enable them below, or reset this view for the expanded six-tile layout.")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 290, height: 540 * scale)
    }

    private var editorBottomTray: some View {
        HStack(alignment: .top, spacing: 12) {
            GroupBox("Typography") {
                VStack(spacing: 9) {
                    Toggle("Apply to all views", isOn: $layouts.globalTypographyEnabled)
                    ForEach(ConsoleFontRole.allCases, id: \.self) { role in
                        editorSlider(role.title, value: fontBinding(role), range: (role == .primary ? 0.75 : 0.65)...3.0)
                    }
                    Text("Dark texts: all dim text, wherever it appears. Main text: bright labels and names.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 310)

            GroupBox("Modules") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 7) {
                    ForEach(LayoutDefaults.modules(for: scene)) { module in
                        let value = layouts.frame(scene, module.id)
                        HStack(spacing: 5) {
                            Toggle("", isOn: Binding(
                                get: { value.visible },
                                set: {
                                    layouts.setVisible($0, scene: scene, module: module.id)
                                    if !$0 && selection == module.id {
                                        selection = ""
                                        layouts.cancelInteraction()
                                        clearInteraction()
                                    }
                                }
                            )).labelsHidden()
                            Button(module.name) { selection = module.id }
                                .buttonStyle(.plain)
                                .lineLimit(1)
                                .foregroundStyle(selection == module.id ? Color.accentColor : Color.primary)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 360)

            GroupBox("Selected module") {
                if let module = LayoutDefaults.modules(for: scene).first(where: { $0.id == selection }) {
                    moduleControls(module)
                } else {
                    Text("Click a module to select it. Click empty canvas space to clear the selection.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func editorSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        HStack(spacing: 8) {
            Text(title).frame(width: 122, alignment: .leading)
            Slider(value: value, in: range)
            Text("\(Int(value.wrappedValue * 100))%")
                .monospacedDigit()
                .frame(width: 42, alignment: .trailing)
        }
    }

    private func fontBinding(_ role: ConsoleFontRole) -> Binding<Double> {
        Binding(get: { layouts.typography(for: scene)[role] },
                set: { layouts.setFontScale($0, role: role, scene: scene) })
    }

    private var editorCanvas: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            staticScene
            ZStack {
                ForEach(LayoutDefaults.modules(for: scene).filter { layouts.frame(scene, $0.id).visible }) { module in
                    moduleBox(module)
                }
            }
            .frame(width: 960 * scale, height: 540 * scale)
            .modifier(CRTTubeEffect(enabled: previewEffects && crtTubeEnabled, strength: crtTubeStrength,
                size: CGSize(width: 960 * scale, height: 540 * scale), opaqueBackground: false))
        }
        .foregroundStyle(Color(red: 0.34, green: 1, blue: 0.43))
        .font(.system(size: 8, weight: .bold, design: .monospaced))
        .frame(width: 960 * scale, height: 540 * scale)
        .contentShape(Rectangle())
        .gesture(editorGesture)
        .transaction { transaction in transaction.animation = nil }
        .clipped()
        .overlay(Rectangle().stroke(Color.green.opacity(0.7), lineWidth: 1))
    }

    private var staticScene: some View {
        let style = ConsoleStyle(rawValue: visualStyleRaw) ?? .phosphor
        ThemeRuntime.palette = style.palette
        let telemetry = TelemetrySnapshot(
            cpu: 0.38, memory: 0.61, disk: 0.62,
            networkIn: 240_000, networkOut: 82_000,
            uptime: 213_420, load: (2.4, 3.1, 3.8), gpu: 0.68,
            power: PowerReading(voltage: 12.16, current: -0.85),
            memoryCapacity: CapacityReading(totalBytes: 32_000_000_000, usedBytes: 19_520_000_000),
            diskCapacity: CapacityReading(totalBytes: 1_000_000_000_000, usedBytes: 620_000_000_000)
        )
        let cpu = (0..<96).map { 0.24 + sin(Double($0) * 0.22) * 0.11 }
        let memory = (0..<96).map { 0.57 + sin(Double($0) * 0.06) * 0.025 }
        let network = (0..<96).map { max(0.02, sin(Double($0) * 0.31) * 0.18 + 0.12) }
        let gpu: [Double?] = (0..<96).map { 0.48 + sin(Double($0) * 0.17) * 0.28 }
        let previewHour = Date()
        let hourly = previewHourlyForecast(from: previewHour)
        let daily = previewDailyForecast(from: previewHour)
        let selection = WeatherRegionSelection(rawValue: regionSelectionRaw) ?? .automatic
        let region = selection.resolve(coordinate: weatherLocation.coordinate ?? GlobeCoordinate(latitude: 32, longitude: 35))
        let weather = WeatherSnapshot(
            location: "LOCAL PREVIEW", condition: "PARTLY CLOUDY",
            temperature: 24, apparentTemperature: 25, humidity: 0.58,
            windSpeed: 12, precipitation: 0,
            temperatureForecast: [0.72, 0.68, 0.61, 0.55, 0.50, 0.45, 0.42, 0.40, 0.36, 0.34, 0.31, 0.29],
            precipitationForecast: [0.08, 0.05, 0.04, 0.03, 0.04, 0.08, 0.12, 0.09, 0.06, 0.04, 0.03, 0.02],
            hourlyForecast: hourly,
            dailyForecast: daily,
            updatedAt: Date(), status: "STATIC LAYOUT PREVIEW",
            radarWeather: region.map { RadarWeatherPoint.preview(region: $0) } ?? [], radarUpdatedAt: Date(), radarStatus: "STATIC FORECAST PREVIEW", radarRegion: region
        )
        return ZStack {
            ConsoleBackground(style: style, phosphorTintStrength: phosphorTint)
                .modifier(CRTTubeEffect(enabled: previewEffects && crtTubeEnabled, strength: crtTubeStrength))
            Group {
            switch scene {
            case .system:
                SystemScene(market: marketPreview, time: 10, location: weatherLocation.coordinate)
            case .radar:
                RadarScene(weather: weather, time: 10)
            case .signal:
                SignalScene(snapshot: telemetry, cpuHistory: cpu, memoryHistory: memory, networkHistory: network, gpuHistory: gpu, time: 10)
            case .fullMetrics:
                FullMetricsScene(snapshot: telemetry, cpuHistory: cpu, memoryHistory: memory,
                                 networkReceiveHistory: network.map { $0 * 1_000_000 },
                                 networkTransmitHistory: network.reversed().map { $0 * 400_000 }, gpuHistory: gpu, time: 10)
            }
            }
            .consoleFont(14, role: .secondary, weight: .medium, fallback: .other)
            .compositingGroup()
            .shadow(color: previewEffects && crtEnabled ? style.palette.primary.opacity(0.24*bloom) : .clear, radius: 2.5+3.5*bloom)
            .modifier(CRTTubeEffect(enabled: previewEffects && crtTubeEnabled, strength: crtTubeStrength, opaqueBackground: false))
            if previewEffects && crtEnabled {
                CRTOverlay(scanlineStrength: scanlines, noiseStrength: noise, vhsTrackingEnabled: tracking,
                    trackingLine1Thickness: firstLine, trackingLine2Thickness: secondLine, time: 10,
                    tubeStrength: crtTubeEnabled ? crtTubeStrength : 0)
            }
        }
        .frame(width: 960, height: 540)
        .foregroundStyle(style.palette.primary)
        .environment(\.consoleTypography, layouts.typography(for: scene))
        .environment(\.consoleAnimationEnabled, false)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: 960 * scale, height: 540 * scale, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func moduleBox(_ module: SceneModule) -> some View {
        let value = layouts.frame(scene, module.id)
        let selected = selection == module.id
        return ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 3)
                .fill(value.visible ? Color.white.opacity(0.001) : Color.gray.opacity(0.12))
            RoundedRectangle(cornerRadius: 3)
                .stroke(
                    selected ? Color.yellow : (value.visible ? Color.green.opacity(0.38) : Color.gray),
                    style: StrokeStyle(lineWidth: selected ? 2 : 1, dash: value.visible ? [] : [5, 4])
                )
            if selected {
                ZStack {
                    Rectangle().fill(Color.black.opacity(0.8))
                    Rectangle().stroke(Color.yellow, lineWidth: 2)
                    Path { path in
                        path.move(to: CGPoint(x: 4, y: 12))
                        path.addLine(to: CGPoint(x: 12, y: 4))
                        path.move(to: CGPoint(x: 8, y: 12))
                        path.addLine(to: CGPoint(x: 12, y: 8))
                    }
                    .stroke(Color.yellow, lineWidth: 1.5)
                }
                .frame(width: 16, height: 16)
            }
        }
        .frame(width: value.width * scale, height: value.height * scale)
        .position(x: (value.x + value.width / 2) * scale, y: (value.y + value.height / 2) * scale)
        .zIndex(selected ? 20 : 0)
        .opacity(value.visible ? 1 : 0.55)
        .allowsHitTesting(false)
    }

    private var editorGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { gesture in
                if interactionModule == nil {
                    let point = editorPoint(gesture.startLocation)
                    let selectedFrame = layouts.frame(scene, selection)
                    let handle = CGRect(
                        x: selectedFrame.x + selectedFrame.width - 24 / scale,
                        y: selectedFrame.y + selectedFrame.height - 24 / scale,
                        width: 24 / scale,
                        height: 24 / scale
                    )
                    let resizing = !selection.isEmpty && selectedFrame.visible && handle.contains(point)
                    let module = resizing ? selection : hitTest(point)
                    guard !module.isEmpty else {
                        selection = ""
                        layouts.cancelInteraction()
                        clearInteraction()
                        return
                    }
                    selection = module
                    interactionModule = module
                    interactionStart = layouts.frame(scene, module)
                    interactionKind = resizing ? .resize : .move
                }

                guard let module = interactionModule, var updated = interactionStart else { return }
                let start = editorPoint(gesture.startLocation)
                let current = editorPoint(gesture.location)
                let dx = current.x - start.x
                let dy = current.y - start.y
                if interactionKind == .resize {
                    updated.width += dx
                    updated.height += dy
                } else {
                    updated.x += dx
                    updated.y += dy
                }
                if snapEnabled { updated = snapped(updated, kind: interactionKind) }
                layouts.previewInteraction(scene, module: module, frame: updated)
            }
            .onEnded { _ in
                layouts.commitInteraction()
                clearInteraction()
            }
    }

    private func hitTest(_ point: CGPoint) -> String {
        LayoutDefaults.modules(for: scene)
            .filter { layouts.frame(scene, $0.id).visible && layouts.frame(scene, $0.id).rect.contains(point) }
            .min { lhs, rhs in
                let left = layouts.frame(scene, lhs.id)
                let right = layouts.frame(scene, rhs.id)
                return left.width * left.height < right.width * right.height
            }?.id ?? ""
    }

    private func editorPoint(_ point: CGPoint) -> CGPoint {
        CRTTubeGeometry.sourcePoint(for: CGPoint(x: point.x / scale, y: point.y / scale),
            size: CGSize(width: 960, height: 540),
            strength: previewEffects && crtTubeEnabled && CRTTubeEffect.isAvailable ? crtTubeStrength : 0)
    }

    private func clearInteraction() {
        interactionModule = nil
        interactionKind = nil
        interactionStart = nil
    }

    private func snapped(_ value: ModuleFrame, kind: InteractionKind?) -> ModuleFrame {
        let step = max(1, snapStep)
        var result = value
        if kind == .resize {
            result.width = (result.width / step).rounded() * step
            result.height = (result.height / step).rounded() * step
        } else {
            result.x = (result.x / step).rounded() * step
            result.y = (result.y / step).rounded() * step
        }
        return result
    }

    private func previewHourlyForecast(from start: Date) -> [HourlyWeatherPoint] {
        var result: [HourlyWeatherPoint] = []
        for index in 0..<12 {
            let indexValue = Double(index)
            let time = start.addingTimeInterval(indexValue * 3600)
            let temperature = 24 - indexValue * 0.35 + sin(indexValue * 0.7)
            let rainChance = max(0.02, sin(indexValue * 0.42) * 0.18 + 0.12)
            let condition = index < 5 ? "PARTLY CLOUDY" : "CLEAR SKY"
            result.append(HourlyWeatherPoint(
                time: time,
                temperature: temperature,
                precipitationChance: rainChance,
                condition: condition
            ))
        }
        return result
    }

    private func previewDailyForecast(from start: Date) -> [DailyWeatherPoint] {
        var result: [DailyWeatherPoint] = []
        for index in 0..<7 {
            let date = Calendar.current.date(byAdding: .day, value: index, to: start) ?? start
            let low = 18 + Double(index % 2)
            let high = 25 + Double(index % 3)
            let rainChance = Double((index * 17) % 55) / 100
            let condition = index.isMultiple(of: 3) ? "RAIN SHOWERS" : "PARTLY CLOUDY"
            result.append(DailyWeatherPoint(
                date: date,
                low: low,
                high: high,
                precipitationChance: rainChance,
                condition: condition
            ))
        }
        return result
    }

    @ViewBuilder
    private func moduleControls(_ module: SceneModule) -> some View {
        let value = layouts.frame(scene, module.id)
        VStack(alignment: .leading, spacing: 5) {
            Text(module.name).font(.caption).bold()
            HStack {
                Stepper("X \(Int(value.x))", value: frameBinding(module.id, \.x), in: 15...875, step: 1)
                Stepper("Y \(Int(value.y))", value: frameBinding(module.id, \.y), in: 45...467, step: 1)
            }
            HStack {
                Stepper("W \(Int(value.width))", value: frameBinding(module.id, \.width), in: 70...930, step: 1)
                Stepper("H \(Int(value.height))", value: frameBinding(module.id, \.height), in: 38...470, step: 1)
            }
            Text(snapEnabled ? "Dragging snaps to the \(Int(snapStep)) px grid." : "Drag changes save at mouse-up. Steppers save immediately.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    private func frameBinding(_ module: String, _ keyPath: WritableKeyPath<ModuleFrame, Double>) -> Binding<Double> {
        Binding(
            get: { layouts.frame(scene, module)[keyPath: keyPath] },
            set: { newValue in
                var value = layouts.frame(scene, module)
                value[keyPath: keyPath] = newValue
                layouts.update(scene, module: module, frame: value)
            }
        )
    }
}
