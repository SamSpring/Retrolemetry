import AppKit
import SwiftUI
import Combine

private var mono: Font { consoleAuxiliaryFont(14, weight: .medium) }

enum SceneTransitionStyle: String, CaseIterable, Identifiable {
    case pan
    case wipe
    case syncRoll

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pan: "Pan"
        case .wipe: "Diagonal Wipe"
        case .syncRoll: "Sync Roll"
        }
    }

    var duration: Double {
        switch self {
        case .pan: 0.78
        case .wipe: 0.92
        case .syncRoll: 0.84
        }
    }
}

enum ConsoleScene: Int, CaseIterable {
    case system, radar, signal, fullMetrics

    var title: String {
        switch self {
        case .system: "MARKET WATCH"
        case .radar: "SECTOR SCAN"
        case .signal: "SIGNAL ANALYSIS"
        case .fullMetrics: "LIVE SYSTEM METRICS"
        }
    }
}

enum SceneOrder {
    static let defaultValue = "0,1,2,3"

    static func parse(_ value: String) -> [ConsoleScene] {
        var seen = Set<ConsoleScene>()
        var result = value
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .compactMap(ConsoleScene.init(rawValue:))
            .filter { seen.insert($0).inserted }
        for scene in ConsoleScene.allCases where seen.insert(scene).inserted {
            result.append(scene)
        }
        return result
    }

    static func encode(_ scenes: [ConsoleScene]) -> String {
        scenes.map { String($0.rawValue) }.joined(separator: ",")
    }
}

struct ConsoleView: View {
    @StateObject private var telemetry = TelemetryModel()
    @StateObject private var weather = WeatherModel()
    @StateObject private var market = MarketModel()
    @AppStorage("DockTelemetry.cycleDuration") private var cycleDuration = 30.0
    @AppStorage("DockTelemetry.automaticCycleEnabled") private var automaticCycleEnabled = true
    @AppStorage("DockTelemetry.sceneOrder") private var sceneOrderRaw = SceneOrder.defaultValue
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
    @ObservedObject private var layouts = LayoutStore.shared
    @State private var activeScene: ConsoleScene = .system
    @State private var previousScene: ConsoleScene?
    @State private var transitionProgress: CGFloat = 1
    @State private var transitionDirection = 1
    @State private var transitionGeneration = 0
    @State private var nextSwitch = Date().addingTimeInterval(24)
    private let sceneClock = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        let style = ConsoleStyle(rawValue: visualStyleRaw) ?? .phosphor
        ThemeRuntime.palette = style.palette
        FontRuntime.scale = layouts.fontScale
        FontRuntime.secondaryScale = layouts.secondaryFontScale
        FontRuntime.auxiliaryScale = layouts.auxiliaryFontScale
        return TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate

            ZStack {
                ConsoleBackground(style: style, phosphorTintStrength: phosphorBackgroundTint)
                transitioningScenes(time: elapsed)
                    .compositingGroup()
                    .shadow(
                        color: crtEnabled ? phosphor.opacity(0.24 * bloomStrength) : .clear,
                        radius: 2.5 + 3.5 * bloomStrength
                    )
                if crtEnabled {
                    CRTOverlay(
                        scanlineStrength: scanlineStrength,
                        noiseStrength: noiseStrength,
                        vhsTrackingEnabled: vhsTrackingEnabled,
                        trackingLine1Thickness: trackingLine1Thickness,
                        trackingLine2Thickness: trackingLine2Thickness,
                        time: elapsed
                    )
                }
                HorizontalScrollCapture { direction in
                    moveScene(direction)
                }
                .frame(width: 960, height: 540)
            }
            .frame(width: 960, height: 540)
            .foregroundStyle(phosphor)
            .font(mono)
            .clipped()
            .focusable()
            .onKeyPress { press in
                switch press.characters {
                case "1": select(.system)
                case "2": select(.radar)
                case "3": select(.signal)
                case "4": select(.fullMetrics)
                case "0", "a", "A":
                    if automaticCycleEnabled {
                        nextSwitch = Date().addingTimeInterval(cycleDuration)
                    }
                default: return .ignored
                }
                return .handled
            }
        }
        .onAppear {
            market.start()
            nextSwitch = Date().addingTimeInterval(cycleDuration)
        }
        .onDisappear { market.stop() }
        .onReceive(sceneClock) { now in
            guard automaticCycleEnabled, now >= nextSwitch else { return }
            let next = adjacentScene(from: activeScene, direction: 1)
            changeScene(to: next, direction: 1)
            nextSwitch = now.addingTimeInterval(cycleDuration)
        }
        .onChange(of: cycleDuration) {
            nextSwitch = Date().addingTimeInterval(cycleDuration)
        }
        .onChange(of: automaticCycleEnabled) {
            nextSwitch = Date().addingTimeInterval(cycleDuration)
        }
    }

    private func select(_ scene: ConsoleScene) {
        let order = SceneOrder.parse(sceneOrderRaw)
        let direction = (order.firstIndex(of: scene) ?? 0) >= (order.firstIndex(of: activeScene) ?? 0) ? 1 : -1
        changeScene(to: scene, direction: direction)
        nextSwitch = Date().addingTimeInterval(cycleDuration)
    }

    private func moveScene(_ direction: Int) {
        changeScene(to: adjacentScene(from: activeScene, direction: direction), direction: direction)
        nextSwitch = Date().addingTimeInterval(cycleDuration)
    }

    private func adjacentScene(from scene: ConsoleScene, direction: Int) -> ConsoleScene {
        let order = SceneOrder.parse(sceneOrderRaw)
        guard !order.isEmpty else { return .system }
        let current = order.firstIndex(of: scene) ?? 0
        let next = (current + (direction >= 0 ? 1 : -1) + order.count) % order.count
        return order[next]
    }

    private func changeScene(to scene: ConsoleScene, direction: Int) {
        guard scene != activeScene else { return }
        let style = SceneTransitionStyle(rawValue: transitionStyleRaw) ?? .pan
        transitionGeneration += 1
        let generation = transitionGeneration
        previousScene = activeScene
        activeScene = scene
        transitionDirection = direction >= 0 ? 1 : -1
        transitionProgress = 0

        DispatchQueue.main.async {
            withAnimation(.timingCurve(0.30, 0.02, 0.18, 1.0, duration: style.duration)) {
                transitionProgress = 1
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + style.duration + 0.08) {
            guard transitionGeneration == generation else { return }
            previousScene = nil
            transitionProgress = 1
        }
    }

    @ViewBuilder
    private func transitioningScenes(time: Double) -> some View {
        let style = SceneTransitionStyle(rawValue: transitionStyleRaw) ?? .pan
        ZStack {
            if let previousScene {
                transitionedScene(previousScene, time: time, incoming: false, style: style)
            }
            transitionedScene(activeScene, time: time, incoming: true, style: style)
            if previousScene != nil {
                transitionOverlay(style: style)
            }
        }
        .frame(width: 960, height: 540)
        .clipped()
    }

    @ViewBuilder
    private func transitionedScene(_ scene: ConsoleScene, time: Double, incoming: Bool, style: SceneTransitionStyle) -> some View {
        switch style {
        case .pan:
            sceneView(scene, time: time)
                .offset(x: incoming
                    ? CGFloat(transitionDirection) * 960 * (1 - transitionProgress)
                    : -CGFloat(transitionDirection) * 960 * transitionProgress)
        case .wipe:
            if incoming {
                sceneView(scene, time: time)
                    .mask(DiagonalWipeMask(progress: transitionProgress, direction: transitionDirection))
            } else {
                sceneView(scene, time: time)
            }
        case .syncRoll:
            sceneView(scene, time: time)
                .offset(
                    x: CGFloat(sin(Double(transitionProgress) * .pi * 8)) * (incoming ? 5 : -5),
                    y: incoming ? -540 * (1 - transitionProgress) : 540 * transitionProgress
                )
        }
    }

    @ViewBuilder
    private func transitionOverlay(style: SceneTransitionStyle) -> some View {
        switch style {
        case .pan:
            EmptyView()
        case .wipe:
            DiagonalWipeEdge(progress: transitionProgress, direction: transitionDirection)
                .foregroundStyle(phosphor)
        case .syncRoll:
            SyncRollBand(progress: transitionProgress)
        }
    }

    @ViewBuilder
    private func sceneView(_ scene: ConsoleScene, time: Double) -> some View {
        switch scene {
        case .system:
            SystemScene(market: market, time: time)
        case .radar:
            RadarScene(
                weather: weather.snapshot,
                time: time
            )
        case .signal:
            SignalScene(
                snapshot: telemetry.snapshot,
                cpuHistory: telemetry.cpuHistory,
                memoryHistory: telemetry.memoryHistory,
                networkHistory: telemetry.networkHistory,
                time: time
            )
        case .fullMetrics:
            FullMetricsScene(
                snapshot: telemetry.snapshot,
                cpuHistory: telemetry.cpuHistory,
                memoryHistory: telemetry.memoryHistory,
                networkHistory: telemetry.networkHistory,
                time: time
            )
        }
    }
}

