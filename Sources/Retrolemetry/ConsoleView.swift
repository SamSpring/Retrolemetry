import AppKit
import SwiftUI
import Combine

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
    case cpu, network, disk
    case gpu = "gpuProxy" // Preserve the saved picker value, now backed by actual GPU counters.

    var id: String { rawValue }
    var title: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .network: "NETWORK"
        case .disk: "DISK USED"
        }
    }
    var shortTitle: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
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

enum SignalDisplayMode: String, CaseIterable, Identifiable {
    case spinning
    case gpuHorizon = "memoryHorizon" // Existing horizon selections survive the data-source change.
    var id: String { rawValue }
    var title: String {
        switch self {
        case .spinning: "Spinning signal"
        case .gpuHorizon: "GPU at the horizon"
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

    var tabTitle: String {
        switch self {
        case .system: "Market"
        case .radar: "Weather"
        case .signal: "Signal"
        case .fullMetrics: "Metrics"
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
    @ObservedObject var renderState: ConsoleRenderState
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
    @AppStorage("DockTelemetry.animationFrameRate") private var animationFrameRate = 30.0
    @AppStorage("DockTelemetry.crtTubeEnabled") private var crtTubeEnabled = false
    @AppStorage("DockTelemetry.crtTubeStrength") private var crtTubeStrength = 0.35
    @ObservedObject private var layouts = LayoutStore.shared
    @State private var activeScene: ConsoleScene = .system
    @State private var previousScene: ConsoleScene?
    @State private var transitionProgress: CGFloat = 1
    @State private var transitionDirection = 1
    @State private var transitionGeneration = 0
    @State private var transitionStarted = 0.0
    @State private var nextSwitch = Date().addingTimeInterval(24)
    @State private var marketTimeframe: MarketTimeframe = .today
    private let sceneClock = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    init(renderState: ConsoleRenderState, preview: Bool = false, initialScene: ConsoleScene = .system) {
        self.renderState = renderState
        _activeScene = State(initialValue: initialScene)
        _market = StateObject(wrappedValue: MarketModel(preview: preview))
        _weather = StateObject(wrappedValue: WeatherModel(preview: preview))
    }

    var body: some View {
        let style = ConsoleStyle(rawValue: visualStyleRaw) ?? .phosphor
        ThemeRuntime.palette = style.palette
        let gpuVectors = VectorDisplay.isAvailable
        return ZStack {
            if renderState.isRendering {
            ZStack {
                ConsoleBackground(style: style, phosphorTintStrength: phosphorBackgroundTint)
                    .modifier(CRTTubeEffect(enabled: crtTubeEnabled, strength: crtTubeStrength))
                ConsoleTransitionSurface(progress: transitionProgress) { progress in
                ZStack {
                if gpuVectors {
                    ForEach(renderedScenes, id: \.self) { scene in
                        if scene != .fullMetrics {
                            VectorDisplay(configuration: vectorConfiguration(scene, progress: progress), paused: !renderState.isRendering, frameRate: animationFrameRate)
                                .allowsHitTesting(false)
                        }
                    }
                }
                transitioningScenes(time: 0, progress: progress)
                    .environment(\.consoleGPUVectors, gpuVectors)
                    .compositingGroup()
                    .shadow(
                        color: crtEnabled ? phosphor.opacity(0.24 * bloomStrength) : .clear,
                        radius: 2.5 + 3.5 * bloomStrength
                    )
                    .modifier(CRTTubeEffect(enabled: crtTubeEnabled, strength: crtTubeStrength, opaqueBackground: false))
                }
                }
            }
            if crtEnabled {
                CRTOverlay(
                    scanlineStrength: scanlineStrength,
                    noiseStrength: noiseStrength,
                    vhsTrackingEnabled: vhsTrackingEnabled,
                    trackingLine1Thickness: trackingLine1Thickness,
                    trackingLine2Thickness: trackingLine2Thickness,
                    time: 0,
                    tubeStrength: crtTubeEnabled ? crtTubeStrength : 0
                )
            }
                HorizontalScrollCapture(onDoubleClick: {
                    automaticCycleEnabled.toggle()
                    nextSwitch = Date().addingTimeInterval(cycleDuration)
                }) { direction in
                    moveScene(direction)
                } onClick: { point in
                    let point = CRTTubeGeometry.sourcePoint(
                        for: point, size: CGSize(width: 960, height: 540),
                        strength: crtTubeEnabled && CRTTubeEffect.isAvailable ? crtTubeStrength : 0
                    )
                    switch activeScene {
                    case .system:
                        for (module, offset) in [("marketTickerA", 0), ("marketTickerB", 5)] {
                            let frame = layouts.frame(.system, module)
                            if frame.visible, let row = MarketTickerGeometry.row(at: point, frame: frame, typography: layouts.typography(for: .system)),
                               offset + row < market.symbols.count {
                                market.focus(market.symbols[offset + row])
                                return
                            }
                        }
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
            } else {
                Color.black
            }
            }
            .frame(width: 960, height: 540)
            .foregroundStyle(phosphor)
            .consoleFont(14, role: .secondary, weight: .medium, fallback: .other)
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
        .environment(\.consoleAnimationEnabled, true)
        .environment(\.consoleAnimationPaused, !renderState.isRendering)
        .environment(\.consoleFrameRate, animationFrameRate)
        .onAppear {
            market.start()
            nextSwitch = Date().addingTimeInterval(cycleDuration)
        }
        .onDisappear { market.stop() }
        .onReceive(sceneClock) { now in
            guard renderState.isRendering, automaticCycleEnabled, now >= nextSwitch else { return }
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
        .onChange(of: renderState.isRendering) {
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
        guard scene != activeScene, previousScene == nil else { return }
        let style = SceneTransitionStyle(rawValue: transitionStyleRaw) ?? .pan
        transitionGeneration += 1
        let generation = transitionGeneration
        transitionStarted = ProcessInfo.processInfo.systemUptime
        previousScene = activeScene
        activeScene = scene
        transitionDirection = direction >= 0 ? 1 : -1
        transitionProgress = 0

        DispatchQueue.main.async {
            transitionStarted = ProcessInfo.processInfo.systemUptime
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

    private var renderedScenes: [ConsoleScene] {
        previousScene.map { [$0, activeScene] } ?? [activeScene]
    }
    private func vectorConfiguration(_ scene: ConsoleScene, progress: CGFloat) -> VectorConfiguration {
        var configuration = VectorConfiguration(scene: scene, layouts: layouts,
            snapshot: telemetry.snapshot, gpuHistory: telemetry.gpuHistory, weather: weather.snapshot,
            tubeStrength: crtTubeEnabled ? crtTubeStrength : 0, bloom: crtEnabled ? bloomStrength : 0,
            location: weather.snapshot.coordinate)
        if previousScene != nil {
            let style = SceneTransitionStyle(rawValue: transitionStyleRaw) ?? .pan
            configuration.transition = ConsoleTransitionMotion(start: transitionStarted, duration: style.duration,
                style: style, direction: transitionDirection, incoming: scene == activeScene)
            configuration.transitionProgress = Float(progress)
        }
        return configuration
    }

    @ViewBuilder
    private func transitioningScenes(time: Double, progress: CGFloat) -> some View {
        let style = SceneTransitionStyle(rawValue: transitionStyleRaw) ?? .pan
        ZStack {
            if let previousScene {
                transitionedScene(previousScene, time: time, incoming: false, style: style, progress: progress)
            }
            if previousScene == nil {
                sceneView(activeScene, time: time)
            } else {
                transitionedScene(activeScene, time: time, incoming: true, style: style, progress: progress)
            }
            if previousScene != nil {
                transitionOverlay(style: style, progress: progress)
            }
        }
        .frame(width: 960, height: 540)
        .clipped()
    }

    @ViewBuilder
    private func transitionedScene(_ scene: ConsoleScene, time: Double, incoming: Bool, style: SceneTransitionStyle, progress: CGFloat) -> some View {
        switch style {
        case .pan:
            sceneView(scene, time: time)
                .offset(x: incoming
                    ? CGFloat(transitionDirection) * 960 * (1 - progress)
                    : -CGFloat(transitionDirection) * 960 * progress)
        case .wipe:
            if incoming {
                sceneView(scene, time: time)
                    .mask(DiagonalWipeMask(progress: progress, direction: transitionDirection))
            } else {
                sceneView(scene, time: time)
                    .mask(DiagonalWipeMask(progress: progress, direction: transitionDirection, inverted: true).fill(style: FillStyle(eoFill: true)))
            }
        case .syncRoll:
            let halfProgress = incoming
                ? max(0, min(1, (progress - 0.48) / 0.52))
                : max(0, min(1, progress / 0.52))
            let verticalScale = incoming
                ? max(0.018, halfProgress)
                : max(0.018, 1 - halfProgress)
            sceneView(scene, time: time)
                .scaleEffect(x: 1 + (1 - verticalScale) * 0.018, y: verticalScale, anchor: .center)
                .offset(x: CGFloat(sin(Double(progress) * .pi * 15)) * (1 - verticalScale) * 11)
                .opacity(incoming ? (progress >= 0.48 ? 1 : 0) : (progress < 0.52 ? 1 : 0))
        }
    }

    private var sceneBackground: some View {
        ConsoleBackground(
            style: ConsoleStyle(rawValue: visualStyleRaw) ?? .phosphor,
            phosphorTintStrength: phosphorBackgroundTint
        )
    }

    @ViewBuilder
    private func transitionOverlay(style: SceneTransitionStyle, progress: CGFloat) -> some View {
        switch style {
        case .pan:
            EmptyView()
        case .wipe:
            DiagonalWipeEdge(progress: progress, direction: transitionDirection)
                .foregroundStyle(phosphor)
        case .syncRoll:
            SyncRollBand(progress: progress)
        }
    }

    @ViewBuilder
    private func sceneView(_ scene: ConsoleScene, time: Double) -> some View {
        Group { switch scene {
        case .system:
            SystemScene(market: market, time: time, timeframe: marketTimeframe, location: weather.snapshot.coordinate)
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
                gpuHistory: telemetry.gpuHistory,
                time: time
            )
        case .fullMetrics:
            FullMetricsScene(
                snapshot: telemetry.snapshot,
                cpuHistory: telemetry.cpuHistory,
                memoryHistory: telemetry.memoryHistory,
                networkReceiveHistory: telemetry.networkReceiveHistory,
                networkTransmitHistory: telemetry.networkTransmitHistory,
                gpuHistory: telemetry.gpuHistory,
                time: time
            )
        } }
        .consoleFont(14, role: .secondary, weight: .medium, fallback: .other)
        .environment(\.consoleTypography, layouts.typography(for: scene))
    }
}

private struct DiagonalWipeMask: Shape {
    var progress: CGFloat
    let direction: Int
    var inverted = false

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
        if inverted {
            var inverse = Path(rect)
            inverse.addPath(path)
            return inverse
        }
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
    var onDoubleClick: () -> Void = {}
    let onScroll: (Int) -> Void
    let onClick: (CGPoint) -> Void

    func makeNSView(context: Context) -> HorizontalScrollView {
        let view = HorizontalScrollView()
        view.onScroll = onScroll
        view.onClick = onClick
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: HorizontalScrollView, context: Context) {
        nsView.onScroll = onScroll
        nsView.onClick = onClick
        nsView.onDoubleClick = onDoubleClick
    }
}

final class HorizontalScrollView: NSView {
    var onScroll: ((Int) -> Void)?
    var onClick: ((CGPoint) -> Void)?
    var onDoubleClick: (() -> Void)?
    private var pendingClick: DispatchWorkItem?
    private var accumulated: CGFloat = 0
    private var gestureTriggered = false
    private var lastDirectEvent = Date.distantPast
    private let preciseThreshold: CGFloat = 26
    private let gestureIdleTimeout: TimeInterval = 0.18

    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
        pendingClick?.cancel()
        pendingClick = nil
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }
        guard event.clickCount == 1 else { return }
        let local = convert(event.locationInWindow, from: nil)
        let point = CGPoint(x: local.x, y: isFlipped ? local.y : bounds.height - local.y)
        let click = DispatchWorkItem { [weak self] in self?.onClick?(point) }
        pendingClick = click
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: click)
    }

    deinit { pendingClick?.cancel() }

    override func scrollWheel(with event: NSEvent) {
        pendingClick?.cancel()
        pendingClick = nil
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
                .padding(.horizontal, 14)
                .padding(.vertical, 2)
            VStack(spacing: 0) {
                HStack {
                    Text("CG//DOCK NODE 01")
                    Spacer()
                    Text(title)
                    Spacer()
                    ConsoleTimeline(time: time, interval: 0.5) { tick in
                        Text("LINK \(Int(tick * 2).isMultiple(of: 2) ? "●" : "○") ACTIVE")
                    }
                }
                .consoleFont(13, role: .frameHeader, weight: .bold)
                .lineLimit(1).minimumScaleFactor(0.4)
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
                .consoleFont(11, role: .frameFooter, weight: .semibold)
                .lineLimit(1).minimumScaleFactor(0.4)
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
    var location: GlobeCoordinate? = nil
    @Environment(\.consoleGPUVectors) private var gpuVectors

    var body: some View {
        ZStack {
            FrameChrome(title: "MARKET WATCH", section: "MKT", time: time)
            LayoutModuleContainer(scene: .system, module: "globe") {
                ZStack(alignment: .bottom) {
                if !gpuVectors {
                ConsoleTimeline(time: time) { tick in WireGlobe(time: tick, location: location) }
                }
                ConsoleTimeline(time: time, interval: 1) { _ in GlobeLegend(hasLocation: location != nil) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            LayoutModuleContainer(scene: .system, module: "marketFocus") {
                ConsoleTimeline(time: time, interval: 1) { tick in
                    MarketFocusPanel(market: market, time: tick, timeframe: timeframe)
                }
            }
            LayoutModuleContainer(scene: .system, module: "marketClocks") {
                ConsoleTimeline(time: time, interval: 1) { tick in MarketWorldClocks(time: tick) }
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
    let networkReceiveHistory: [Double]
    let networkTransmitHistory: [Double]
    var gpuHistory: [Double?] = []
    let time: Double

    var body: some View {
        ZStack {
            FrameChrome(title: "LIVE SYSTEM METRICS", section: "DAT", time: time)
            LayoutModuleContainer(scene: .fullMetrics, module: "metricCPU") { LargeMetricTile(label: "CPU LOAD", value: percent(snapshot.cpu), level: snapshot.cpu) }
            LayoutModuleContainer(scene: .fullMetrics, module: "metricMemory") {
                LargeMetricTile(label: "MEMORY", value: percent(snapshot.memory), level: snapshot.memory,
                                showsCapacity: true, capacity: snapshot.memoryCapacity)
                    .help("Used RAM is active + wired + compressed memory. Free is the remaining physical RAM, including cached/reclaimable memory. Amounts use decimal GB.")
            }
            LayoutModuleContainer(scene: .fullMetrics, module: "metricDisk") {
                LargeMetricTile(label: "DISK USED", value: percent(snapshot.disk), level: snapshot.disk,
                                showsCapacity: true, capacity: snapshot.diskCapacity)
                    .help("Used and free capacity reported by macOS for the startup filesystem. Amounts use decimal GB/TB; refreshed every 30 seconds.")
            }
            LayoutModuleContainer(scene: .fullMetrics, module: "metricNetwork") { LargeMetricTile(label: "NETWORK RX", value: byteRate(snapshot.networkIn), level: min(1, snapshot.networkIn / 12_000_000)) }
            LayoutModuleContainer(scene: .fullMetrics, module: "metricGPU") {
                LargeMetricTile(label: "GPU BUSY", value: snapshot.gpu.map(percent) ?? "N/A", level: snapshot.gpu)
                    .help("Utilization reported by the busiest exposed GPU; N/A means the driver does not expose a reading.")
            }
            LayoutModuleContainer(scene: .fullMetrics, module: "metricPower") { PowerVoltageTile(reading: snapshot.power) }
            LayoutModuleContainer(scene: .fullMetrics, module: "graphCPU") { LargeDataGraph(label: "CPU // 96 SEC", value: percent(snapshot.cpu), values: cpuHistory) }
            LayoutModuleContainer(scene: .fullMetrics, module: "graphMemory") { LargeDataGraph(label: "MEMORY // 96 SEC", value: percent(snapshot.memory), values: memoryHistory) }
            LayoutModuleContainer(scene: .fullMetrics, module: "graphNetwork") {
                NetworkTrafficPanel(transmit: snapshot.networkOut, receiveHistory: networkReceiveHistory,
                                    transmitHistory: networkTransmitHistory)
            }
            LayoutModuleContainer(scene: .fullMetrics, module: "graphGPU") {
                LargeDataGraph(label: "GPU // 96 SEC", value: snapshot.gpu.map(percent) ?? "N/A", optionalValues: gpuHistory)
            }
            LayoutModuleContainer(scene: .fullMetrics, module: "statusUptime") { LargeStatusReadout(label: "UPTIME", value: snapshot.uptime.compactUptime) }
            LayoutModuleContainer(scene: .fullMetrics, module: "statusLoad") { LargeStatusReadout(label: "LOAD 1 / 5 / 15", value: String(format: "%.1f  %.1f  %.1f", snapshot.load.0, snapshot.load.1, snapshot.load.2)) }
            // Retain the saved module ID so existing custom layouts do not move or reset.
            LayoutModuleContainer(scene: .fullMetrics, module: "statusTX") { LargeStatusReadout(label: "NETWORK RX", value: byteRate(snapshot.networkIn)) }
        }
    }

    private func percent(_ value: Double) -> String {
        String(format: "%03.0f%%", value * 100)
    }
}

struct LargeMetricTile: View {
    @Environment(\.consoleTypography) private var typography
    let label: String
    let value: String
    let level: Double?
    var showsCapacity = false
    var capacity: CapacityReading? = nil

    var body: some View {
        GeometryReader { geometry in
          let valueSize = value.count > 7 ? 23.0 : 31.0
          let capacityHeight = showsCapacity ? 11 * max(typography.primary, typography.scale(.dark)) + 8 : 0
          let requiredHeight = 13 * typography.secondary + valueSize * typography.primary + 29 + capacityHeight
          let fit = min(1, max(0.35, (geometry.size.height - 24) / requiredHeight))
          VStack(alignment: .leading, spacing: 8 * fit) {
            Text(label)
                .consoleFont(13 * fit, role: .secondary, weight: .bold)
                .lineLimit(1).minimumScaleFactor(0.55)
            Text(value)
                .consoleFont(valueSize * fit, role: .primary, weight: .bold)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
            if showsCapacity {
                CapacitySummary(capacity: capacity, fit: fit)
            }
            HStack(spacing: 3) {
                ForEach(0..<12, id: \.self) { index in
                    Rectangle()
                        .fill(Double(index) / 12 < (level ?? 0) ? phosphor : dimPhosphor)
                }
            }
            .frame(height: 13 * fit)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .overlay(Rectangle().stroke(dimPhosphor.opacity(0.95), lineWidth: 1.2))
    }
}

struct PowerVoltageTile: View {
    @Environment(\.consoleTypography) private var typography
    let reading: PowerReading

    var body: some View {
        GeometryReader { geometry in
            let requiredHeight = 11 * typography.secondary + 42 * typography.primary + 8 * typography.scale(.dark, fallback: .other) + 12
            let fit = min(1, max(0.35, (geometry.size.height - 20) / requiredHeight))
            VStack(alignment: .leading, spacing: 4 * fit) {
                Text("POWER / VOLTAGE")
                    .consoleFont(11 * fit, role: .secondary, weight: .bold)
                Text(reading.watts.map { String(format: "%.1f W", $0) } ?? "N/A W")
                    .consoleFont(23 * fit, role: .primary, weight: .bold)
                Text(reading.voltage.map { String(format: "%.2f V", $0) } ?? "N/A V")
                    .consoleFont(19 * fit, role: .primary, weight: .bold)
                Text(reading.status)
                    .consoleFont(8 * fit, role: .dark, weight: .bold, fallback: .other)
                    .consoleDimmed()
            }
            .lineLimit(1).minimumScaleFactor(0.45)
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .overlay(Rectangle().stroke(dimPhosphor.opacity(0.95), lineWidth: 1.2))
        .help("Battery electrical flow (voltage × current), not total Mac or CPU/GPU power. Sensors are optional on each Mac.")
    }
}

struct LargeDataGraph: View {
    let label: String
    let value: String
    var values: [Double] = []
    var optionalValues: [Double?]? = nil

    var body: some View {
        VStack(spacing: 0) {
            DataGraphHeader(label: label, value: value)

            if let optionalValues {
                LineGraph(optionalValues: optionalValues, showsBorder: false)
                    .overlay {
                        if !optionalValues.contains(where: { $0 != nil }) {
                            Text("GPU DATA UNAVAILABLE")
                                .consoleFont(10, role: .secondary, weight: .bold, fallback: .other)
                                .lineLimit(1).minimumScaleFactor(0.55)
                                .padding(8)
                        }
                    }
            } else {
                LineGraph(values: values, showsBorder: false)
            }
        }
        .overlay(Rectangle().stroke(dimPhosphor, lineWidth: 1))
        .clipped()
    }
}

struct LargeStatusReadout: View {
    @Environment(\.consoleTypography) private var typography
    let label: String
    let value: String

    var body: some View {
        GeometryReader { geometry in
        let fit = min(1, max(0.25, (geometry.size.height - 16) / (11 * typography.scale(.secondary, dimmed: true) + 20 * typography.primary + 5)))
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .consoleFont(11 * fit, role: .secondary, weight: .bold)
                .consoleDimmed()
                .lineLimit(1).minimumScaleFactor(0.3)
            Text(value)
                .consoleFont(20 * fit, role: .primary, weight: .bold)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
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
        .consoleFont(12, role: .secondary, weight: .bold)
    }
}

struct Readout: View {
    @Environment(\.consoleTypography) private var typography
    let label: String
    let value: String

    var body: some View {
        GeometryReader { geometry in
        let fit = min(1, max(0.2, (geometry.size.height - 18) / (9 * typography.scale(.secondary, dimmed: true) + 15 * typography.primary + 4)))
        VStack(alignment: .leading, spacing: 4) {
            Text(label).consoleFont(9 * fit, role: .secondary).consoleDimmed()
                .lineLimit(1).minimumScaleFactor(0.5)
            Text(value).consoleFont(15 * fit, role: .primary, weight: .semibold)
                .lineLimit(1).minimumScaleFactor(0.25)
        }
        .padding(9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
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
            Text(label).consoleFont(9, role: .secondary, fallback: .other)
        }
    }
}

struct LineGraph: View {
    let values: [Double?]
    var showsBorder = true

    init(values: [Double], showsBorder: Bool = true) {
        self.values = values.map { $0 }
        self.showsBorder = showsBorder
    }

    init(optionalValues: [Double?], showsBorder: Bool = true) {
        values = optionalValues
        self.showsBorder = showsBorder
    }

    var body: some View {
        Canvas { context, size in
            drawGrid(context: &context, size: size, columns: 12, rows: 4)
            guard values.count > 1 else { return }
            let plot = CGRect(x: 0, y: 6, width: size.width, height: max(0, size.height - 12))
            for segment in UsageHistoryGeometry.segments(values, in: plot) {
                var path = Path()
                for (index, point) in segment.enumerated() {
                    index == 0 ? path.move(to: point) : path.addLine(to: point)
                }
                if segment.count == 1, let point = segment.first {
                    context.fill(Path(ellipseIn: CGRect(x: point.x - 1.5, y: point.y - 1.5, width: 3, height: 3)), with: .color(phosphor))
                } else {
                    context.stroke(path, with: .color(phosphor), lineWidth: 2.2)
                }
            }
        }
        .overlay {
            if showsBorder {
                Rectangle().stroke(dimPhosphor, lineWidth: 1)
            }
        }
    }
}

struct WireGlobe: View {
    let time: Double
    var location: GlobeCoordinate? = nil
    @AppStorage("DockTelemetry.globeWidthCorrection") private var widthCorrection = 1.10
    @AppStorage("DockTelemetry.globeHeightCorrection") private var heightCorrection = 0.9254

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) * 0.41
            let rotation = time * 0.48
            let activity = TradingRegionActivity(at: Date())
            func screen(_ p: SIMD3<Double>) -> CGPoint {
                CGPoint(x: center.x + p.x * radius, y: center.y + p.y * radius)
            }
            context.stroke(Path(ellipseIn: CGRect(x: center.x-radius, y: center.y-radius, width: radius*2, height: radius*2)), with: .color(phosphor), lineWidth: 1.4)
            for latitude in stride(from: -60.0, through: 60.0, by: 20) {
                let scale = cos(latitude * .pi / 180)
                let y = center.y - sin(latitude * .pi / 180) * radius
                context.stroke(Path(ellipseIn: CGRect(x: center.x-radius*scale, y: y-radius*0.1*scale, width: radius*scale*2, height: radius*0.2*scale)), with: .color(dimPhosphor), lineWidth: 1)
            }
            for index in 0..<GlobeGeometry.meridianCount {
                let longitude = GlobeGeometry.longitude(index, rotation: rotation)
                var line = Path()
                for step in 0...72 {
                    let latitude = -.pi / 2 + Double(step) / 72 * .pi
                    let p = CGPoint(x: center.x + cos(latitude)*sin(longitude)*radius, y: center.y-sin(latitude)*radius)
                    step == 0 ? line.move(to: p) : line.addLine(to: p)
                }
                context.stroke(line, with: .color(dimPhosphor.opacity(cos(longitude) >= 0 ? 0.92 : 0.46)), lineWidth: cos(longitude) >= 0 ? 1.05 : 0.7)
            }
            for edge in GlobeCoastlines.degrees {
                let a = GlobeGeometry.project(latitude: Double(edge.y), longitude: Double(edge.x), rotation: rotation)
                let b = GlobeGeometry.project(latitude: Double(edge.w), longitude: Double(edge.z), rotation: rotation)
                let region = GlobeGeometry.region(longitude: Double(edge.x+edge.z)/2, latitude: Double(edge.y+edge.w)/2)
                var line = Path(); line.move(to: screen(a)); line.addLine(to: screen(b))
                let active = activity[region]
                context.stroke(line, with: .color((active ? phosphor : dimPhosphor).opacity(a.z >= 0 && b.z >= 0 ? (active ? 1 : 0.88) : 0.14)), lineWidth: active ? 1.7 : 1.05)
            }
            let markers: [(GlobeCoordinate?, Bool, Bool)] = [
                (location, true, true),
                (GlobeCoordinate(latitude: 40.713, longitude: -74.006), activity.us, false),
                (GlobeCoordinate(latitude: 51.507, longitude: -0.128), activity.europe, false),
                (GlobeCoordinate(latitude: 35.690, longitude: 139.692), activity.asia, false)
            ]
            for (coordinate, active, local) in markers {
                guard let coordinate else { continue }
                let p = GlobeGeometry.project(latitude: coordinate.latitude, longitude: coordinate.longitude, rotation: rotation)
                guard p.z >= 0 else { continue }
                let point = screen(p)
                let pulse = local ? 0.80 + (sin(time*3)+1)*0.25 : 1
                let color = active ? phosphor : dimPhosphor
                context.fill(Path(ellipseIn: CGRect(x: point.x-2.3*pulse, y: point.y-2.3*pulse, width: 4.6*pulse, height: 4.6*pulse)), with: .color(color))
                context.stroke(Path(ellipseIn: CGRect(x: point.x-4.6*pulse, y: point.y-4.6*pulse, width: 9.2*pulse, height: 9.2*pulse)), with: .color(color.opacity(0.45)), lineWidth: 0.9)
            }
            var axis = Path(); axis.move(to: CGPoint(x: center.x,y: center.y-radius-9)); axis.addLine(to: CGPoint(x: center.x,y: center.y+radius+9))
            context.stroke(axis, with: .color(phosphor.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [4,5]))
        }
        .scaleEffect(x: widthCorrection, y: heightCorrection)
    }
}

struct GlobeLegend: View {
    let hasLocation: Bool
    var body: some View {
        let activity = TradingRegionActivity(at: Date())
        HStack(spacing: 7) {
            if hasLocation { Text("◎ LOCAL") }
            Text("US \(activity.us ? "●" : "○")")
            Text("EU \(activity.europe ? "●" : "○")")
            Text("AS \(activity.asia ? "●" : "○")")
        }
        .consoleFont(7, role: .secondary, weight: .bold, fallback: .other)
        .lineLimit(1).minimumScaleFactor(0.6)
        .padding(.bottom, 3)
        .help("Region lights follow regular weekday sessions in New York, London/Frankfurt and Tokyo/Hong Kong. Holidays, early closes and extended trading are not included. The pulsing location uses the existing approximate weather location and stays on this Mac.")
    }
}

struct MarketFocusPanel: View {
    @ObservedObject var market: MarketModel
    @Environment(\.consoleTypography) private var typography
    let time: Double
    let timeframe: MarketTimeframe

    var body: some View {
        let symbol = activeSymbol
        GeometryReader { geometry in
        let textHeight = (9 * typography.scale(.secondary, dimmed: true)
            + max(17 * typography.scale(.secondary, fallback: .primary), 28 * typography.primary)
            + max(13 * typography.primary, 8 * typography.scale(.dark, fallback: .other))
            + 8 * typography.scale(.secondary, fallback: .other)) * 1.2
        let fit = min(1, max(0.25, (geometry.size.height - 50 - max(24, geometry.size.height * 0.23)) / textHeight))
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("MARKET FEED // \(timeframe.label)")
                Spacer()
                Text("\(market.state.label) // CLICK")
            }
            .consoleFont(9 * fit, role: .secondary, weight: .bold)
            .consoleDimmed()
            .lineLimit(1).minimumScaleFactor(0.3)

            if let symbol, let quote = market.quotes[symbol] {
                HStack(alignment: .firstTextBaseline) {
                    Text(symbol)
                        .consoleFont(17 * fit, role: .secondary, weight: .bold, fallback: .primary)
                    Spacer()
                    Text(marketPrice(quote.price))
                        .consoleFont(28 * fit, role: .primary, weight: .bold)
                        .lineLimit(1).minimumScaleFactor(0.3)
                }
                HStack {
                    Text(String(format: "%+.2f  %+.2f%%", quote.change, quote.percentChange))
                        .consoleFont(13 * fit, role: .primary, weight: .bold)
                        .lineLimit(1).minimumScaleFactor(0.3)
                    Spacer()
                    Text("LAST \(marketTime(quote.tradeTime))")
                        .consoleFont(8 * fit, role: .dark, weight: .bold, fallback: .other)
                        .consoleDimmed()
                        .lineLimit(1).minimumScaleFactor(0.3)
                }
                let chartValues = market.chartValues(for: symbol, timeframe: timeframe)
                MarketTrace(values: chartValues, quote: quote, includeDayRange: timeframe == .today)
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .topTrailing) {
                        if market.isLoadingChart(for: symbol, timeframe: timeframe) {
                            Text("LOADING \(timeframe.label)")
                                .consoleFont(7, role: .dark, weight: .bold, fallback: .other)
                                .consoleDimmed()
                                .padding(4)
                        } else if market.isChartUnavailable(for: symbol, timeframe: timeframe), chartValues.isEmpty {
                            Text("RANGE UNAVAILABLE")
                                .consoleFont(7, role: .dark, weight: .bold, fallback: .other)
                                .consoleDimmed()
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
                .consoleFont(8 * fit, role: .secondary, weight: .bold, fallback: .other)
                .lineLimit(1).minimumScaleFactor(0.3)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(market.state == .needsAPIKey ? "FINNHUB KEY REQUIRED" : "AWAITING QUOTE DATA")
                        .consoleFont(15, role: .secondary, weight: .bold)
                    Text(market.state == .needsAPIKey
                         ? "OPEN SETTINGS // LIVE MARKET DATA"
                         : "CONNECTING TO LIVE US MARKET FEED")
                        .consoleFont(9, role: .dark, weight: .bold, fallback: .other)
                        .consoleDimmed()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .padding(11)
        }
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
        if let focused = market.focusedSymbol, market.symbols.contains(focused) { return focused }
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
                .consoleFont(8, role: .secondary, weight: .bold, fallback: .other)
                .consoleDimmed()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(clockTime(date, identifier: option.id))
                .consoleFont(14, role: .primary, weight: .bold)
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.3)
        }
        .frame(maxWidth: .infinity)
    }
}

struct MarketTickerList: View {
    @Environment(\.consoleTypography) private var typography
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
            .consoleFont(9, role: .secondary, weight: .bold)
            .frame(height: MarketTickerGeometry.headerHeight(typography))
            .lineLimit(1).minimumScaleFactor(0.6)
            .consoleDimmed()
            Rectangle().fill(dimPhosphor.opacity(0.65)).frame(height: 1)
            ForEach(0..<5, id: \.self) { row in
                let index = startIndex + row
                let symbol = index < market.symbols.count ? market.symbols[index] : nil
                HStack(spacing: 5) {
                    Circle()
                        .fill(symbol.flatMap { market.quotes[$0] } == nil ? dimPhosphor : phosphor)
                        .frame(width: 6, height: 6)
                    Text(symbol ?? "AVAILABLE")
                        .consoleFont(9, role: .secondary, weight: .bold, fallback: .primary)
                        .consoleDimmed(symbol == nil)
                        .frame(width: 66, alignment: .leading)
                    Spacer()
                    if let symbol, let quote = market.quotes[symbol] {
                        Text(marketPrice(quote.price)).frame(width: 58, alignment: .trailing)
                        Text(String(format: "%+.2f%%", quote.percentChange)).frame(width: 56, alignment: .trailing)
                    } else {
                        Text("--").frame(width: 119, alignment: .trailing)
                    }
                }
                .consoleFont(9, role: .primary, weight: .bold)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(maxHeight: .infinity)
                .background(symbol != nil && symbol == market.focusedSymbol ? phosphor.opacity(0.10) : .clear)
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
                    .consoleFont(9, role: .secondary, weight: .bold)
                    .consoleDimmed()
                    .lineLimit(1).minimumScaleFactor(0.25)
                Spacer()
                if let latest = points.last {
                    Text(String(format: "%.4f", latest.rate))
                        .consoleFont(14, role: .primary, weight: .bold)
                        .lineLimit(1).minimumScaleFactor(0.25)
                } else {
                    Text("LOADING")
                        .consoleFont(9, role: .secondary, weight: .bold, fallback: .other)
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
                .consoleFont(8, role: .dark, weight: .bold, fallback: .other)
                .consoleDimmed()
                .lineLimit(1).minimumScaleFactor(0.25)
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
        case .precipitation: "RAIN CHANCE // CURRENT HOUR"
        case .temperature: "TEMPERATURE // REGIONAL"
        case .wind: "WIND // SPEED + DIRECTION"
        case .decorative: "DECORATIVE CONTACTS"
        }
    }
    var shortTitle: String {
        switch self {
        case .precipitation: "RAIN CHANCE"
        case .temperature: "TEMP NODES"
        case .wind: "WIND FIELD"
        case .decorative: "CONTACTS"
        }
    }
}

struct RadarTargetSample {
    let angle: Double
    let radius: Double
    let intensity: Double
    var mapPosition: SIMD2<Float> = .zero
    var heading = 0.0
}

func radarTargets(for weather: WeatherSnapshot, mode: RadarTargetMode) -> [RadarTargetSample] {
    if mode == .decorative {
        return (0..<7).map { index in
            RadarTargetSample(
                angle: Double(index * 53),
                radius: 0.25 + Double((index * 37) % 65) / 100,
                intensity: 0.82
            )
        }
    }
    guard let update = weather.radarUpdatedAt, Date().timeIntervalSince(update) < 3600 else { return [] }
    return weather.radarWeather.compactMap { sample in
        guard let value = sample.value(for: mode), mode != .wind || sample.windDirection != nil else { return nil }
        let intensity: Double
        switch mode {
        case .precipitation: intensity = value
        case .temperature: intensity = (value + 5) / 45
        case .wind: intensity = value / 50
        case .decorative: intensity = 0
        }
        return RadarTargetSample(angle: 0, radius: 0, intensity: min(1, max(0, intensity)),
            mapPosition: RadarMapGeometry.position(latitude: sample.site.latitude, longitude: sample.site.longitude, region: weather.radarRegion ?? .israel),
            heading: (sample.windDirection ?? 0) + 90)
    }
}

struct RadarScene: View {
    let weather: WeatherSnapshot
    let time: Double
    @Environment(\.consoleTypography) private var typography
    @Environment(\.consoleGPUVectors) private var gpuVectors
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
            FrameChrome(title: "WEATHER // \(weather.radarRegion?.screenTitle ?? "REGION") SCAN", section: "WX", time: time)
            LayoutModuleContainer(scene: .radar, module: "radar") {
              ZStack(alignment: .topLeading) {
              if !gpuVectors {
              ConsoleTimeline(time: time) { time in
              Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) * 0.47
                for ring in 1...4 {
                    let r = radius * CGFloat(ring) / 4
                    context.stroke(Path(ellipseIn: CGRect(x: center.x-r, y: center.y-r, width: r*2, height: r*2)), with: .color(dimPhosphor.opacity(0.35)), lineWidth: 1.1)
                }
                for angle in stride(from: 0.0, to: 360.0, by: 30) {
                    let p = point(center: center, radius: radius, angle: angle)
                    var line = Path(); line.move(to: center); line.addLine(to: p)
                    context.stroke(line, with: .color(dimPhosphor.opacity(0.35)), lineWidth: 1.1)
                }
                let sweep = time * 42
                for trail in 0..<16 {
                    let angle = sweep - Double(trail) * 2.3
                    var line = Path(); line.move(to: center); line.addLine(to: point(center: center, radius: radius, angle: angle))
                    context.stroke(line, with: .color(phosphor.opacity(0.25 * (1 - Double(trail)/16))), lineWidth: 2)
                }
                let mapCenter = CGPoint(x: center.x + size.width * 0.10, y: center.y)
                let mapEdges = weather.radarRegion.map { RadarMapGeometry.segments(for: $0) } ?? []
                for (index, edge) in mapEdges.enumerated() {
                    var path = Path()
                    path.move(to: CGPoint(x: mapCenter.x + CGFloat(edge.x)*radius, y: mapCenter.y + CGFloat(edge.y)*radius))
                    path.addLine(to: CGPoint(x: mapCenter.x + CGFloat(edge.z)*radius, y: mapCenter.y + CGFloat(edge.w)*radius))
                    let city = index >= (weather.radarRegion.map { RadarMapGeometry.countrySegmentCount(for: $0) } ?? 0)
                    context.stroke(path, with: .color(city ? dimPhosphor.opacity(1) : phosphor.opacity(0.92)), lineWidth: city ? 1.6 : 1.2)
                }
                let targets = radarTargets(for: weather, mode: radarTargetMode)
                for (index, target) in targets.enumerated() {
                    let drift = radarTargetMode == .decorative ? sin(time * 0.15 + Double(index)) * 15 : 0
                    let p = radarTargetMode == .decorative
                        ? point(center: center, radius: radius * target.radius, angle: target.angle + drift)
                        : CGPoint(x: mapCenter.x + CGFloat(target.mapPosition.x)*radius, y: mapCenter.y + CGFloat(target.mapPosition.y)*radius)
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
                        let heading = target.heading * .pi / 180
                        let dx = cos(heading) * targetRadius * 1.8
                        let dy = sin(heading) * targetRadius * 1.8
                        var streak = Path()
                        streak.move(to: CGPoint(x: p.x-dx, y: p.y-dy))
                        streak.addLine(to: CGPoint(x: p.x+dx, y: p.y+dy))
                        let tip = CGPoint(x: p.x+dx, y: p.y+dy)
                        for offset in [-0.55, 0.55] {
                            streak.move(to: tip)
                            streak.addLine(to: CGPoint(x: tip.x - cos(heading+offset)*targetRadius, y: tip.y - sin(heading+offset)*targetRadius))
                        }
                        context.stroke(streak, with: .color(phosphor.opacity(opacity)), lineWidth: 1.8)
                    }
                }
              }
              .scaleEffect(x: radarWidthCorrection, y: radarHeightCorrection, anchor: .center)
              }
              }
              RadarForecastLegend(weather: weather, mode: radarTargetMode)
              }
            }
            LayoutModuleContainer(scene: .radar, module: "weatherHeader") {
                GeometryReader { geometry in
                let leftFit = min(1, max(0.2, (geometry.size.height - 4) / (11 * typography.scale(.dark, fallback: .secondary) + 18 * typography.scale(.secondary, fallback: .primary) + 3)))
                let valueFit = min(1, max(0.2, (geometry.size.height - 4) / (40 * typography.primary)))
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(weather.location)
                            .consoleFont(11 * leftFit, role: .dark, weight: .bold, fallback: .secondary)
                            .consoleDimmed()
                        Text(weather.localForecastIsAvailable ? weather.condition : "LOCAL FORECAST OFFLINE")
                            .consoleFont(18 * leftFit, role: .secondary, weight: .bold, fallback: .primary)
                    }
                    Spacer()
                    Text(weather.localForecastIsAvailable ? String(format: "%.0f°C", weather.temperature) : "N/A")
                        .consoleFont(40 * valueFit, role: .primary, weight: .bold)
                }
                .lineLimit(1).minimumScaleFactor(0.25)
                .frame(maxHeight: .infinity, alignment: .center)
                }
            }
            LayoutModuleContainer(scene: .radar, module: "weatherStats") {
                HStack(spacing: 8) {
                    WeatherReadout(label: "FEELS", value: weather.localForecastIsAvailable ? String(format: "%.0f°C", weather.apparentTemperature) : "N/A")
                    WeatherReadout(label: "HUMID", value: weather.localForecastIsAvailable ? String(format: "%.0f%%", weather.humidity * 100) : "N/A")
                    WeatherReadout(label: "WIND", value: weather.localForecastIsAvailable ? String(format: "%.0f KM/H", weather.windSpeed) : "N/A")
                    WeatherReadout(label: "RAIN", value: weather.localForecastIsAvailable ? String(format: "%.1f MM", weather.precipitation) : "N/A")
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
                    Text(weather.radarStatus)
                    Spacer()
                    Text("FORECAST // CLICK RADAR")
                }
                .consoleFont(10, role: .secondary, weight: .bold, fallback: .other)
                .lineLimit(1).minimumScaleFactor(0.4)
            }
        }
    }
}

struct RadarForecastLegend: View {
    let weather: WeatherSnapshot
    let mode: RadarTargetMode

    var body: some View {
        GeometryReader { size in
            VStack(alignment: .leading, spacing: 5) {
                Text(mode == .decorative ? "DEMO CONTACTS" : "\(weather.radarRegion?.screenTitle ?? "REGION") FORECAST")
                    .consoleFont(9, role: .secondary, weight: .bold)
                Text(mode.shortTitle)
                    .consoleFont(10, role: .secondary, weight: .bold)
                Spacer(minLength: 4)
                if weather.radarRegion == nil {
                    Text("ALLOW LOCATION\nOR SELECT MAP\nIN SETTINGS")
                        .consoleFont(9, role: .secondary, weight: .bold)
                        .lineLimit(3)
                }
                if mode != .decorative {
                    ForEach(Array((weather.radarRegion?.sites ?? []).enumerated()), id: \.offset) { _, site in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(site.name).consoleFont(8, role: .dark, weight: .bold, fallback: .secondary).consoleDimmed()
                            Text(readout(site)).consoleFont(13, role: .primary, weight: .bold)
                        }
                        .frame(maxHeight: .infinity, alignment: .center)
                    }
                }
                Spacer(minLength: 4)
                Text(weather.radarRegion == .israel ? "TEL AVIV OUTLINED" : "REGIONAL POINTS")
                    .consoleFont(8, role: .dark, weight: .bold, fallback: .other).consoleDimmed()
                Text(mode == .decorative ? "DECORATIVE" : "MODEL • NOT RADAR")
                    .consoleFont(7, role: .secondary, fallback: .other)
                Text(weather.radarRegion == .israel ? "© OSM • Natural Earth" : "Natural Earth")
                    .consoleFont(6, role: .dark, fallback: .other).consoleDimmed()
            }
            .lineLimit(1).minimumScaleFactor(0.33)
            .padding(7)
            .frame(width: max(70, size.size.width * 0.27), height: size.size.height, alignment: .leading)
        }
        .allowsHitTesting(false)
    }

    private func readout(_ site: RadarWeatherSite) -> String {
        guard let updated = weather.radarUpdatedAt, Date().timeIntervalSince(updated) < 3600,
              let sample = weather.radarWeather.first(where: { $0.site == site }) else { return "N/A" }
        return sample.readout(for: mode)
    }
}

struct WeatherReadout: View {
    @Environment(\.consoleTypography) private var typography
    let label: String
    let value: String

    var body: some View {
        GeometryReader { geometry in
        let fit = min(1, max(0.25, (geometry.size.height - 16) / (10 * typography.scale(.secondary, dimmed: true) + 15 * typography.primary + 4)))
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .consoleFont(10 * fit, role: .secondary, weight: .bold)
                .consoleDimmed()
                .lineLimit(1).minimumScaleFactor(0.35)
            Text(value)
                .consoleFont(15 * fit, role: .primary, weight: .bold)
                .lineLimit(1)
                .minimumScaleFactor(0.35)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .overlay(Rectangle().stroke(dimPhosphor.opacity(0.9), lineWidth: 1))
    }
}

struct HourlyForecastPanel: View {
    let weather: WeatherSnapshot

    var body: some View {
        let points = weather.hourlyForecast
        VStack(spacing: 0) {
            HStack {
                Text("HOURLY // NEXT 12").consoleFont(9, role: .secondary, weight: .bold)
                Spacer(minLength: 3)
                if let first = points.first, let last = points.last {
                    Text(String(format: "%.0f° → %.0f°", first.temperature, last.temperature))
                        .consoleFont(9, role: .primary, weight: .bold)
                }
            }
            .lineLimit(1).minimumScaleFactor(0.35)
            .padding(.horizontal, 6).padding(.vertical, 5)
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
                let y = 3 + max(0, size.height - 6) * (1 - CGFloat(normalized))
                index == 0 ? temperaturePath.move(to: CGPoint(x: x, y: y)) : temperaturePath.addLine(to: CGPoint(x: x, y: y))
                let rainHeight = CGFloat(point.precipitationChance) * min(24, size.height * 0.28)
                let bar = CGRect(x: max(0, x - 2), y: max(0, size.height - rainHeight), width: 4, height: rainHeight)
                context.fill(Path(bar), with: .color(dimPhosphor.opacity(0.85)))
            }
            context.stroke(temperaturePath, with: .color(phosphor), lineWidth: 1.7)
        }
            .clipped()
            HStack {
                ForEach(hourMarkers, id: \.time) { point in
                    Text(hourLabel(point.time))
                    if point.time != hourMarkers.last?.time { Spacer() }
                }
            }
            .consoleFont(7, role: .secondary, weight: .bold, fallback: .other)
            .lineLimit(1).minimumScaleFactor(0.35)
            .consoleDimmed()
            .padding(.horizontal, 6)
            .padding(.bottom, 3)
        }
        .overlay(Rectangle().stroke(dimPhosphor.opacity(0.9), lineWidth: 1.2))
    }

    private var hourMarkers: [HourlyWeatherPoint] {
        let points = weather.hourlyForecast
        guard !points.isEmpty else { return [] }
        return stride(from: 0, to: points.count, by: 3).map { points[$0] }
    }
}

struct DailyForecastPanel: View {
    @Environment(\.consoleTypography) private var typography
    let days: [DailyWeatherPoint]

    var body: some View {
        GeometryReader { geometry in
        let rowHeight = max(1, (geometry.size.height - 18 - 9 * typography.scale(.secondary, dimmed: true)) / Double(max(1, days.count)))
        let fit = min(1, max(0.2, (rowHeight - 3) / max(13 * typography.primary, 8.5 * typography.scale(.secondary, fallback: .other))))
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                Text("DAILY OUTLOOK // \(days.count) DAYS")
                Spacer()
                Text("LOW").frame(width: 52, alignment: .trailing)
                Text("HIGH").frame(width: 52, alignment: .trailing)
                Text("RAIN").frame(width: 68, alignment: .trailing)
            }
            .consoleFont(9, role: .secondary, weight: .bold)
            .lineLimit(1).minimumScaleFactor(0.25)
            .consoleDimmed()
            .padding(.bottom, 2)

            if days.isEmpty {
                Text("AWAITING DAILY FORECAST")
                    .consoleFont(9, role: .secondary, weight: .bold, fallback: .other)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    HStack(spacing: 6) {
                        Text(index == 0 ? "TODAY" : dayLabel(day.date))
                            .frame(width: 45, alignment: .leading)
                        Text(day.condition)
                            .consoleFont(8.5 * fit, role: .secondary, weight: .bold, fallback: .other)
                            .lineLimit(1)
                            .minimumScaleFactor(0.35)
                        Spacer(minLength: 3)
                        Text(String(format: "%.0f°", day.low))
                            .consoleFont(13 * fit, role: .primary, weight: .bold)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.35)
                            .frame(width: 52, alignment: .trailing)
                        Text(String(format: "%.0f°", day.high))
                            .consoleFont(13 * fit, role: .primary, weight: .bold)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.35)
                            .frame(width: 52, alignment: .trailing)
                        HStack(spacing: 2) {
                            ForEach(0..<5, id: \.self) { segment in
                                Rectangle()
                                    .fill(Double(segment) / 5 < day.precipitationChance ? phosphor : dimPhosphor)
                                    .frame(width: 7, height: 7)
                            }
                        }
                        Text(String(format: "%2.0f", day.precipitationChance * 100))
                            .consoleFont(8.5 * fit, role: .primary, weight: .bold, fallback: .other)
                            .frame(width: 23, alignment: .trailing)
                    }
                    .consoleFont(8.5 * fit, role: .secondary, weight: .bold, fallback: .other)
                    .lineLimit(1).minimumScaleFactor(0.35)
                    .frame(maxHeight: .infinity)
                    if index < days.count - 1 {
                        Rectangle().fill(dimPhosphor.opacity(0.35)).frame(height: 0.5)
                    }
                }
            }
        }
        .padding(7)
        }
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
    @Environment(\.consoleTypography) private var typography
    let snapshot: TelemetrySnapshot
    let cpuHistory: [Double]
    let memoryHistory: [Double]
    let networkHistory: [Double]
    var gpuHistory: [Double?] = []
    let time: Double
    @Environment(\.consoleGPUVectors) private var gpuVectors
    @AppStorage("DockTelemetry.signalGridMetric") private var gridMetricRaw = SignalGridMetric.cpu.rawValue
    @AppStorage("DockTelemetry.signalDisplayMode") private var signalDisplayModeRaw = SignalDisplayMode.spinning.rawValue
    @AppStorage("DockTelemetry.signalSynthwaveGrid") private var synthwaveGrid = false
    @AppStorage("DockTelemetry.signalGridAnimationEnabled") private var gridAnimationEnabled = true

    private var gridMetricValue: Double {
        switch SignalGridMetric(rawValue: gridMetricRaw) ?? .cpu {
        case .cpu:
            snapshot.cpu
        case .gpu:
            snapshot.gpu ?? 0
        case .network:
            min(1, (snapshot.networkIn + snapshot.networkOut) / 12_000_000)
        case .disk:
            snapshot.disk
        }
    }

    private var gridMetricLabel: String {
        let metric = SignalGridMetric(rawValue: gridMetricRaw) ?? .cpu
        switch metric {
        case .gpu where snapshot.gpu == nil:
            return "GRID GPU N/A"
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
                if gpuVectors {
                    GeometryReader { proxy in
                        Rectangle().stroke(dimPhosphor, lineWidth: 1)
                        if signalDisplayModeRaw == SignalDisplayMode.gpuHorizon.rawValue && !gpuHistory.contains(where: { $0 != nil }) {
                            let height = min(proxy.size.height * 0.26, proxy.size.height * 0.32 - min(proxy.size.height * 0.30, max(42, 13 * max(typography.primary, typography.secondary) + 26)))
                            Text("GPU DATA UNAVAILABLE")
                                .consoleFont(11, role: .secondary, weight: .bold, fallback: .other)
                                .position(x: proxy.size.width / 2, y: proxy.size.height * 0.32 - max(0, height) / 2)
                        }
                    }
                } else {
                ConsoleTimeline(
                    time: time,
                    interval: signalDisplayModeRaw == SignalDisplayMode.gpuHorizon.rawValue && !(synthwaveGrid && gridAnimationEnabled) ? 1 : nil
                ) { tick in
                    SignalScope(time: tick, metricValue: gridMetricValue, gpuHistory: gpuHistory)
                }
                }
            }
            LayoutModuleContainer(scene: .signal, module: "signalHeader") {
                HStack {
                    SignalChannelField(label: "GRID", value: gridMetricLabel.replacingOccurrences(of: "GRID ", with: ""))
                    Spacer()
                    SignalChannelField(label: "CH B", value: snapshot.gpu.map { String(format: "GPU %03.0f%%", $0 * 100) } ?? "GPU N/A")
                    Spacer()
                    if signalDisplayModeRaw == SignalDisplayMode.gpuHorizon.rawValue {
                        Text("GPU // 96 SEC")
                    } else {
                        ConsoleTimeline(time: time, interval: 0.25) { tick in
                            Text("PHASE \(Int(tick*22)%360)°")
                        }
                    }
                }
                .consoleFont(13, role: .secondary, weight: .bold, fallback: .other)
                .lineLimit(1).minimumScaleFactor(0.6)
            }
            LayoutModuleContainer(scene: .signal, module: "cpuTrace") { MiniTrace(label: "CPU", values: cpuHistory, value: String(format: "%.0f%%", snapshot.cpu * 100)) }
            LayoutModuleContainer(scene: .signal, module: "memoryTrace") { MiniTrace(label: "MEMORY", values: memoryHistory, value: String(format: "%.0f%%", snapshot.memory * 100)) }
            LayoutModuleContainer(scene: .signal, module: "networkTrace") { MiniTrace(label: "NETWORK", values: networkHistory) }
            LayoutModuleContainer(scene: .signal, module: "ioReadout") { Readout(label: "I/O RX / TX", value: "\(byteRate(snapshot.networkIn)) / \(byteRate(snapshot.networkOut))") }
        }
    }
}

private struct SignalChannelField: View {
    let label: String
    let value: String
    var body: some View {
        HStack(spacing: 7) {
            Text(label).consoleFont(13, role: .secondary, weight: .bold)
            Text(value).consoleFont(13, role: .primary, weight: .bold)
        }
    }
}

/// Own the fast-moving grid state inside the scope so it cannot invalidate data modules.
private struct SignalScope: View {
    @Environment(\.consoleTypography) private var typography
    let time: Double
    let metricValue: Double
    let gpuHistory: [Double?]
    @AppStorage("DockTelemetry.signalDisplayMode") private var signalDisplayModeRaw = SignalDisplayMode.spinning.rawValue
    @AppStorage("DockTelemetry.signalSynthwaveGrid") private var synthwaveGrid = false
    @AppStorage("DockTelemetry.signalGridAnimationEnabled") private var gridAnimationEnabled = true
    @AppStorage("DockTelemetry.signalGridPattern") private var gridPatternRaw = SignalGridPattern.recede.rawValue
    @AppStorage("DockTelemetry.signalGridResponse") private var gridResponseRaw = SignalGridResponse.medium.rawValue
    @State private var motion = SignalGridMotion()
    @Environment(\.consoleAnimationPaused) private var paused

