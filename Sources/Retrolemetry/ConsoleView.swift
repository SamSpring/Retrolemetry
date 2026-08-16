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

enum SignalGridMetric: String, CaseIterable, Identifiable {
    case cpu, gpuProxy, network, disk

    var id: String { rawValue }
    var title: String {
        switch self {
        case .cpu: "CPU"
        case .gpuProxy: "GPU / SYSTEM LOAD"
        case .network: "NETWORK"
        case .disk: "DISK USED"
        }
    }
    var shortTitle: String {
        switch self {
        case .cpu: "CPU"
        case .gpuProxy: "LOAD"
        case .network: "NET"
        case .disk: "DSK"
        }
    }
}

enum SignalGridPattern: String, CaseIterable, Identifiable {
    case recede, terrainPulse, signalSweep

    var id: String { rawValue }
    var title: String {
        switch self {
        case .recede: "Recede"
        case .terrainPulse: "Terrain Pulse"
        case .signalSweep: "Signal Sweep"
        }
    }
}

enum SignalGridResponse: String, CaseIterable, Identifiable {
    case low, medium, high

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
    var multiplier: Double {
        switch self {
        case .low: 0.55
        case .medium: 1.0
        case .high: 1.65
        }
    }
    var smoothingRate: Double {
        switch self {
        case .low: 0.8
        case .medium: 2.0
        case .high: 5.0
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
    @AppStorage("DockTelemetry.radarTargetMode") private var radarTargetModeRaw = RadarTargetMode.precipitation.rawValue
    @ObservedObject private var layouts = LayoutStore.shared
    @State private var activeScene: ConsoleScene = .system
    @State private var previousScene: ConsoleScene?
    @State private var transitionProgress: CGFloat = 1
    @State private var transitionDirection = 1
    @State private var transitionGeneration = 0
    @State private var nextSwitch = Date().addingTimeInterval(24)
    @State private var marketTimeframe: MarketTimeframe = .today
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
                } onClick: { point in
                    switch activeScene {
                    case .system:
                        let focus = layouts.frame(.system, "marketFocus")
                        guard focus.visible, focus.rect.contains(point) else { return }
                        marketTimeframe = marketTimeframe.next
                    case .radar:
                        let radar = layouts.frame(.radar, "radar")
                        guard radar.visible, radar.rect.contains(point) else { return }
                        let current = RadarTargetMode(rawValue: radarTargetModeRaw) ?? .precipitation
                        radarTargetModeRaw = current.next.rawValue
                    case .signal, .fullMetrics:
                        return
                    }
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
                .background(Color.black)
                .offset(x: incoming
                    ? CGFloat(transitionDirection) * 960 * (1 - transitionProgress)
                    : -CGFloat(transitionDirection) * 960 * transitionProgress)
        case .wipe:
            if incoming {
                sceneView(scene, time: time)
                    .background(Color.black)
                    .mask(DiagonalWipeMask(progress: transitionProgress, direction: transitionDirection))
            } else {
                sceneView(scene, time: time)
                    .background(Color.black)
            }
        case .syncRoll:
            let halfProgress = incoming
                ? max(0, min(1, (transitionProgress - 0.48) / 0.52))
                : max(0, min(1, transitionProgress / 0.52))
            let verticalScale = incoming
                ? max(0.018, halfProgress)
                : max(0.018, 1 - halfProgress)
            sceneView(scene, time: time)
                .background(Color.black)
                .scaleEffect(x: 1 + (1 - verticalScale) * 0.018, y: verticalScale, anchor: .center)
                .offset(x: CGFloat(sin(Double(transitionProgress) * .pi * 15)) * (1 - verticalScale) * 11)
                .opacity(incoming ? (transitionProgress >= 0.48 ? 1 : 0) : (transitionProgress < 0.52 ? 1 : 0))
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
            SystemScene(market: market, time: time, timeframe: marketTimeframe)
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
            let y = size.height / 2
            let intensity = max(0, 1 - abs(progress - 0.5) * 2)
            let bandHeight = 8 + intensity * 48
            context.fill(
                Path(CGRect(x: 0, y: y - bandHeight / 2, width: size.width, height: bandHeight)),
                with: .linearGradient(
                    Gradient(colors: [.clear, .black.opacity(0.82), phosphor.opacity(0.18), .black.opacity(0.72), .clear]),
                    startPoint: CGPoint(x: 0, y: y - bandHeight / 2),
                    endPoint: CGPoint(x: 0, y: y + bandHeight / 2)
                )
            )
            for index in 0..<14 {
                let start = CGFloat((index * 83 + Int(progress * 720)) % 900)
                let length = CGFloat(22 + (index * 31) % 128)
                let offset = CGFloat(index % 7) - 3
                context.fill(
                    Path(CGRect(x: start, y: y + offset * 3.1, width: length, height: index.isMultiple(of: 4) ? 2 : 1)),
                    with: .color((index.isMultiple(of: 3) ? Color.white : phosphor).opacity(0.10 + intensity * 0.34))
                )
            }
            var edge = Path()
            edge.move(to: CGPoint(x: 0, y: y))
            edge.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(edge, with: .color(phosphor.opacity(0.18 + intensity * 0.82)), lineWidth: 1.5 + intensity * 2.5)
        }
        .allowsHitTesting(false)
    }
}