private struct DiagonalWipeMask: Shape {
    var progress: CGFloat
    let direction: Int

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let slant: CGFloat = 94
        let top = progress * (rect.width + slant) - slant
        let bottom = progress * (rect.width + slant)
        var path = Path()
        if direction >= 0 {
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: min(rect.width, max(0, top)), y: 0))
            path.addLine(to: CGPoint(x: min(rect.width, max(0, bottom)), y: rect.height))
            path.addLine(to: CGPoint(x: 0, y: rect.height))
        } else {
            path.move(to: CGPoint(x: rect.width, y: 0))
            path.addLine(to: CGPoint(x: rect.width - min(rect.width, max(0, top)), y: 0))
            path.addLine(to: CGPoint(x: rect.width - min(rect.width, max(0, bottom)), y: rect.height))
            path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        }
        path.closeSubpath()
        return path
    }
}

private struct DiagonalWipeEdge: View {
    let progress: CGFloat
    let direction: Int

    var body: some View {
        Canvas { context, size in
            let slant: CGFloat = 94
            let top = progress * (size.width + slant) - slant
            let bottom = progress * (size.width + slant)
            let topX = direction >= 0 ? top : size.width - top
            let bottomX = direction >= 0 ? bottom : size.width - bottom
            guard max(topX, bottomX) >= -12, min(topX, bottomX) <= size.width + 12 else { return }
            var glow = Path()
            glow.move(to: CGPoint(x: topX, y: 0))
            glow.addLine(to: CGPoint(x: bottomX, y: size.height))
            context.stroke(glow, with: .color(phosphor.opacity(0.22)), lineWidth: 14)
            context.stroke(glow, with: .color(phosphor.opacity(0.95)), lineWidth: 2.2)
        }
        .allowsHitTesting(false)
    }
}

private struct SyncRollBand: View {
    let progress: CGFloat

    var body: some View {
        Canvas { context, size in
            let y = progress * (size.height + 90) - 45
            context.fill(
                Path(CGRect(x: 0, y: y - 28, width: size.width, height: 56)),
                with: .linearGradient(
                    Gradient(colors: [.clear, .black.opacity(0.82), phosphor.opacity(0.18), .black.opacity(0.72), .clear]),
                    startPoint: CGPoint(x: 0, y: y - 28),
                    endPoint: CGPoint(x: 0, y: y + 28)
                )
            )
            for index in 0..<18 {
                let start = CGFloat((index * 83 + Int(progress * 1000)) % 900)
                let length = CGFloat(22 + (index * 31) % 128)
                let offset = CGFloat(index % 7) - 3
                context.fill(
                    Path(CGRect(x: start, y: y + offset * 2.2, width: length, height: index.isMultiple(of: 4) ? 2 : 1)),
                    with: .color((index.isMultiple(of: 3) ? Color.white : phosphor).opacity(0.22))
                )
            }
            var edge = Path()
            edge.move(to: CGPoint(x: 0, y: y))
            edge.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(edge, with: .color(phosphor.opacity(0.92)), lineWidth: 2)
        }
        .allowsHitTesting(false)
    }
}

struct HorizontalScrollCapture: NSViewRepresentable {
    let onScroll: (Int) -> Void

    func makeNSView(context: Context) -> HorizontalScrollView {
        let view = HorizontalScrollView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: HorizontalScrollView, context: Context) {
        nsView.onScroll = onScroll
    }
}

final class HorizontalScrollView: NSView {
    var onScroll: ((Int) -> Void)?
    private var accumulated: CGFloat = 0
    private var lastSwitch = Date.distantPast

    override var acceptsFirstResponder: Bool { false }

    override func scrollWheel(with event: NSEvent) {
        let horizontal = event.scrollingDeltaX
        guard abs(horizontal) > 0.01 else {
            super.scrollWheel(with: event)
            return
        }

        accumulated += horizontal
        let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 34 : 1
        guard abs(accumulated) >= threshold,
              Date().timeIntervalSince(lastSwitch) > 0.45 else { return }

        let direction = accumulated < 0 ? 1 : -1
        accumulated = 0
        lastSwitch = Date()
        onScroll?(direction)
    }
}