    var body: some View {
        let frame = motion.sample(at: time)
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.stroke(Path(rect), with: .color(dimPhosphor), lineWidth: 1)
            if synthwaveGrid {
                drawSynthwaveGrid(
                    context: &context, rect: rect,
                    travelPhase: frame.travel, wavePhase: frame.wave,
                    metricValue: frame.metric,
                    pattern: SignalGridPattern(rawValue: gridPatternRaw) ?? .recede,
                    responseGain: (SignalGridResponse(rawValue: gridResponseRaw) ?? .medium).multiplier
                )
            } else {
                drawGrid(context: &context, size: rect.size, columns: 16, rows: 8, origin: rect.origin, strength: 0.72)
            }
            if signalDisplayModeRaw == SignalDisplayMode.gpuHorizon.rawValue {
                drawGPUHorizon(context: &context, rect: rect, history: gpuHistory, typography: typography)
            } else {
            let amplitude = 108 + sin(time * 0.19) * 7
            let continuousPhase = sin(time * 0.16) * 0.72
            for echo in stride(from: 3, through: 0, by: -1) {
                var path = Path()
                let lag = Double(echo) * 0.025
                for i in 0...360 {
                    let t = Double(i) / 360 * Double.pi * 2
                    let x = rect.midX + CGFloat(sin(t * 3.04 + time * 0.82 - lag)) * amplitude * 2.05
                    let y = rect.midY + CGFloat(sin(t * 4.07 + time * 0.61 + continuousPhase - lag)) * amplitude
                    i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
                }
                let opacity = echo == 0 ? 1.0 : 0.11 + Double(3 - echo) * 0.075
                context.stroke(path, with: .color(phosphor.opacity(opacity)), lineWidth: echo == 0 ? 1.5 : 0.8)
            }
            }
        }
        .onAppear {
            motion = SignalGridMotion(time: time, metric: metricValue, response: response, animated: gridAnimationEnabled && !paused)
        }
        .onChange(of: metricValue) {
            updateMotion()
        }
        .onChange(of: gridResponseRaw) { updateMotion() }
        .onChange(of: gridAnimationEnabled) { updateMotion() }
        .onChange(of: paused) { updateMotion() }
    }

