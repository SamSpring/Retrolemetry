import AppKit
import SwiftUI
import Combine

private var mono: Font { consoleFont(14, weight: .medium) }

enum ConsoleScene: Int, CaseIterable {
    case system, radar, signal, fullMetrics

    var title: String {
        switch self {
        case .system: "SYSTEM TELEMETRY"
        case .radar: "SECTOR SCAN"
        case .signal: "SIGNAL ANALYSIS"
        case .fullMetrics: "LIVE SYSTEM METRICS"
        }
    }
}

struct ConsoleView: View {
    @StateObject private var telemetry = TelemetryModel()
    @StateObject private var weather = WeatherModel()
    @AppStorage("DockTelemetry.cycleDuration") private var cycleDuration = 24.0
    @AppStorage("DockTelemetry.automaticCycleEnabled") private var automaticCycleEnabled = true
    @AppStorage("DockTelemetry.crtEnabled") private var crtEnabled = true
    @AppStorage("DockTelemetry.bloomStrength") private var bloomStrength = 0.72
    @AppStorage("DockTelemetry.scanlineStrength") private var scanlineStrength = 0.22
    @AppStorage("DockTelemetry.noiseStrength") private var noiseStrength = 0.32
    @AppStorage("DockTelemetry.vhsTrackingEnabled") private var vhsTrackingEnabled = true
    @AppStorage("DockTelemetry.phosphorBackgroundTint") private var phosphorBackgroundTint = 0.12
    @AppStorage("DockTelemetry.visualStyle") private var visualStyleRaw = ConsoleStyle.phosphor.rawValue
    @ObservedObject private var layouts = LayoutStore.shared
    @State private var activeScene: ConsoleScene = .system
    @State private var nextSwitch = Date().addingTimeInterval(24)
    private let sceneClock = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        let style = ConsoleStyle(rawValue: visualStyleRaw) ?? .phosphor
        ThemeRuntime.palette = style.palette
        FontRuntime.scale = layouts.fontScale
        FontRuntime.secondaryScale = layouts.secondaryFontScale
        return TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate

            ZStack {
                ConsoleBackground(style: style, phosphorTintStrength: phosphorBackgroundTint)
                sceneView(activeScene, time: elapsed)
                    .id(activeScene)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
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
                        time: elapsed
                    )
                }
                HorizontalScrollCapture { direction in
                    moveScene(direction)
                }
                .frame(width: 960, height: 540)
            }
            .animation(.smooth(duration: 0.9), value: activeScene)
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
            nextSwitch = Date().addingTimeInterval(cycleDuration)
        }
        .onReceive(sceneClock) { now in
            guard automaticCycleEnabled, now >= nextSwitch else { return }
            withAnimation(.smooth(duration: 0.9)) {
                activeScene = ConsoleScene(rawValue: (activeScene.rawValue + 1) % ConsoleScene.allCases.count) ?? .system
            }
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
        withAnimation(.smooth(duration: 0.9)) { activeScene = scene }
        nextSwitch = Date().addingTimeInterval(cycleDuration)
    }

    private func moveScene(_ direction: Int) {
        let count = ConsoleScene.allCases.count
        let next = (activeScene.rawValue + direction + count) % count
        withAnimation(.smooth(duration: 0.9)) {
            activeScene = ConsoleScene(rawValue: next) ?? .system
        }
        nextSwitch = Date().addingTimeInterval(cycleDuration)
    }

    @ViewBuilder
    private func sceneView(_ scene: ConsoleScene, time: Double) -> some View {
        switch scene {
        case .system:
            SystemScene(snapshot: telemetry.snapshot, history: telemetry.cpuHistory, time: time)
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
                .font(consoleSecondaryFont(13, weight: .bold))
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
                .font(consoleSecondaryFont(11, weight: .semibold))
                .padding(.horizontal, 26)
                .frame(height: 30)
            }
        }
        .allowsHitTesting(false)
    }
}

struct SystemScene: View {
    let snapshot: TelemetrySnapshot
    let history: [Double]
    let time: Double