struct FrameChrome: View {
    let title: String
    let section: String
    let time: Double
    @AppStorage("DockTelemetry.automaticCycleEnabled") private var automaticCycleEnabled = true

    var body: some View {
        ZStack {
            Rectangle().stroke(phosphor.opacity(0.72), lineWidth: 1)
                .padding(14)
            VStack(spacing: 0) {
                HStack {
                    Text("CG//DOCK NODE 01")
                    Spacer()
                    Text(title)
                    Spacer()
                    Text("LINK \(Int(time * 2).isMultiple(of: 2) ? "●" : "○") ACTIVE")
                }
                .font(consoleAuxiliaryFont(13, weight: .bold))
                .padding(.horizontal, 26)
                .frame(height: 42)
                Rectangle().fill(phosphor.opacity(0.6)).frame(height: 1).padding(.horizontal, 14)
                Spacer()
                HStack {
                    Text("MODE \(section)")
                    Spacer()
                    Text(automaticCycleEnabled
                         ? "AUTO CYCLE  //  1–4 SELECT  //  0 AUTO"
                         : "AUTO OFF  //  1–4 SELECT  //  H-SCROLL")
                }
                .font(consoleAuxiliaryFont(11, weight: .semibold))
                .padding(.horizontal, 26)
                .frame(height: 30)
            }
        }
        .allowsHitTesting(false)
    }
}

struct SystemScene: View {
    @ObservedObject var market: MarketModel
    let time: Double

    var body: some View {
        ZStack {
            FrameChrome(title: "MARKET WATCH", section: "MKT", time: time)
            LayoutModuleContainer(scene: .system, module: "globe") {
                WireGlobe(time: time)
            }
            LayoutModuleContainer(scene: .system, module: "marketFocus") {
                MarketFocusPanel(market: market, time: time)
            }
            LayoutModuleContainer(scene: .system, module: "marketClocks") {
                MarketWorldClocks(time: time)
            }
            LayoutModuleContainer(scene: .system, module: "marketTickerA") {
                MarketTickerList(market: market, startIndex: 0, title: "PORTFOLIO // A")
            }
            LayoutModuleContainer(scene: .system, module: "marketTickerB") {
                MarketTickerList(market: market, startIndex: 5, title: "PORTFOLIO // B")
            }
            LayoutModuleContainer(scene: .system, module: "fxGraph") {
                FXRatePanel(market: market)
            }
        }
    }

}

struct FullMetricsScene: View {
    let snapshot: TelemetrySnapshot
    let cpuHistory: [Double]
    let memoryHistory: [Double]
    let networkHistory: [Double]
    let time: Double

    var body: some View {
        ZStack {
            FrameChrome(title: "LIVE SYSTEM METRICS", section: "DAT", time: time)
            LayoutModuleContainer(scene: .fullMetrics, module: "metricCPU") { LargeMetricTile(label: "CPU LOAD", value: percent(snapshot.cpu), level: snapshot.cpu) }
            LayoutModuleContainer(scene: .fullMetrics, module: "metricMemory") { LargeMetricTile(label: "MEMORY", value: percent(snapshot.memory), level: snapshot.memory) }
            LayoutModuleContainer(scene: .fullMetrics, module: "metricDisk") { LargeMetricTile(label: "DISK USED", value: percent(snapshot.disk), level: snapshot.disk) }
            LayoutModuleContainer(scene: .fullMetrics, module: "metricNetwork") { LargeMetricTile(label: "NETWORK RX", value: byteRate(snapshot.networkIn), level: min(1, snapshot.networkIn / 12_000_000)) }
            LayoutModuleContainer(scene: .fullMetrics, module: "graphCPU") { LargeDataGraph(label: "CPU // 96 SEC", value: percent(snapshot.cpu), values: cpuHistory) }
            LayoutModuleContainer(scene: .fullMetrics, module: "graphMemory") { LargeDataGraph(label: "MEMORY // 96 SEC", value: percent(snapshot.memory), values: memoryHistory) }
            LayoutModuleContainer(scene: .fullMetrics, module: "graphNetwork") { LargeDataGraph(label: "NETWORK // 96 SEC", value: byteRate(snapshot.networkIn), values: networkHistory) }
            LayoutModuleContainer(scene: .fullMetrics, module: "statusUptime") { LargeStatusReadout(label: "UPTIME", value: snapshot.uptime.compactUptime) }
            LayoutModuleContainer(scene: .fullMetrics, module: "statusLoad") { LargeStatusReadout(label: "LOAD 1 / 5 / 15", value: String(format: "%.1f  %.1f  %.1f", snapshot.load.0, snapshot.load.1, snapshot.load.2)) }
            LayoutModuleContainer(scene: .fullMetrics, module: "statusTX") { LargeStatusReadout(label: "NETWORK TX", value: byteRate(snapshot.networkOut)) }
        }
    }

    private func percent(_ value: Double) -> String {
        String(format: "%03.0f%%", value * 100)
    }
}

struct LargeMetricTile: View {
    let label: String
    let value: String
    let level: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(consoleSecondaryFont(13, weight: .bold))
            Text(value)
                .font(consoleFont(value.count > 7 ? 23 : 31, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            HStack(spacing: 3) {
                ForEach(0..<12, id: \.self) { index in
                    Rectangle()
                        .fill(Double(index) / 12 < level ? phosphor : dimPhosphor)
                }
            }
            .frame(height: 13)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .overlay(Rectangle().stroke(dimPhosphor.opacity(0.95), lineWidth: 1.2))
    }
}

struct LargeDataGraph: View {
    let label: String
    let value: String
    let values: [Double]

    var body: some View {
        LineGraph(values: values)
            .overlay(alignment: .top) {
                HStack(spacing: 8) {
                    Text(label)
                        .font(consoleSecondaryFont(13, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                    Spacer(minLength: 4)
                    Text(value)
                        .font(consoleFont(18, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.60)
                }
                .padding(9)
            }
    }
}

struct LargeStatusReadout: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(consoleSecondaryFont(11, weight: .bold))
                .foregroundStyle(dimPhosphor)
            Text(value)
                .font(consoleFont(20, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .overlay(Rectangle().stroke(dimPhosphor.opacity(0.95), lineWidth: 1.2))
    }
}

struct SegmentedMeter: View {
    let label: String
    let value: Double
    let detail: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label).frame(width: 34, alignment: .leading)
            HStack(spacing: 3) {
                ForEach(0..<20, id: \.self) { index in
                    Rectangle()
                        .fill(Double(index) / 20 < value ? phosphor : dimPhosphor)
                        .frame(width: 17, height: 17)
                }
            }
            Text(detail).frame(width: 76, alignment: .trailing)
        }
        .font(consoleSecondaryFont(12, weight: .bold))
    }
}

struct Readout: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(consoleSecondaryFont(9)).foregroundStyle(dimPhosphor)
            Text(value).font(consoleFont(15, weight: .semibold))
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(Rectangle().stroke(dimPhosphor, lineWidth: 1))
    }
}

