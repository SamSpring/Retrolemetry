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
            [module("metricCPU", "CPU tile"), module("metricMemory", "Memory tile"), module("metricDisk", "Disk tile"), module("metricNetwork", "Network tile"), module("graphCPU", "CPU graph"), module("graphMemory", "Memory graph"), module("graphNetwork", "Network graph"), module("statusUptime", "Uptime"), module("statusLoad", "Load averages"), module("statusTX", "Network TX")]
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
            let tileW = 217.0
            return [
                "metricCPU": frame(28, 55, tileW, 116), "metricMemory": frame(257, 55, tileW, 116),
                "metricDisk": frame(486, 55, tileW, 116), "metricNetwork": frame(715, 55, tileW, 116),
                "graphCPU": frame(28, 183, 293, 200), "graphMemory": frame(333, 183, 293, 200),
                "graphNetwork": frame(638, 183, 294, 200),
                "statusUptime": frame(28, 395, 290.7309, 108.1884),
                "statusLoad": frame(333, 394.7723, 292.7358, 107.8150),
                "statusTX": frame(638, 395, 287.8994, 107.7403)
            ]
        }
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
        didSet { UserDefaults.standard.set(fontScale, forKey: "DockTelemetry.fontScale") }
    }
    @Published var secondaryFontScale: Double {
        didSet { UserDefaults.standard.set(secondaryFontScale, forKey: "DockTelemetry.secondaryFontScale") }
    }
    @Published var auxiliaryFontScale: Double {
        didSet { UserDefaults.standard.set(auxiliaryFontScale, forKey: "DockTelemetry.auxiliaryFontScale") }
    }

    private init() {
        fontScale = UserDefaults.standard.object(forKey: "DockTelemetry.fontScale") as? Double ?? 1.45
        secondaryFontScale = UserDefaults.standard.object(forKey: "DockTelemetry.secondaryFontScale") as? Double ?? 1
        auxiliaryFontScale = UserDefaults.standard.object(forKey: "DockTelemetry.auxiliaryFontScale") as? Double ?? 1
        for scene in ConsoleScene.allCases { layouts[sceneKey(scene)] = load(scene) }
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
        guard let data = UserDefaults.standard.data(forKey: storageKey(scene)),
              let saved = try? JSONDecoder().decode([String: ModuleFrame].self, from: data) else {
            return LayoutDefaults.frames(for: scene)
        }
        return LayoutDefaults.frames(for: scene).merging(saved) { _, saved in saved }
    }

    private func save(_ scene: ConsoleScene, _ layout: [String: ModuleFrame]) {
        guard let data = try? JSONEncoder().encode(layout) else { return }
        UserDefaults.standard.set(data, forKey: storageKey(scene))
    }

    private struct InteractionPreview {
        let scene: ConsoleScene
        let module: String
        let frame: ModuleFrame
    }
}

enum FontRuntime {
    nonisolated(unsafe) static var scale = 1.0
    nonisolated(unsafe) static var secondaryScale = 1.0
    nonisolated(unsafe) static var auxiliaryScale = 1.0
}

func consoleFont(_ size: Double, weight: Font.Weight = .regular) -> Font {
    .system(size: size * FontRuntime.scale, weight: weight, design: .monospaced)
}

func consoleSecondaryFont(_ size: Double, weight: Font.Weight = .regular) -> Font {
    .system(size: size * FontRuntime.secondaryScale, weight: weight, design: .monospaced)
}

func consoleAuxiliaryFont(_ size: Double, weight: Font.Weight = .regular) -> Font {
    .system(size: size * FontRuntime.auxiliaryScale, weight: weight, design: .monospaced)
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
                .position(x: value.x + value.width / 2, y: value.y + value.height / 2)
                .clipped()
        }
    }
}