    var body: some View {
        ZStack {
            FrameChrome(title: "SYSTEM TELEMETRY", section: "SYS", time: time)
            LayoutModuleContainer(scene: .system, module: "meters") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("PRIMARY LOAD CHANNELS").font(consoleSecondaryFont(13, weight: .bold))
                    SegmentedMeter(label: "CPU", value: snapshot.cpu, detail: percent(snapshot.cpu))
                    SegmentedMeter(label: "MEM", value: snapshot.memory, detail: percent(snapshot.memory))
                    SegmentedMeter(label: "DSK", value: snapshot.disk, detail: percent(snapshot.disk))
                    SegmentedMeter(label: "NET", value: min(1, (snapshot.networkIn + snapshot.networkOut) / 12_000_000), detail: byteRate(snapshot.networkIn))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            LayoutModuleContainer(scene: .system, module: "readouts") {
                HStack(spacing: 18) {
                    Readout(label: "UPTIME", value: snapshot.uptime.compactUptime)
                    Readout(label: "NET OUT", value: byteRate(snapshot.networkOut))
                }
            }
            LayoutModuleContainer(scene: .system, module: "history") {
                LineGraph(values: history)
                    .overlay(alignment: .topLeading) {
                        Text("CPU HISTORY // 96 SEC").font(consoleSecondaryFont(11, weight: .bold)).padding(7)
                    }
            }
            LayoutModuleContainer(scene: .system, module: "globe") {
                WireGlobe(time: time)
            }
            LayoutModuleContainer(scene: .system, module: "globeStatus") {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        PulseIndicator(label: "CORE", active: true, time: time)
                        PulseIndicator(label: "I/O", active: snapshot.networkIn > 100, time: time + 0.4)
                        PulseIndicator(label: "THERM", active: true, time: time + 0.8)
                    }
                    Text(String(format: "LOAD %.2f  %.2f  %.2f", snapshot.load.0, snapshot.load.1, snapshot.load.2))
                        .font(consoleSecondaryFont(11))
                }
            }
        }
    }

    private func percent(_ value: Double) -> String { String(format: "%03.0f%%", value * 100) }
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
            Text(label).font(consoleSecondaryFont(9))
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
    @AppStorage("DockTelemetry.globeHeightCorrection") private var heightCorrection = 1.00

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) * 0.41
            let rotation = time * 0.48
            context.stroke(Path(ellipseIn: CGRect(x: center.x-radius, y: center.y-radius, width: radius*2, height: radius*2)), with: .color(phosphor), lineWidth: 1.4)

            for latitude in stride(from: -60.0, through: 60.0, by: 20) {
                let scale = CGFloat(cos(latitude * .pi / 180))
                let y = center.y + CGFloat(sin(latitude * .pi / 180)) * radius
                let rect = CGRect(x: center.x - radius * scale, y: y - radius * 0.10 * scale, width: radius * 2 * scale, height: radius * 0.20 * scale)
                context.stroke(Path(ellipseIn: rect), with: .color(dimPhosphor), lineWidth: 1)
            }
            for longitude in stride(from: 0.0, to: Double.pi, by: Double.pi / 8) {
                var front = Path()
                var back = Path()
                var frontStarted = false
                var backStarted = false
                for step in 0...72 {
                    let latitude = -Double.pi / 2 + Double(step) / 72 * Double.pi
                    let longitudeRotated = longitude + rotation
                    let x = cos(latitude) * sin(longitudeRotated)
                    let y = sin(latitude)
                    let z = cos(latitude) * cos(longitudeRotated)
                    let projected = CGPoint(x: center.x + CGFloat(x) * radius, y: center.y + CGFloat(y) * radius)
                    if z >= 0 {
                        frontStarted ? front.addLine(to: projected) : front.move(to: projected)
                        frontStarted = true; backStarted = false
                    } else {
                        backStarted ? back.addLine(to: projected) : back.move(to: projected)
                        backStarted = true; frontStarted = false
                    }
                }
                context.stroke(back, with: .color(dimPhosphor.opacity(0.34)), lineWidth: 0.7)
                context.stroke(front, with: .color(dimPhosphor.opacity(0.92)), lineWidth: 1.05)
            }

            // An asymmetric orbital marker makes the continuous rotation direction perceptible.
            let markerLongitude = rotation + 0.65
            let markerLatitude = 0.34
            let markerX = cos(markerLatitude) * sin(markerLongitude)
            let markerY = sin(markerLatitude)
            let markerZ = cos(markerLatitude) * cos(markerLongitude)
            let marker = CGPoint(x: center.x + CGFloat(markerX) * radius, y: center.y + CGFloat(markerY) * radius)
            context.fill(Path(ellipseIn: CGRect(x: marker.x - 3, y: marker.y - 3, width: 6, height: 6)), with: .color(phosphor.opacity(markerZ >= 0 ? 1 : 0)))
            var axis = Path()
            axis.move(to: CGPoint(x: center.x, y: center.y-radius-12)); axis.addLine(to: CGPoint(x: center.x, y: center.y+radius+12))
            context.stroke(axis, with: .color(phosphor.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
        }
        .scaleEffect(x: widthCorrection, y: heightCorrection, anchor: .center)
    }
}