struct PulseIndicator: View {
    let label: String
    let active: Bool
    let time: Double

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(active && sin(time * 4) > -0.2 ? phosphor : dimPhosphor).frame(width: 7, height: 7)
            Text(label).font(consoleAuxiliaryFont(9))
        }
    }
}

struct LineGraph: View {
    let values: [Double]
    var body: some View {
        Canvas { context, size in
            drawGrid(context: &context, size: size, columns: 12, rows: 4)
            guard values.count > 1 else { return }
            var path = Path()
            for (index, value) in values.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
                let y = size.height - CGFloat(value) * (size.height - 12) - 6
                index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
            }
            context.stroke(path, with: .color(phosphor), lineWidth: 2.2)
        }
        .overlay(Rectangle().stroke(dimPhosphor, lineWidth: 1))
    }
}

struct WireGlobe: View {
    let time: Double
    @AppStorage("DockTelemetry.globeWidthCorrection") private var widthCorrection = 1.10
    @AppStorage("DockTelemetry.globeHeightCorrection") private var heightCorrection = 0.9254

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) * 0.41
            let rotation = time * 0.48
            context.stroke(
                Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                with: .color(phosphor),
                lineWidth: 1.4
            )
            for latitude in stride(from: -60.0, through: 60.0, by: 20) {
                let latitudeScale = CGFloat(cos(latitude * .pi / 180))
                let y = center.y + CGFloat(sin(latitude * .pi / 180)) * radius
                let rect = CGRect(
                    x: center.x - radius * latitudeScale,
                    y: y - radius * 0.10 * latitudeScale,
                    width: radius * 2 * latitudeScale,
                    height: radius * 0.20 * latitudeScale
                )
                context.stroke(Path(ellipseIn: rect), with: .color(dimPhosphor), lineWidth: 1)
            }
            for longitude in stride(from: 0.0, to: Double.pi, by: Double.pi / 8) {
                var front = Path()
                var back = Path()
                var frontStarted = false
                var backStarted = false
                for step in 0...72 {
                    let latitude = -Double.pi / 2 + Double(step) / 72 * Double.pi
                    let rotated = longitude + rotation
                    let x = cos(latitude) * sin(rotated)
                    let y = sin(latitude)
                    let z = cos(latitude) * cos(rotated)
                    let projected = CGPoint(x: center.x + CGFloat(x) * radius, y: center.y + CGFloat(y) * radius)
                    if z >= 0 {
                        frontStarted ? front.addLine(to: projected) : front.move(to: projected)
                        frontStarted = true
                        backStarted = false
                    } else {
                        backStarted ? back.addLine(to: projected) : back.move(to: projected)
                        backStarted = true
                        frontStarted = false
                    }
                }
                context.stroke(back, with: .color(dimPhosphor.opacity(0.34)), lineWidth: 0.7)
                context.stroke(front, with: .color(dimPhosphor.opacity(0.92)), lineWidth: 1.05)
            }
            let markerLongitude = rotation + 0.65
            let markerLatitude = 0.34
            let markerX = cos(markerLatitude) * sin(markerLongitude)
            let markerY = sin(markerLatitude)
            let markerZ = cos(markerLatitude) * cos(markerLongitude)
            let marker = CGPoint(x: center.x + CGFloat(markerX) * radius, y: center.y + CGFloat(markerY) * radius)
            context.fill(
                Path(ellipseIn: CGRect(x: marker.x - 3, y: marker.y - 3, width: 6, height: 6)),
                with: .color(phosphor.opacity(markerZ >= 0 ? 1 : 0))
            )
            var axis = Path()
            axis.move(to: CGPoint(x: center.x, y: center.y - radius - 9))
            axis.addLine(to: CGPoint(x: center.x, y: center.y + radius + 9))
            context.stroke(axis, with: .color(phosphor.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
        }
        .scaleEffect(x: widthCorrection, y: heightCorrection, anchor: .center)
    }
}

struct MarketFocusPanel: View {
    @ObservedObject var market: MarketModel
    let time: Double

    var body: some View {
        let symbol = activeSymbol
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("MARKET FEED // FINNHUB")
                Spacer()
                Text(market.state.label)
            }
            .font(consoleAuxiliaryFont(9, weight: .bold))
            .foregroundStyle(dimPhosphor)

            if let symbol, let quote = market.quotes[symbol] {
                HStack(alignment: .firstTextBaseline) {
                    Text(symbol)
                        .font(consoleSecondaryFont(17, weight: .bold))
                    Spacer()
                    Text(marketPrice(quote.price))
                        .font(consoleFont(28, weight: .bold))
                        .minimumScaleFactor(0.72)
                }
                HStack {
                    Text(String(format: "%+.2f  %+.2f%%", quote.change, quote.percentChange))
                        .font(consoleFont(13, weight: .bold))
                    Spacer()
                    Text("LAST \(marketTime(quote.tradeTime))")
                        .font(consoleAuxiliaryFont(8, weight: .bold))
                        .foregroundStyle(dimPhosphor)
                }
                MarketTrace(values: market.histories[symbol] ?? [], quote: quote)
                    .frame(maxHeight: .infinity)
                HStack {
                    Text("O \(marketPrice(quote.open))")
                    Spacer()
                    Text("L \(marketPrice(quote.low))")
                    Spacer()
                    Text("H \(marketPrice(quote.high))")
                }
                .font(consoleAuxiliaryFont(8, weight: .bold))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(market.state == .needsAPIKey ? "FINNHUB KEY REQUIRED" : "AWAITING QUOTE DATA")
                        .font(consoleSecondaryFont(15, weight: .bold))
                    Text(market.state == .needsAPIKey
                         ? "OPEN SETTINGS // LIVE MARKET DATA"
                         : "CONNECTING TO LIVE US MARKET FEED")
                        .font(consoleAuxiliaryFont(9, weight: .bold))
                        .foregroundStyle(dimPhosphor)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .padding(11)
        .overlay(Rectangle().stroke(dimPhosphor.opacity(0.95), lineWidth: 1.1))
    }