    private var response: SignalGridResponse { SignalGridResponse(rawValue: gridResponseRaw) ?? .medium }
    private func updateMotion() {
        motion.retarget(at: time, metric: metricValue, response: response, animated: gridAnimationEnabled && !paused)
    }
}

private func drawGPUHorizon(context: inout GraphicsContext, rect: CGRect, history: [Double?], typography: ConsoleTypography) {
    let horizon = rect.minY + rect.height * 0.32
    // Keep full-load peaks below the channel header, including large typography.
    let topInset = min(rect.height * 0.30, max(42, 13 * max(typography.primary, typography.secondary) + 26))
    let height = max(0, min(rect.height * 0.26, horizon - rect.minY - topInset))
    let plot = CGRect(x: rect.minX, y: horizon - height, width: rect.width, height: height)
    let segments = UsageHistoryGeometry.segments(history, in: plot)
    for segment in segments {
        guard let first = segment.first, let last = segment.last else { continue }
        var trace = Path()
        for (index, point) in segment.enumerated() {
            index == 0 ? trace.move(to: point) : trace.addLine(to: point)
        }
        var fill = trace
        fill.addLine(to: CGPoint(x: last.x, y: horizon))
        fill.addLine(to: CGPoint(x: first.x, y: horizon))
        fill.closeSubpath()
        context.fill(fill, with: .linearGradient(
            Gradient(colors: [phosphor.opacity(0.30), dimPhosphor.opacity(0.04)]),
            startPoint: CGPoint(x: rect.midX, y: horizon - height),
            endPoint: CGPoint(x: rect.midX, y: horizon)
        ))
        if segment.count == 1 {
            context.fill(Path(ellipseIn: CGRect(x: first.x - 2, y: first.y - 2, width: 4, height: 4)), with: .color(phosphor))
        } else {
            context.stroke(trace, with: .color(phosphor.opacity(0.14)), lineWidth: 6)
            context.stroke(trace, with: .color(phosphor), lineWidth: 1.8)
        }
    }
    if segments.isEmpty {
        context.draw(Text("GPU DATA UNAVAILABLE").font(typography.font(11, role: .secondary, weight: .bold, fallback: .other)).foregroundStyle(phosphor), at: CGPoint(x: rect.midX, y: horizon - height / 2))
    }
    var base = Path()
    base.move(to: CGPoint(x: rect.minX, y: horizon))
    base.addLine(to: CGPoint(x: rect.maxX, y: horizon))
    context.stroke(base, with: .color(dimPhosphor), lineWidth: 1.3)
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

    var longitudinal = Path()
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
        longitudinal.addPath(path)
    }
    context.stroke(longitudinal, with: .color(dimPhosphor.opacity(0.78)), lineWidth: 0.9)

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
        .consoleFont(12, role: .secondary, weight: .bold, fallback: .other)
    }
}