struct RadarScene: View {
    let weather: WeatherSnapshot
    let time: Double
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
                MiniTrace(label: "TEMPERATURE // NEXT 12 HOURS", values: weather.temperatureForecast)
            }
            LayoutModuleContainer(scene: .radar, module: "precipitation") {
                MiniTrace(label: "PRECIPITATION CHANCE // NEXT 12 HOURS", values: weather.precipitationForecast)
            }
            LayoutModuleContainer(scene: .radar, module: "weatherStatus") {
                HStack {
                    Text(weather.status)
                    Spacer()
                    Text("RADAR SWEEP 042°/S")
                }
                .font(consoleSecondaryFont(10, weight: .bold))
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

struct SignalScene: View {
    let snapshot: TelemetrySnapshot
    let cpuHistory: [Double]
    let memoryHistory: [Double]
    let networkHistory: [Double]
    let time: Double
    var body: some View {
        ZStack {
            FrameChrome(title: "SIGNAL ANALYSIS", section: "SIG", time: time)
            LayoutModuleContainer(scene: .signal, module: "scope") {
              Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size)
                context.stroke(Path(rect), with: .color(dimPhosphor), lineWidth: 1)
                drawGrid(context: &context, size: rect.size, columns: 16, rows: 8, origin: rect.origin, strength: 0.72)
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
                .font(consoleSecondaryFont(13, weight: .bold))
            }
            LayoutModuleContainer(scene: .signal, module: "cpuTrace") { MiniTrace(label: "CPU", values: cpuHistory) }
            LayoutModuleContainer(scene: .signal, module: "memoryTrace") { MiniTrace(label: "MEMORY", values: memoryHistory) }
            LayoutModuleContainer(scene: .signal, module: "networkTrace") { MiniTrace(label: "NETWORK", values: networkHistory) }
            LayoutModuleContainer(scene: .signal, module: "ioReadout") { Readout(label: "I/O RX / TX", value: "\(byteRate(snapshot.networkIn)) / \(byteRate(snapshot.networkOut))") }
        }
    }
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
        .font(consoleSecondaryFont(12, weight: .bold))
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
                    let travel = (time * 72).truncatingRemainder(dividingBy: size.height + 100)
                    let y = CGFloat(travel) - 50
                    let band = CGRect(x: 0, y: y - 14, width: size.width, height: 29)
                    context.fill(
                        Path(band),
                        with: .linearGradient(
                            Gradient(colors: [.clear, .black.opacity(0.17), phosphor.opacity(0.10), .clear]),
                            startPoint: CGPoint(x: 0, y: y - 14),
                            endPoint: CGPoint(x: 0, y: y + 15)
                        )
                    )

                    var trackingEdge = Path()
                    trackingEdge.move(to: CGPoint(x: 0, y: y))
                    trackingEdge.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(trackingEdge, with: .color(phosphor.opacity(0.34)), lineWidth: 1.15)

                    let segmentFrame = Int(time * 9)
                    for index in 0..<13 {
                        let start = CGFloat((index * 137 + segmentFrame * 29) % 900)
                        let length = CGFloat(18 + (index * 23) % 96)
                        let offset = CGFloat((index % 5) - 2) * 2.5
                        context.fill(
                            Path(CGRect(x: start, y: y + offset, width: length, height: 1)),
                            with: .color(Color.white.opacity(0.10 + Double(index % 3) * 0.035))
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