    private var activeSymbol: String? {
        guard !market.symbols.isEmpty else { return nil }
        return market.symbols[Int(time / 7) % market.symbols.count]
    }
}

struct MarketTrace: View {
    let values: [Double]
    let quote: MarketQuote

    var body: some View {
        Canvas { context, size in
            drawGrid(context: &context, size: size, columns: 6, rows: 3, strength: 0.48)
            let samples = values.count > 1 ? values : [quote.previousClose, quote.price]
            let low = min(samples.min() ?? quote.low, quote.low)
            let high = max(samples.max() ?? quote.high, quote.high)
            let span = max(0.0001, high - low)
            var path = Path()
            for (index, value) in samples.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(max(1, samples.count - 1))
                let normalized = (value - low) / span
                let y = size.height - 7 - CGFloat(normalized) * max(1, size.height - 14)
                index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
            }
            context.stroke(path, with: .color(phosphor), lineWidth: 1.8)
        }
    }
}

struct MarketWorldClocks: View {
    let time: Double
    @AppStorage("DockTelemetry.marketClock1") private var clock1 = "America/New_York"
    @AppStorage("DockTelemetry.marketClock2") private var clock2 = "America/Los_Angeles"
    @AppStorage("DockTelemetry.marketClock3") private var clock3 = "Europe/London"

    var body: some View {
        HStack(spacing: 10) {
            clock(clock1)
            clock(clock2)
            clock(clock3)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(Rectangle().stroke(dimPhosphor.opacity(0.95), lineWidth: 1.1))
    }

    private func clock(_ identifier: String) -> some View {
        let option = MarketClockZone.option(for: identifier)
        let date = Date(timeIntervalSinceReferenceDate: time)
        return VStack(spacing: 3) {
            Text(option.shortTitle)
                .font(consoleAuxiliaryFont(8, weight: .bold))
                .foregroundStyle(dimPhosphor)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(clockTime(date, identifier: option.id))
                .font(consoleSecondaryFont(14, weight: .bold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}

struct MarketTickerList: View {
    @ObservedObject var market: MarketModel
    let startIndex: Int
    let title: String

    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Text(title)
                Spacer()
                Text("LAST").frame(width: 58, alignment: .trailing)
                Text("CHANGE").frame(width: 56, alignment: .trailing)
            }
            .font(consoleAuxiliaryFont(9, weight: .bold))
            .foregroundStyle(dimPhosphor)
            Rectangle().fill(dimPhosphor.opacity(0.65)).frame(height: 1)
            ForEach(0..<5, id: \.self) { row in
                let index = startIndex + row
                let symbol = index < market.symbols.count ? market.symbols[index] : nil
                HStack(spacing: 5) {
                    Circle()
                        .fill(symbol.flatMap { market.quotes[$0] } == nil ? dimPhosphor : phosphor)
                        .frame(width: 6, height: 6)
                    Text(symbol ?? "AVAILABLE")
                        .foregroundStyle(symbol == nil ? dimPhosphor : phosphor)
                        .frame(width: 66, alignment: .leading)
                    Spacer()
                    if let symbol, let quote = market.quotes[symbol] {
                        Text(marketPrice(quote.price)).frame(width: 58, alignment: .trailing)
                        Text(String(format: "%+.2f%%", quote.percentChange)).frame(width: 56, alignment: .trailing)
                    } else {
                        Text("--").frame(width: 119, alignment: .trailing)
                    }
                }
                .font(consoleAuxiliaryFont(9, weight: .bold))
                .frame(maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(Rectangle().stroke(dimPhosphor.opacity(0.95), lineWidth: 1.1))
    }
}

struct FXRatePanel: View {
    @ObservedObject var market: MarketModel

    var body: some View {
        let points = market.usdIlsHistory
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("USD→ILS // DAILY REF")
                    .font(consoleAuxiliaryFont(9, weight: .bold))
                    .foregroundStyle(dimPhosphor)
                Spacer()
                if let latest = points.last {
                    Text(String(format: "%.4f", latest.rate))
                        .font(consoleSecondaryFont(14, weight: .bold))
                } else {
                    Text("LOADING")
                        .font(consoleAuxiliaryFont(9, weight: .bold))
                }
            }
            Canvas { context, size in
                drawGrid(context: &context, size: size, columns: 6, rows: 3, strength: 0.35)
                guard points.count > 1 else { return }
                let values = points.map(\.rate)
                let low = values.min() ?? 0
                let high = values.max() ?? 1
                let span = max(0.0001, high - low)
                var path = Path()
                for (index, point) in points.enumerated() {
                    let x = size.width * CGFloat(index) / CGFloat(points.count - 1)
                    let y = size.height - 5 - CGFloat((point.rate - low) / span) * max(1, size.height - 10)
                    index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
                }
                context.stroke(path, with: .color(phosphor), lineWidth: 1.6)
            }
            .frame(maxHeight: .infinity)
            if let first = points.first, let last = points.last {
                HStack {
                    Text("24 SESSIONS")
                    Spacer()
                    Text(String(format: "%+.2f%%", ((last.rate / first.rate) - 1) * 100))
                }
                .font(consoleAuxiliaryFont(8, weight: .bold))
                .foregroundStyle(dimPhosphor)
            }
        }
        .padding(8)
        .overlay(Rectangle().stroke(dimPhosphor.opacity(0.95), lineWidth: 1.1))
    }
}

private func marketPrice(_ value: Double) -> String {
    value < 1 ? String(format: "%.3f", value) : String(format: "%.2f", value)
}

private func marketTime(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .standard)
}

private func clockTime(_ date: Date, identifier: String) -> String {
    var style = Date.FormatStyle(date: .omitted, time: .shortened)
    style.timeZone = TimeZone(identifier: identifier) ?? .gmt
    return date.formatted(style)
}

struct RadarScene: View {
    let weather: WeatherSnapshot
    let time: Double
    @AppStorage("DockTelemetry.weatherForecastDays") private var weatherForecastDays = 5
    @AppStorage("DockTelemetry.radarWidthCorrection") private var radarWidthCorrection = 1.10
    @AppStorage("DockTelemetry.radarHeightCorrection") private var radarHeightCorrection = 0.9254
    var body: some View {
        ZStack {
            FrameChrome(title: "LOCAL WEATHER RADAR", section: "WX", time: time)
            LayoutModuleContainer(scene: .radar, module: "radar") {
              Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) * 0.47
                for ring in 1...4 {
                    let r = radius * CGFloat(ring) / 4
                    context.stroke(Path(ellipseIn: CGRect(x: center.x-r, y: center.y-r, width: r*2, height: r*2)), with: .color(dimPhosphor.opacity(0.82)), lineWidth: 1.1)
                }
                for angle in stride(from: 0.0, to: 360.0, by: 30) {
                    let p = point(center: center, radius: radius, angle: angle)
                    var line = Path(); line.move(to: center); line.addLine(to: p)
                    context.stroke(line, with: .color(dimPhosphor.opacity(0.82)), lineWidth: 1.1)
                }
                let sweep = time * 42
                for trail in 0..<16 {
                    let angle = sweep - Double(trail) * 2.3
                    var line = Path(); line.move(to: center); line.addLine(to: point(center: center, radius: radius, angle: angle))
                    context.stroke(line, with: .color(phosphor.opacity(0.75 * (1 - Double(trail)/16))), lineWidth: 2)
                }
                for index in 0..<7 {
                    let angle = Double(index * 53) + sin(time * 0.15 + Double(index)) * 15
                    let r = radius * (0.25 + Double((index * 37) % 65) / 100)
                    let p = point(center: center, radius: r, angle: angle)
                    context.fill(Path(ellipseIn: CGRect(x: p.x-3, y: p.y-3, width: 6, height: 6)), with: .color(phosphor))
                }
              }
              .scaleEffect(x: radarWidthCorrection, y: radarHeightCorrection, anchor: .center)
            }
            LayoutModuleContainer(scene: .radar, module: "weatherHeader") {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(weather.location)
                            .font(consoleSecondaryFont(11, weight: .bold))
                            .foregroundStyle(dimPhosphor)
                        Text(weather.condition)
                            .font(consoleFont(18, weight: .bold))
                    }
                    Spacer()
                    Text(String(format: "%.0f°C", weather.temperature))
                        .font(consoleFont(40, weight: .bold))
                }
            }
            LayoutModuleContainer(scene: .radar, module: "weatherStats") {
                HStack(spacing: 8) {
                    WeatherReadout(label: "FEELS", value: String(format: "%.0f°C", weather.apparentTemperature))
                    WeatherReadout(label: "HUMID", value: String(format: "%.0f%%", weather.humidity * 100))
                    WeatherReadout(label: "WIND", value: String(format: "%.0f KM/H", weather.windSpeed))
                    WeatherReadout(label: "RAIN", value: String(format: "%.1f MM", weather.precipitation))
                }
            }
            LayoutModuleContainer(scene: .radar, module: "temperature") {
                HourlyForecastPanel(weather: weather)
            }
            LayoutModuleContainer(scene: .radar, module: "precipitation") {
                DailyForecastPanel(days: Array(weather.dailyForecast.prefix(weatherForecastDays)))
            }
            LayoutModuleContainer(scene: .radar, module: "weatherStatus") {
                HStack {
                    Text(weather.status)
                    Spacer()
                    Text("RADAR SWEEP 042°/S")
                }
                .font(consoleAuxiliaryFont(10, weight: .bold))
            }
        }
    }
}