struct MiniTrace: View {
    let label: String
    let values: [Double]
    var value: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(label)
                    .consoleFont(11, role: .secondary, weight: .bold)
                    .lineLimit(1).minimumScaleFactor(0.45)
                Spacer(minLength: 0)
                if let value {
                    Text(value)
                        .consoleFont(12, role: .primary, weight: .bold)
                        .lineLimit(1).minimumScaleFactor(0.45)
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
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
        }
        .overlay(Rectangle().stroke(dimPhosphor.opacity(0.9), lineWidth: 1.2))
        .clipped()
    }
}

struct CRTOverlay: View {
    let scanlineStrength: Double
    let noiseStrength: Double
    let vhsTrackingEnabled: Bool
    let trackingLine1Thickness: Double
    let trackingLine2Thickness: Double
    let time: Double
    var tubeStrength: Double = 0
    @Environment(\.consoleAnimationEnabled) private var animated
    @Environment(\.consoleAnimationPaused) private var paused
    @Environment(\.consoleFrameRate) private var frameRate

    @ViewBuilder
    var body: some View {
        if CRTDisplay.isAvailable {
            CRTDisplay(
                scanlines: scanlineStrength, noise: noiseStrength,
                tracking: vhsTrackingEnabled,
                firstThickness: trackingLine1Thickness, secondThickness: trackingLine2Thickness,
                tubeStrength: tubeStrength, color: phosphor, paused: paused || !animated, frameRate: frameRate
            )
            .allowsHitTesting(false)
        } else {
            staticOverlay
                .modifier(CRTTubeEffect(enabled: tubeStrength > 0.001, strength: tubeStrength, opaqueBackground: false))
        }
    }