struct HorizontalScrollCapture: NSViewRepresentable {
    let onScroll: (Int) -> Void
    let onClick: (CGPoint) -> Void

    func makeNSView(context: Context) -> HorizontalScrollView {
        let view = HorizontalScrollView()
        view.onScroll = onScroll
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: HorizontalScrollView, context: Context) {
        nsView.onScroll = onScroll
        nsView.onClick = onClick
    }
}

final class HorizontalScrollView: NSView {
    var onScroll: ((Int) -> Void)?
    var onClick: ((CGPoint) -> Void)?
    private var accumulated: CGFloat = 0
    private var gestureTriggered = false
    private var lastDirectEvent = Date.distantPast
    private let preciseThreshold: CGFloat = 26
    private let gestureIdleTimeout: TimeInterval = 0.18

    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let point = CGPoint(x: local.x, y: isFlipped ? local.y : bounds.height - local.y)
        onClick?(point)
    }

    override func scrollWheel(with event: NSEvent) {
        let now = Date()

        // Trackpad and Magic Mouse momentum often reverses slightly while settling. Treat
        // momentum as part of the completed gesture instead of allowing it to change scenes.
        guard event.momentumPhase.isEmpty else { return }

        if event.phase.contains(.began) || event.phase.contains(.mayBegin) ||
            (event.phase.isEmpty && now.timeIntervalSince(lastDirectEvent) > gestureIdleTimeout) {
            resetScrollGesture()
        }
        if event.phase.contains(.cancelled) {
            resetScrollGesture()
            return
        }
        lastDirectEvent = now

        let horizontal = event.scrollingDeltaX
        let vertical = event.scrollingDeltaY
        guard abs(horizontal) > 0.01, abs(horizontal) >= abs(vertical) * 0.72 else {
            if event.phase.contains(.ended) { resetScrollGesture() }
            super.scrollWheel(with: event)
            return
        }

        guard !gestureTriggered else {
            if event.phase.contains(.ended) { resetScrollGesture() }
            return
        }

        accumulated += horizontal
        let threshold = event.hasPreciseScrollingDeltas ? preciseThreshold : 1
        guard abs(accumulated) >= threshold else {
            if event.phase.contains(.ended) { resetScrollGesture() }
            return
        }

        let direction = accumulated < 0 ? 1 : -1
        gestureTriggered = true
        onScroll?(direction)

        if event.phase.contains(.ended) { resetScrollGesture() }
    }

    private func resetScrollGesture() {
        accumulated = 0
        gestureTriggered = false
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
    var timeframe: MarketTimeframe = .today

    var body: some View {
        ZStack {
            FrameChrome(title: "MARKET WATCH", section: "MKT", time: time)
            LayoutModuleContainer(scene: .system, module: "globe") {
                WireGlobe(time: time)
            }
            LayoutModuleContainer(scene: .system, module: "marketFocus") {
                MarketFocusPanel(market: market, time: time, timeframe: timeframe)
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
    let timeframe: MarketTimeframe

    var body: some View {
        let symbol = activeSymbol
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("MARKET FEED // \(timeframe.label)")
                Spacer()
                Text("\(market.state.label) // CLICK")
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
                let chartValues = market.chartValues(for: symbol, timeframe: timeframe)
                MarketTrace(values: chartValues, quote: quote, includeDayRange: timeframe == .today)
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .topTrailing) {
                        if market.isLoadingChart(for: symbol, timeframe: timeframe) {
                            Text("LOADING \(timeframe.label)")
                                .font(consoleAuxiliaryFont(7, weight: .bold))
                                .foregroundStyle(dimPhosphor)
                                .padding(4)
                        } else if market.isChartUnavailable(for: symbol, timeframe: timeframe), chartValues.isEmpty {
                            Text("RANGE UNAVAILABLE")
                                .font(consoleAuxiliaryFont(7, weight: .bold))
                                .foregroundStyle(dimPhosphor)
                                .padding(4)
                        }
                    }
                HStack {
                    Text(timeframe == .today
                         ? "O \(marketPrice(quote.open))"
                         : "START \(marketPrice(chartValues.first ?? quote.previousClose))")
                    Spacer()
                    Text(timeframe == .today
                         ? "L \(marketPrice(quote.low))"
                         : "LOW \(marketPrice(chartValues.min() ?? quote.low))")
                    Spacer()
                    Text(timeframe == .today
                         ? "H \(marketPrice(quote.high))"
                         : "HIGH \(marketPrice(chartValues.max() ?? quote.high))")
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
        .task(id: "\(symbol ?? "none"):\(timeframe.rawValue)") {
            guard let symbol else { return }
            while !Task.isCancelled {
                await market.loadChart(for: symbol, timeframe: timeframe)
                try? await Task.sleep(for: .seconds(timeframe.refreshInterval))
            }
        }
    }

    private var activeSymbol: String? {
        guard !market.symbols.isEmpty else { return nil }
        return market.symbols[Int(time / 7) % market.symbols.count]
    }
}

struct MarketTrace: View {
    let values: [Double]
    let quote: MarketQuote
    var includeDayRange = true

    var body: some View {
        Canvas { context, size in
            drawGrid(context: &context, size: size, columns: 6, rows: 3, strength: 0.48)
            let samples = values.count > 1 ? values : [quote.previousClose, quote.price]
            let low = includeDayRange ? min(samples.min() ?? quote.low, quote.low) : (samples.min() ?? quote.low)
            let high = includeDayRange ? max(samples.max() ?? quote.high, quote.high) : (samples.max() ?? quote.high)
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

enum RadarTargetMode: String, CaseIterable, Identifiable {
    case precipitation, temperature, wind, decorative

    var id: String { rawValue }
    var next: RadarTargetMode {
        let values = Self.allCases
        let index = values.firstIndex(of: self) ?? 0
        return values[(index + 1) % values.count]
    }
    var title: String {
        switch self {
        case .precipitation: "PRECIPITATION // 12H"
        case .temperature: "TEMPERATURE // 12H"
        case .wind: "WIND FIELD"
        case .decorative: "DECORATIVE CONTACTS"
        }
    }
    var shortTitle: String {
        switch self {
        case .precipitation: "RAIN CELLS"
        case .temperature: "TEMP NODES"
        case .wind: "WIND FIELD"
        case .decorative: "CONTACTS"
        }
    }
}

private struct RadarTargetSample {
    let angle: Double
    let radius: Double
    let intensity: Double
}

private func radarTargets(for weather: WeatherSnapshot, mode: RadarTargetMode) -> [RadarTargetSample] {
    switch mode {
    case .precipitation:
        return Array(weather.precipitationForecast.prefix(12)).enumerated().map { index, chance in
            RadarTargetSample(
                angle: -82 + Double(index) * 31,
                radius: 0.22 + Double(index) / 16,
                intensity: min(1, max(0.06, chance))
            )
        }
    case .temperature:
        return Array(weather.temperatureForecast.prefix(12)).enumerated().map { index, level in
            RadarTargetSample(
                angle: -70 + Double(index) * 47,
                radius: 0.26 + Double((index * 7) % 9) / 14,
                intensity: min(1, max(0.10, level))
            )
        }
    case .wind:
        let level = min(1, max(0, weather.windSpeed / 45))
        let count = max(2, Int((level * 10).rounded()) + 2)
        return (0..<count).map { index in
            RadarTargetSample(
                angle: Double(index * 71) + weather.windSpeed * 1.8,
                radius: 0.24 + Double((index * 29) % 62) / 100,
                intensity: max(0.14, level)
            )
        }
    case .decorative:
        return (0..<7).map { index in
            RadarTargetSample(
                angle: Double(index * 53),
                radius: 0.25 + Double((index * 37) % 65) / 100,
                intensity: 0.82
            )
        }
    }
}

struct RadarScene: View {
    let weather: WeatherSnapshot
    let time: Double
    @AppStorage("DockTelemetry.weatherForecastDays") private var weatherForecastDays = 5
    @AppStorage("DockTelemetry.radarWidthCorrection") private var radarWidthCorrection = 1.10
    @AppStorage("DockTelemetry.radarHeightCorrection") private var radarHeightCorrection = 0.9254
    @AppStorage("DockTelemetry.radarTargetMode") private var radarTargetModeRaw = RadarTargetMode.precipitation.rawValue
    @AppStorage("DockTelemetry.radarTargetPulse") private var radarTargetPulse = true

    private var radarTargetMode: RadarTargetMode {
        RadarTargetMode(rawValue: radarTargetModeRaw) ?? .precipitation
    }

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
                let targets = radarTargets(for: weather, mode: radarTargetMode)
                for (index, target) in targets.enumerated() {
                    let drift = radarTargetMode == .decorative ? sin(time * 0.15 + Double(index)) * 15 : 0
                    let p = point(center: center, radius: radius * target.radius, angle: target.angle + drift)
                    let pulse = radarTargetPulse ? 0.76 + (sin(time * 3.1 + Double(index) * 0.78) + 1) * 0.25 : 1
                    let targetRadius = (2.1 + target.intensity * 5.6) * pulse
                    let opacity = 0.20 + target.intensity * 0.80
                    if radarTargetPulse {
                        let haloRadius = targetRadius * 1.9
                        context.stroke(
                            Path(ellipseIn: CGRect(x: p.x-haloRadius, y: p.y-haloRadius, width: haloRadius*2, height: haloRadius*2)),
                            with: .color(phosphor.opacity(opacity * 0.32)),
                            lineWidth: 0.8
                        )
                    }
                    switch radarTargetMode {
                    case .precipitation, .decorative:
                        context.fill(
                            Path(ellipseIn: CGRect(x: p.x-targetRadius, y: p.y-targetRadius, width: targetRadius*2, height: targetRadius*2)),
                            with: .color(phosphor.opacity(opacity))
                        )
                    case .temperature:
                        var diamond = Path()
                        diamond.move(to: CGPoint(x: p.x, y: p.y-targetRadius))
                        diamond.addLine(to: CGPoint(x: p.x+targetRadius, y: p.y))
                        diamond.addLine(to: CGPoint(x: p.x, y: p.y+targetRadius))
                        diamond.addLine(to: CGPoint(x: p.x-targetRadius, y: p.y))
                        diamond.closeSubpath()
                        context.stroke(diamond, with: .color(phosphor.opacity(opacity)), lineWidth: 1.4)
                    case .wind:
                        let heading = target.angle * .pi / 180
                        let dx = cos(heading) * targetRadius * 1.8
                        let dy = sin(heading) * targetRadius * 1.8
                        var streak = Path()
                        streak.move(to: CGPoint(x: p.x-dx, y: p.y-dy))
                        streak.addLine(to: CGPoint(x: p.x+dx, y: p.y+dy))
                        context.stroke(streak, with: .color(phosphor.opacity(opacity)), lineWidth: 1.8)
                    }
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
                    Text("\(radarTargetMode.shortTitle) \(radarTargets(for: weather, mode: radarTargetMode).count) // \(radarTargetPulse ? "PULSE" : "STEADY") // CLICK RADAR")
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
    @AppStorage("DockTelemetry.signalGridAnimationEnabled") private var gridAnimationEnabled = true
    @AppStorage("DockTelemetry.signalGridMetric") private var gridMetricRaw = SignalGridMetric.cpu.rawValue
    @AppStorage("DockTelemetry.signalGridPattern") private var gridPatternRaw = SignalGridPattern.recede.rawValue
    @AppStorage("DockTelemetry.signalGridResponse") private var gridResponseRaw = SignalGridResponse.medium.rawValue
    @State private var gridTravelPhase = 0.0
    @State private var gridWavePhase = 0.0
    @State private var smoothedGridMetric = 0.0
    @State private var lastGridTime: Double?

    private var gridMetricValue: Double {
        switch SignalGridMetric(rawValue: gridMetricRaw) ?? .cpu {
        case .cpu:
            snapshot.cpu
        case .gpuProxy:
            min(1, snapshot.load.0 / Double(max(1, ProcessInfo.processInfo.activeProcessorCount)))
        case .network:
            min(1, (snapshot.networkIn + snapshot.networkOut) / 12_000_000)
        case .disk:
            snapshot.disk
        }
    }

    private var gridMetricLabel: String {
        let metric = SignalGridMetric(rawValue: gridMetricRaw) ?? .cpu
        switch metric {
        case .network:
            return "GRID \(metric.shortTitle) \(byteRate(snapshot.networkIn + snapshot.networkOut))"
        default:
            return String(format: "GRID %@ %03.0f%%", metric.shortTitle, gridMetricValue * 100)
        }
    }

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
                        travelPhase: gridTravelPhase,
                        wavePhase: gridWavePhase,
                        metricValue: smoothedGridMetric,
                        pattern: SignalGridPattern(rawValue: gridPatternRaw) ?? .recede,
                        responseGain: (SignalGridResponse(rawValue: gridResponseRaw) ?? .medium).multiplier
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
                    Text(gridMetricLabel)
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
        .onAppear {
            smoothedGridMetric = gridMetricValue
            lastGridTime = time
        }
        .onChange(of: time) {
            advanceGridMotion(to: time)
        }
        .onChange(of: gridMetricRaw) {
            smoothedGridMetric = gridMetricValue
        }
    }

    private func advanceGridMotion(to newTime: Double) {
        defer { lastGridTime = newTime }
        guard gridAnimationEnabled, let previousTime = lastGridTime else { return }
        let delta = min(0.1, max(0, newTime - previousTime))
        guard delta > 0 else { return }
        let response = SignalGridResponse(rawValue: gridResponseRaw) ?? .medium
        let blend = 1 - exp(-delta * response.smoothingRate)
        smoothedGridMetric += (gridMetricValue - smoothedGridMetric) * blend
        gridTravelPhase += delta * (0.020 + smoothedGridMetric * 0.12) * response.multiplier
        gridWavePhase += delta * (0.25 + smoothedGridMetric * 1.30) * response.multiplier
    }
}

private func drawSynthwaveGrid(
    context: inout GraphicsContext,
    rect: CGRect,
    travelPhase: Double,
    wavePhase: Double,
    metricValue: Double,
    pattern: SignalGridPattern,
    responseGain: Double
) {
    let horizon = rect.minY + rect.height * 0.32
    let bottom = rect.maxY
    let centerX = rect.midX
    let normalizedMetric = min(1, max(0, metricValue))
    let metricEnergy = pow(normalizedMetric, 0.72) * (0.72 + responseGain * 0.52)
    let pulse = sin(wavePhase * 1.6)

    for index in -10...10 {
        let bottomX = centerX + CGFloat(index) * rect.width / 7.5
        var path = Path()
        for step in 0...64 {
            let depth = CGFloat(step) / 64
            let perspective = pow(depth, 1.58)
            let x = centerX + (bottomX - centerX) * perspective
            let xPhase = Double(index) * 0.43
            let phase: Double
            let amplitude: Double
            switch pattern {
            case .recede:
                phase = Double(depth) * 6.2 + xPhase + wavePhase * 0.16
                amplitude = 8.0 + metricEnergy * 24.0
            case .terrainPulse:
                phase = Double(depth) * 7.4 + xPhase - wavePhase * 1.10
                amplitude = 10.0 + metricEnergy * (18.0 + (pulse + 1) * 18.0)
            case .signalSweep:
                phase = Double(depth) * 10.0 + xPhase - wavePhase * 1.35
                amplitude = 9.0 + metricEnergy * 34.0
            }
            let terrain = sin(phase) * amplitude * Double(0.16 + perspective * 0.84)
            let y = horizon + (bottom - horizon) * perspective + CGFloat(terrain)
            step == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
        }
        context.stroke(path, with: .color(dimPhosphor.opacity(0.78)), lineWidth: 0.9)
    }

    for row in 0..<16 {
        let patternTravel: Double
        switch pattern {
        case .recede: patternTravel = travelPhase
        case .terrainPulse: patternTravel = sin(wavePhase * 0.7) * 0.025
        case .signalSweep: patternTravel = travelPhase * 0.45
        }
        let rawDepth = Double(row) / 16 - patternTravel
        let wrappedDepth = rawDepth - floor(rawDepth)
        let depth = CGFloat(wrappedDepth)
        let perspective = pow(depth, 1.82)
        let yBase = horizon + (bottom - horizon) * perspective
        var path = Path()
        for step in 0...80 {
            let xProgress = CGFloat(step) / 80
            let normalizedX = xProgress * 2 - 1
            let horizontalSpread = 0.16 + perspective * 1.18
            let x = centerX + normalizedX * rect.width * horizontalSpread
            let phase: Double
            let amplitude: Double
            switch pattern {
            case .recede:
                phase = Double(normalizedX) * .pi * 2.2 + Double(depth) * 6.2 + wavePhase * 0.16
                amplitude = 8.0 + metricEnergy * 24.0
            case .terrainPulse:
                phase = Double(normalizedX) * .pi * 2.6 + Double(depth) * 7.4 - wavePhase * 1.10
                amplitude = 10.0 + metricEnergy * (18.0 + (pulse + 1) * 18.0)
            case .signalSweep:
                phase = Double(normalizedX) * .pi * 3.0 + Double(depth) * 10.0 - wavePhase * 1.35
                amplitude = 9.0 + metricEnergy * 34.0
            }
            let y = yBase + CGFloat(sin(phase) * amplitude) * (0.18 + perspective * 0.82)
            step == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
        }
        context.stroke(path, with: .color(phosphor.opacity(0.38 + Double(perspective) * 0.56)), lineWidth: 0.8 + perspective * 1.0)
    }

    var horizonPath = Path()
    horizonPath.move(to: CGPoint(x: rect.minX, y: horizon))
    horizonPath.addLine(to: CGPoint(x: rect.maxX, y: horizon))
    context.stroke(horizonPath, with: .color(dimPhosphor.opacity(0.98)), lineWidth: 1.45)
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