struct WeatherReadout: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(consoleSecondaryFont(10, weight: .bold))
                .foregroundStyle(dimPhosphor)
            Text(value)
                .font(consoleFont(15, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .overlay(Rectangle().stroke(dimPhosphor.opacity(0.9), lineWidth: 1))
    }
}

struct HourlyForecastPanel: View {
    let weather: WeatherSnapshot

    var body: some View {
        let points = weather.hourlyForecast
        Canvas { context, size in
            drawGrid(context: &context, size: size, columns: 6, rows: 3, strength: 0.42)
            guard points.count > 1 else { return }
            let temperatures = points.map(\.temperature)
            let low = temperatures.min() ?? 0
            let high = temperatures.max() ?? 1
            let span = max(2, high - low)
            var temperaturePath = Path()
            for (index, point) in points.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(points.count - 1)
                let normalized = (point.temperature - low) / span
                let y = 19 + (size.height - 36) * (1 - CGFloat(normalized))
                index == 0 ? temperaturePath.move(to: CGPoint(x: x, y: y)) : temperaturePath.addLine(to: CGPoint(x: x, y: y))
                let rainHeight = CGFloat(point.precipitationChance) * min(24, size.height * 0.28)
                let bar = CGRect(x: max(0, x - 2), y: size.height - 13 - rainHeight, width: 4, height: rainHeight)
                context.fill(Path(bar), with: .color(dimPhosphor.opacity(0.85)))
            }
            context.stroke(temperaturePath, with: .color(phosphor), lineWidth: 1.7)
        }
        .overlay(Rectangle().stroke(dimPhosphor.opacity(0.9), lineWidth: 1.2))
        .overlay(alignment: .top) {
            HStack {
                Text("HOURLY // NEXT 12")
                Spacer()
                if let first = points.first, let last = points.last {
                    Text(String(format: "%.0f° → %.0f°", first.temperature, last.temperature))
                }
            }
            .font(consoleSecondaryFont(9, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.top, 5)
        }
        .overlay(alignment: .bottom) {
            HStack {
                ForEach(hourMarkers, id: \.time) { point in
                    Text(hourLabel(point.time))
                    if point.time != hourMarkers.last?.time { Spacer() }
                }
            }
            .font(consoleAuxiliaryFont(7, weight: .bold))
            .foregroundStyle(dimPhosphor)
            .padding(.horizontal, 6)
            .padding(.bottom, 3)
        }
    }

    private var hourMarkers: [HourlyWeatherPoint] {
        let points = weather.hourlyForecast
        guard !points.isEmpty else { return [] }
        return stride(from: 0, to: points.count, by: 3).map { points[$0] }
    }
}