    private var staticOverlay: some View {
        ZStack {
            if scanlineStrength > 0.001 {
                Canvas { context, size in
                    let darkOpacity = 0.12 + scanlineStrength * 0.60
                    let highlightOpacity = 0.025 + scanlineStrength * 0.14
                    var darkLines = Path()
                    var highlights = Path()
                    for y in stride(from: 1.0, through: size.height, by: 4) {
                        darkLines.move(to: CGPoint(x: 0, y: y))
                        darkLines.addLine(to: CGPoint(x: size.width, y: y))
                        highlights.move(to: CGPoint(x: 0, y: y + 1.35))
                        highlights.addLine(to: CGPoint(x: size.width, y: y + 1.35))
                    }
                    context.stroke(darkLines, with: .color(.black.opacity(darkOpacity)), lineWidth: 1.15)
                    context.stroke(highlights, with: .color(phosphor.opacity(highlightOpacity)), lineWidth: 0.55)
                }
            }
            if noiseStrength > 0.001 {
                ConsoleTimeline(time: time, interval: 1.0 / 14.0) { tick in
                    Canvas { context, size in
                        let frames = CRTNoiseTextures.frames
                        guard !frames.isEmpty else { return }
                        let frame = frames[abs(Int(tick * 14)) % frames.count]
                        context.opacity = 0.035 + noiseStrength * 0.26
                        let rect = CGRect(origin: .zero, size: size)
                        var grain = context.resolve(Image(decorative: frame.phosphor, scale: 1))
                        grain.shading = .color(phosphor)
                        context.draw(grain, in: rect)
                        context.draw(Image(decorative: frame.white, scale: 1), in: rect)
                    }
                }
            }
            if vhsTrackingEnabled {
                ConsoleTimeline(time: time) { time in
                  Canvas { context, size in
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

func drawGrid(
    context: inout GraphicsContext,
    size: CGSize,
    columns: Int,
    rows: Int,
    origin: CGPoint = .zero,
    strength: Double = 0.62
) {
    var grid = Path()
    for column in 0...columns {
        let x = origin.x + size.width * CGFloat(column) / CGFloat(columns)
        grid.move(to: CGPoint(x: x, y: origin.y))
        grid.addLine(to: CGPoint(x: x, y: origin.y + size.height))
    }
    for row in 0...rows {
        let y = origin.y + size.height * CGFloat(row) / CGFloat(rows)
        grid.move(to: CGPoint(x: origin.x, y: y))
        grid.addLine(to: CGPoint(x: origin.x + size.width, y: y))
    }
    context.stroke(grid, with: .color(dimPhosphor.opacity(strength)), lineWidth: 0.8)
}

private func point(center: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
    let radians = angle * .pi / 180
    return CGPoint(x: center.x + CGFloat(cos(radians)) * radius, y: center.y + CGFloat(sin(radians)) * radius)
}