struct LayoutEditorView: View {
    @ObservedObject private var layouts = LayoutStore.shared
    @StateObject private var marketPreview = MarketModel(preview: true)
    @AppStorage("DockTelemetry.radarWidthCorrection") private var radarWidthCorrection = 1.10
    @AppStorage("DockTelemetry.radarHeightCorrection") private var radarHeightCorrection = 0.9254
    @State private var scene: ConsoleScene = .system
    @State private var selection = "marketFocus"
    @State private var interactionModule: String?
    @State private var interactionStart: ModuleFrame?
    @State private var interactionKind: InteractionKind?
    private let scale = 0.68

    private enum InteractionKind { case move, resize }

    var body: some View {
        FontRuntime.scale = layouts.fontScale
        FontRuntime.secondaryScale = layouts.secondaryFontScale
        FontRuntime.auxiliaryScale = layouts.auxiliaryFontScale
        return VStack(spacing: 12) {
            HStack {
                Picker("View", selection: $scene) {
                    ForEach(ConsoleScene.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .frame(width: 320)
                .onChange(of: scene) {
                    layouts.cancelInteraction()
                    clearInteraction()
                    selection = LayoutDefaults.modules(for: scene).first?.id ?? ""
                }
                Spacer(minLength: 20)
                LabeledContent("Font size") {
                    Slider(value: $layouts.fontScale, in: 0.75...1.45).frame(width: 125)
                }
                Text("\(Int(layouts.fontScale * 100))%")
                    .monospacedDigit().frame(width: 42, alignment: .trailing)
                Button("Reset this view") { layouts.reset(scene) }
            }

            HStack {
                LabeledContent("Secondary text") {
                    Slider(value: $layouts.secondaryFontScale, in: 0.65...1.45).frame(width: 125)
                }
                Text("\(Int(layouts.secondaryFontScale * 100))%")
                    .monospacedDigit().frame(width: 42, alignment: .trailing)
                Text("Controls labels, headings, and supporting readouts.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }

            HStack {
                LabeledContent("Other text") {
                    Slider(value: $layouts.auxiliaryFontScale, in: 0.65...1.45).frame(width: 125)
                }
                Text("\(Int(layouts.auxiliaryFontScale * 100))%")
                    .monospacedDigit().frame(width: 42, alignment: .trailing)
                Text("Controls chrome, status, and remaining inherited text.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Text("Radar width").frame(width: 92, alignment: .leading)
                    Text("NARROW").font(.caption2).foregroundStyle(.secondary)
                    Slider(value: $radarWidthCorrection, in: 0.70...1.35).frame(width: 260)
                    Text("WIDE").font(.caption2).foregroundStyle(.secondary)
                    Text("\(Int(radarWidthCorrection * 100))%")
                        .monospacedDigit().frame(width: 42, alignment: .trailing)
                    Spacer()
                }
                HStack(spacing: 12) {
                    Text("Radar height").frame(width: 92, alignment: .leading)
                    Text("SHORT").font(.caption2).foregroundStyle(.secondary)
                    Slider(value: $radarHeightCorrection, in: 0.70...1.35).frame(width: 260)
                    Text("TALL").font(.caption2).foregroundStyle(.secondary)
                    Text("\(Int(radarHeightCorrection * 100))%")
                        .monospacedDigit().frame(width: 42, alignment: .trailing)
                    Text("Adjust both while looking at the physical dock screen until the radar is circular.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
            }

            HStack(alignment: .top, spacing: 14) {
                editorCanvas
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("MODULES").font(.headline)
                        ForEach(LayoutDefaults.modules(for: scene)) { module in
                            let value = layouts.frame(scene, module.id)
                            HStack {
                                Toggle("", isOn: Binding(
                                    get: { value.visible },
                                    set: { layouts.setVisible($0, scene: scene, module: module.id) }
                                )).labelsHidden()
                                Button(module.name) { selection = module.id }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(selection == module.id ? Color.accentColor : Color.primary)
                                Spacer()
                            }
                        }
                        Divider()
                        Text("Drag inside the selected outline to move. Drag the yellow corner handle to resize.")
                            .font(.caption).foregroundStyle(.secondary)
                        if let module = LayoutDefaults.modules(for: scene).first(where: { $0.id == selection }) {
                            moduleControls(module)
                        }
                    }
                }
                .frame(width: 210, height: 367)
            }
        }
        .padding(16)
    }

    private var editorCanvas: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            staticScene
            ForEach(LayoutDefaults.modules(for: scene)) { module in
                moduleBox(module)
            }
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

    @ViewBuilder
    private var staticScene: some View {
        let telemetry = TelemetrySnapshot(
            cpu: 0.38, memory: 0.61, disk: 0.62,
            networkIn: 240_000, networkOut: 82_000,
            uptime: 213_420, load: (2.4, 3.1, 3.8)
        )
        let cpu = (0..<96).map { 0.24 + sin(Double($0) * 0.22) * 0.11 }
        let memory = (0..<96).map { 0.57 + sin(Double($0) * 0.06) * 0.025 }
        let network = (0..<96).map { max(0.02, sin(Double($0) * 0.31) * 0.18 + 0.12) }
        let previewHour = Date()
        let hourly = previewHourlyForecast(from: previewHour)
        let daily = previewDailyForecast(from: previewHour)
        let weather = WeatherSnapshot(
            location: "LOCAL PREVIEW", condition: "PARTLY CLOUDY",
            temperature: 24, apparentTemperature: 25, humidity: 0.58,
            windSpeed: 12, precipitation: 0,
            temperatureForecast: [0.72, 0.68, 0.61, 0.55, 0.50, 0.45, 0.42, 0.40, 0.36, 0.34, 0.31, 0.29],
            precipitationForecast: [0.08, 0.05, 0.04, 0.03, 0.04, 0.08, 0.12, 0.09, 0.06, 0.04, 0.03, 0.02],
            hourlyForecast: hourly,
            dailyForecast: daily,
            status: "STATIC LAYOUT PREVIEW"
        )
        Group {
            switch scene {
            case .system:
                SystemScene(market: marketPreview, time: 10)
            case .radar:
                RadarScene(weather: weather, time: 10)
            case .signal:
                SignalScene(snapshot: telemetry, cpuHistory: cpu, memoryHistory: memory, networkHistory: network, time: 10)
            case .fullMetrics:
                FullMetricsScene(snapshot: telemetry, cpuHistory: cpu, memoryHistory: memory, networkHistory: network, time: 10)
            }
        }
        .frame(width: 960, height: 540)
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
                    let point = CGPoint(x: gesture.startLocation.x / scale, y: gesture.startLocation.y / scale)
                    let selectedFrame = layouts.frame(scene, selection)
                    let handle = CGRect(
                        x: selectedFrame.x + selectedFrame.width - 24 / scale,
                        y: selectedFrame.y + selectedFrame.height - 24 / scale,
                        width: 24 / scale,
                        height: 24 / scale
                    )
                    let resizing = !selection.isEmpty && handle.contains(point)
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
                let dx = gesture.translation.width / scale
                let dy = gesture.translation.height / scale
                if interactionKind == .resize {
                    updated.width += dx
                    updated.height += dy
                } else {
                    updated.x += dx
                    updated.y += dy
                }
                layouts.previewInteraction(scene, module: module, frame: updated)
            }
            .onEnded { _ in
                layouts.commitInteraction()
                clearInteraction()
            }
    }

    private func hitTest(_ point: CGPoint) -> String {
        LayoutDefaults.modules(for: scene)
            .filter { layouts.frame(scene, $0.id).rect.contains(point) }
            .min { lhs, rhs in
                let left = layouts.frame(scene, lhs.id)
                let right = layouts.frame(scene, rhs.id)
                return left.width * left.height < right.width * right.height
            }?.id ?? ""
    }

    private func clearInteraction() {
        interactionModule = nil
        interactionKind = nil
        interactionStart = nil
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
            Text("Drag changes save at mouse-up. Steppers save immediately.")
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