struct DailyForecastPanel: View {
    let days: [DailyWeatherPoint]

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text("DAILY OUTLOOK // \(days.count) DAYS")
                Spacer()
                Text("LOW  HIGH  RAIN")
            }
            .font(consoleSecondaryFont(9, weight: .bold))
            .foregroundStyle(dimPhosphor)
            .padding(.bottom, 2)

            if days.isEmpty {
                Text("AWAITING DAILY FORECAST")
                    .font(consoleAuxiliaryFont(9, weight: .bold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    HStack(spacing: 6) {
                        Text(index == 0 ? "TODAY" : dayLabel(day.date))
                            .frame(width: 45, alignment: .leading)
                        Text(day.condition)
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                        Spacer(minLength: 3)
                        Text(String(format: "%3.0f°", day.low)).frame(width: 30, alignment: .trailing)
                        Text(String(format: "%3.0f°", day.high)).frame(width: 30, alignment: .trailing)
                        HStack(spacing: 2) {
                            ForEach(0..<5, id: \.self) { segment in
                                Rectangle()
                                    .fill(Double(segment) / 5 < day.precipitationChance ? phosphor : dimPhosphor)
                                    .frame(width: 7, height: 7)
                            }
                        }
                        Text(String(format: "%2.0f", day.precipitationChance * 100))
                            .frame(width: 23, alignment: .trailing)
                    }
                    .font(consoleAuxiliaryFont(8.5, weight: .bold))
                    .frame(maxHeight: .infinity)
                    if index < days.count - 1 {
                        Rectangle().fill(dimPhosphor.opacity(0.35)).frame(height: 0.5)
                    }
                }
            }
        }
        .padding(7)
        .overlay(Rectangle().stroke(dimPhosphor.opacity(0.9), lineWidth: 1.2))
    }
}

private func hourLabel(_ date: Date) -> String {
    date.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)))
}

private func dayLabel(_ date: Date) -> String {
    date.formatted(.dateTime.weekday(.abbreviated)).uppercased()
}

struct SignalScene: View {
    let snapshot: TelemetrySnapshot
    let cpuHistory: [Double]
    let memoryHistory: [Double]
    let networkHistory: [Double]
    let time: Double
    @AppStorage("DockTelemetry.signalSynthwaveGrid") private var synthwaveGrid = false
    var body: some View {
        ZStack {
            FrameChrome(title: "SIGNAL ANALYSIS", section: "SIG", time: time)
            LayoutModuleContainer(scene: .signal, module: "scope") {
              Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size)
                context.stroke(Path(rect), with: .color(dimPhosphor), lineWidth: 1)
                if synthwaveGrid {
                    drawSynthwaveGrid(
                        context: &context,
                        rect: rect,
                        time: time,
                        cpuLoad: snapshot.cpu
                    )
                } else {
                    drawGrid(context: &context, size: rect.size, columns: 16, rows: 8, origin: rect.origin, strength: 0.72)
                }
                let amplitude = 108 + sin(time * 0.19) * 7
                let frequencyA = 3.04
                let frequencyB = 4.07
                let continuousPhase = sin(time * 0.16) * 0.72
                for echo in stride(from: 3, through: 0, by: -1) {
                    var path = Path()
                    let lag = Double(echo) * 0.025
                    for i in 0...360 {
                        let t = Double(i) / 360 * Double.pi * 2
                        let x = rect.midX + CGFloat(sin(t * frequencyA + time * 0.82 - lag)) * amplitude * 2.05
                        let y = rect.midY + CGFloat(sin(t * frequencyB + time * 0.61 + continuousPhase - lag)) * amplitude
                        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
                    }
                    let opacity = echo == 0 ? 1.0 : 0.11 + Double(3 - echo) * 0.075
                    context.stroke(path, with: .color(phosphor.opacity(opacity)), lineWidth: echo == 0 ? 1.5 : 0.8)
                }
              }
            }
            LayoutModuleContainer(scene: .signal, module: "signalHeader") {
                HStack {
                    Text(String(format: "CH A  CPU %03.0f%%", snapshot.cpu * 100))
                    Spacer()
                    Text(String(format: "CH B  MEM %03.0f%%", snapshot.memory * 100))
                    Spacer()
                    Text("PHASE \(Int(time*22)%360)°")
                }
                .font(consoleAuxiliaryFont(13, weight: .bold))
            }
            LayoutModuleContainer(scene: .signal, module: "cpuTrace") { MiniTrace(label: "CPU", values: cpuHistory) }
            LayoutModuleContainer(scene: .signal, module: "memoryTrace") { MiniTrace(label: "MEMORY", values: memoryHistory) }
            LayoutModuleContainer(scene: .signal, module: "networkTrace") { MiniTrace(label: "NETWORK", values: networkHistory) }
            LayoutModuleContainer(scene: .signal, module: "ioReadout") { Readout(label: "I/O RX / TX", value: "\(byteRate(snapshot.networkIn)) / \(byteRate(snapshot.networkOut))") }
        }
    }
}

private func drawSynthwaveGrid(
    context: inout GraphicsContext,
    rect: CGRect,
    time: Double,
    cpuLoad: Double
) {
    let horizon = rect.minY + rect.height * 0.34
    let bottom = rect.maxY
    let centerX = rect.midX
    let travel = time * (0.32 + min(1, max(0, cpuLoad)) * 1.9)

    for index in -12...12 {
        let bottomX = centerX + CGFloat(index) * rect.width / 13
        var path = Path()
        for step in 0...48 {
            let depth = CGFloat(step) / 48
            let perspective = pow(depth, 1.72)
            let wave = sin(Double(depth) * 10 + travel * 1.35 + Double(index) * 0.42)
            let x = centerX + (bottomX - centerX) * perspective + CGFloat(wave) * 5 * depth
            let y = horizon + (bottom - horizon) * perspective
            step == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
        }
        context.stroke(path, with: .color(dimPhosphor.opacity(0.86)), lineWidth: 1)
    }

    for row in 0..<18 {
        let phase = (Double(row) / 18 + travel * 0.095).truncatingRemainder(dividingBy: 1)
        let depth = CGFloat(phase)
        let perspective = pow(depth, 2.12)
        let yBase = horizon + (bottom - horizon) * perspective
        var path = Path()
        for step in 0...72 {
            let xProgress = CGFloat(step) / 72
            let x = rect.minX + rect.width * xProgress
            let wave = sin(Double(xProgress) * .pi * 4 + travel * 1.6 + Double(row) * 0.33)
            let y = yBase + CGFloat(wave) * (2 + 9 * perspective)
            step == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
        }
        context.stroke(path, with: .color(phosphor.opacity(0.38 + Double(perspective) * 0.46)), lineWidth: 0.8 + perspective * 0.8)
    }

    var horizonPath = Path()
    horizonPath.move(to: CGPoint(x: rect.minX, y: horizon))
    horizonPath.addLine(to: CGPoint(x: rect.maxX, y: horizon))
    context.stroke(horizonPath, with: .color(phosphor.opacity(0.78)), lineWidth: 1.2)
}

struct CompactMeter: View {
    let label: String
    let value: Double

    var body: some View {
        HStack(spacing: 5) {
            Text(label).frame(width: 38, alignment: .leading)
            HStack(spacing: 2) {
                ForEach(0..<10, id: \.self) { index in
                    Rectangle()
                        .fill(Double(index) / 10 < value ? phosphor : dimPhosphor)
                        .frame(height: 12)
                }
            }
            Text(String(format: "%02.0f", value * 100)).frame(width: 30, alignment: .trailing)
        }
        .font(consoleAuxiliaryFont(12, weight: .bold))
    }
}

struct MiniTrace: View {
    let label: String
    let values: [Double]

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            var path = Path()
            for (index, value) in values.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
                let y = size.height - CGFloat(value) * (size.height - 14) - 3
                index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
            }
            context.stroke(path, with: .color(phosphor), lineWidth: 1.5)
        }
        .overlay(Rectangle().stroke(dimPhosphor.opacity(0.9), lineWidth: 1.2))
        .overlay(alignment: .topLeading) {
            Text(label)
                .font(consoleSecondaryFont(11, weight: .bold))
                .padding(6)
        }
    }
}

struct CRTOverlay: View {
    let scanlineStrength: Double
    let noiseStrength: Double
    let vhsTrackingEnabled: Bool
    let trackingLine1Thickness: Double
    let trackingLine2Thickness: Double
    let time: Double

    var body: some View {
        ZStack {
            Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                if scanlineStrength > 0.001 {
                    let darkOpacity = 0.12 + scanlineStrength * 0.60
                    let highlightOpacity = 0.025 + scanlineStrength * 0.14
                    for y in stride(from: 1.0, through: size.height, by: 4) {
                        var darkLine = Path()
                        darkLine.move(to: CGPoint(x: 0, y: y))
                        darkLine.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(darkLine, with: .color(.black.opacity(darkOpacity)), lineWidth: 1.15)

                        var highlight = Path()
                        highlight.move(to: CGPoint(x: 0, y: y + 1.35))
                        highlight.addLine(to: CGPoint(x: size.width, y: y + 1.35))
                        context.stroke(highlight, with: .color(phosphor.opacity(highlightOpacity)), lineWidth: 0.55)
                    }
                }

                if noiseStrength > 0.001 {
                    let frame = Int(time * 14)
                    let grainOpacity = 0.035 + noiseStrength * 0.26
                    for index in 0..<820 {
                        let hash = (index &* 73_856_093) ^ (frame &* 19_349_663)
                        let positive = hash & 0x7fff_ffff
                        let x = CGFloat((positive &* 37) % 960)
                        let y = CGFloat((positive &* 91 + index &* 17) % 540)
                        let width: CGFloat = index.isMultiple(of: 7) ? 2.5 : 1
                        context.fill(
                            Path(CGRect(x: x, y: y, width: width, height: 1)),
                            with: .color((index.isMultiple(of: 5) ? Color.white : phosphor).opacity(grainOpacity))
                        )
                    }
                }

                if vhsTrackingEnabled {
                    let firstTravel = (time * 72).truncatingRemainder(dividingBy: size.height + 100)
                    drawTrackingBand(
                        context: &context,
                        size: size,
                        y: CGFloat(firstTravel) - 50,
                        thickness: trackingLine1Thickness,
                        strength: 0.78,
                        segmentFrame: Int(time * 9)
                    )

                    let secondTravel = (time * 43 + Double(size.height) * 0.53)
                        .truncatingRemainder(dividingBy: Double(size.height) + 150)
                    drawTrackingBand(
                        context: &context,
                        size: size,
                        y: CGFloat(secondTravel) - 75,
                        thickness: trackingLine2Thickness,
                        strength: 1.0,
                        segmentFrame: Int(time * 6) + 117
                    )
                }
            }
            RadialGradient(
                colors: [.clear, .clear, .black.opacity(0.30)],
                center: .center,
                startRadius: 180,
                endRadius: 590
            )
        }
        .allowsHitTesting(false)
    }
}

private func drawTrackingBand(
    context: inout GraphicsContext,
    size: CGSize,
    y: CGFloat,
    thickness: Double,
    strength: Double,
    segmentFrame: Int
) {
    let lineWidth = max(0.5, CGFloat(thickness))
    let bandHeight = max(18, lineWidth * 4.2)
    let band = CGRect(x: 0, y: y - bandHeight / 2, width: size.width, height: bandHeight)
    context.fill(
        Path(band),
        with: .linearGradient(
            Gradient(colors: [
                .clear,
                .black.opacity(0.12 * strength),
                phosphor.opacity(0.075 * strength),
                .clear
            ]),
            startPoint: CGPoint(x: 0, y: band.minY),
            endPoint: CGPoint(x: 0, y: band.maxY)
        )
    )

    var edge = Path()
    edge.move(to: CGPoint(x: 0, y: y))
    edge.addLine(to: CGPoint(x: size.width, y: y))
    context.stroke(edge, with: .color(phosphor.opacity(0.34 * strength)), lineWidth: lineWidth)

    for index in 0..<13 {
        let start = CGFloat((index * 137 + segmentFrame * 29) % 900)
        let length = CGFloat(18 + (index * 23) % 96)
        let offset = CGFloat((index % 5) - 2) * max(2.5, lineWidth * 0.65)
        context.fill(
            Path(CGRect(x: start, y: y + offset, width: length, height: max(1, lineWidth * 0.22))),
            with: .color(Color.white.opacity((0.10 + Double(index % 3) * 0.035) * strength))
        )
    }
}

private func drawGrid(
    context: inout GraphicsContext,
    size: CGSize,
    columns: Int,
    rows: Int,
    origin: CGPoint = .zero,
    strength: Double = 0.62
) {
    for column in 0...columns {
        let x = origin.x + size.width * CGFloat(column) / CGFloat(columns)
        var path = Path(); path.move(to: CGPoint(x: x, y: origin.y)); path.addLine(to: CGPoint(x: x, y: origin.y + size.height))
        context.stroke(path, with: .color(dimPhosphor.opacity(strength)), lineWidth: 0.8)
    }
    for row in 0...rows {
        let y = origin.y + size.height * CGFloat(row) / CGFloat(rows)
        var path = Path(); path.move(to: CGPoint(x: origin.x, y: y)); path.addLine(to: CGPoint(x: origin.x + size.width, y: y))
        context.stroke(path, with: .color(dimPhosphor.opacity(strength)), lineWidth: 0.8)
    }
}

private func point(center: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
    let radians = angle * .pi / 180
    return CGPoint(x: center.x + CGFloat(cos(radians)) * radius, y: center.y + CGFloat(sin(radians)) * radius)
}
