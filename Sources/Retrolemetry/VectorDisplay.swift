import AppKit
import MetalKit
import SwiftUI

/// A tiny fixed-coordinate vector layer. Static text/telemetry stays in SwiftUI;
/// the GPU calculates line positions instead of tessellating Canvas paths at 30fps.
struct VectorConfiguration {
    var uniforms = VectorUniforms()
    var history: [Float] = Array(repeating: -1, count: 96)
    var targets: [SIMD4<Float>] = []
    var metric = 0.0
    var response = SignalGridResponse.medium
    var animated = true
    var scene: ConsoleScene
    var transition: ConsoleTransitionMotion?
    var transitionProgress: Float?
    var radarRegion: RadarRegion?

    @MainActor
    init(scene: ConsoleScene, layouts: LayoutStore, snapshot: TelemetrySnapshot,
         gpuHistory: [Double?], weather: WeatherSnapshot, tubeStrength: Double, bloom: Double, location: GlobeCoordinate? = nil) {
        self.scene = scene
        let defaults = UserDefaults.standard
        func value(_ key: String, _ fallback: Double) -> Double {
            (defaults.object(forKey: "DockTelemetry." + key) as? NSNumber)?.doubleValue ?? fallback
        }
        func color(_ color: Color) -> SIMD4<Float> {
            let c = NSColor(color).usingColorSpace(.sRGB) ?? .green
            return SIMD4(Float(c.redComponent), Float(c.greenComponent), Float(c.blueComponent), Float(c.alphaComponent))
        }
        uniforms.primary = color(phosphor)
        uniforms.secondary = color(dimPhosphor)
        uniforms.style = SIMD4(Float(scene.rawValue), Float(tubeStrength), Float(bloom), 0)
        let module: String
        switch scene {
        case .system: module = "globe"
        case .radar: module = "radar"
        case .signal: module = "scope"
        case .fullMetrics: return
        }
        let frame = layouts.frame(scene, module)
        guard frame.visible else { return }
        uniforms.rect = SIMD4(Float(frame.x), Float(frame.y), Float(frame.width), Float(frame.height))
        switch scene {
        case .system:
            uniforms.shape = SIMD4(Float(value("globeWidthCorrection", 1.10)), Float(value("globeHeightCorrection", 0.9254)), 0, 0)
            let activity = TradingRegionActivity(at: Date())
            uniforms.globe = SIMD4(activity.us ? 1 : 0, activity.europe ? 1 : 0, activity.asia ? 1 : 0, Float(GlobeCoastlines.degrees.count))
            if let location {
                uniforms.location = SIMD4(Float(location.longitude * .pi / 180), Float(location.latitude * .pi / 180), 1, 0)
            }
        case .radar:
            radarRegion = weather.radarRegion
            let mode = RadarTargetMode(rawValue: defaults.string(forKey: "DockTelemetry.radarTargetMode") ?? "") ?? .precipitation
            let modes: [RadarTargetMode] = [.precipitation, .temperature, .wind, .decorative]
            targets = radarTargets(for: weather, mode: mode).map {
                mode == .decorative ? SIMD4(Float($0.radius), Float($0.angle), Float($0.intensity), 0)
                    : SIMD4($0.mapPosition.x, $0.mapPosition.y, Float($0.intensity), Float($0.heading))
            }
            uniforms.shape = SIMD4(Float(value("radarWidthCorrection", 1.10)), Float(value("radarHeightCorrection", 0.9254)),
                                  Float(modes.firstIndex(of: mode) ?? 0), Float(value("radarTargetPulse", 1)))
            uniforms.style.w = Float(targets.count)
            uniforms.extra.z = Float(radarRegion.map { RadarMapGeometry.segments(for: $0).count } ?? 0)
            uniforms.extra.w = Float(radarRegion.map { RadarMapGeometry.countrySegmentCount(for: $0) } ?? 0)
        case .signal:
            let selected = SignalGridMetric(rawValue: defaults.string(forKey: "DockTelemetry.signalGridMetric") ?? "") ?? .cpu
            switch selected {
            case .cpu: metric = snapshot.cpu
            case .gpu: metric = snapshot.gpu ?? 0
            case .network: metric = min(1, (snapshot.networkIn + snapshot.networkOut) / 12_000_000)
            case .disk: metric = snapshot.disk
            }
            response = SignalGridResponse(rawValue: defaults.string(forKey: "DockTelemetry.signalGridResponse") ?? "") ?? .medium
            animated = value("signalGridAnimationEnabled", 1) > 0.5
            let pattern = SignalGridPattern(rawValue: defaults.string(forKey: "DockTelemetry.signalGridPattern") ?? "") ?? .recede
            uniforms.shape = SIMD4(Float(value("signalSynthwaveGrid", 0)),
                                  Float(SignalGridPattern.allCases.firstIndex(of: pattern) ?? 0),
                                  defaults.string(forKey: "DockTelemetry.signalDisplayMode") == SignalDisplayMode.gpuHorizon.rawValue ? 1 : 0,
                                  Float(response.multiplier))
            let typography = layouts.typography(for: scene)
            uniforms.extra.x = Float(max(typography.primary, typography.secondary))
            for (index, sample) in gpuHistory.suffix(96).enumerated() {
                history[index] = sample.flatMap { $0.isFinite && (0...1).contains($0) ? Float($0) : nil } ?? -1
            }
        case .fullMetrics: break
        }
    }

    var visible: Bool { uniforms.rect.z > 0 && uniforms.rect.w > 0 }
    var segmentCount: Int {
        switch scene {
        case .system: 128 + 7 * 96 + GlobeGeometry.meridianCount * 72 + 24 + GlobeCoastlines.degrees.count + 4 * 32
        case .radar: 4 * 96 + 12 + 16 + Int(uniforms.extra.z) + targets.count * 32
        case .signal: (uniforms.shape.x > 0.5 ? 21 * 64 + 16 * 80 + 1 : 26) + (uniforms.shape.z > 0.5 ? 287 : 4 * 360)
        case .fullMetrics: 0
        }
    }
}

struct VectorUniforms {
    var rect = SIMD4<Float>(repeating: 0)
    var primary = SIMD4<Float>(0.34, 1, 0.43, 1)
    var secondary = SIMD4<Float>(0.34, 1, 0.43, 0.48)
    var style = SIMD4<Float>(repeating: 0) // scene, tube, bloom, target count
    var shape = SIMD4<Float>(1, 1, 0, 0)
    var motion = SIMD4<Float>(repeating: 0) // time, travel, wave, metric
    var extra = SIMD4<Float>(1, 0, 0, 0)
    var globe = SIMD4<Float>(repeating: 0)
    var location = SIMD4<Float>(repeating: 0)
    var transition = SIMD4<Float>(-1, 0, 1, 1)
}

struct VectorDisplay: NSViewRepresentable {
    let configuration: VectorConfiguration
    let paused: Bool
    let frameRate: Double
    static var isAvailable: Bool { VectorGPU.shared != nil }

    func makeCoordinator() -> Renderer { Renderer() }
    func makeNSView(context: Context) -> MTKView {
        let view = VectorMetalView(frame: .zero, device: VectorGPU.shared?.device)
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.autoResizeDrawable = false
        // Retain crisp curves at Retina density, but never allocate a 4K vector buffer.
        view.drawableSize = CGSize(width: 1920, height: 1080)
        view.layer?.isOpaque = false
        view.delegate = context.coordinator
        updateNSView(view, context: context)
        return view
    }
    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.update(configuration, paused: paused)
        let moves = configuration.transition != nil || configuration.scene != .signal || configuration.uniforms.shape.z < 0.5
            || (configuration.uniforms.shape.x > 0.5 && configuration.animated)
        let fps = moves ? max(15, min(60, Int(frameRate))) : 1
        if view.preferredFramesPerSecond != fps { view.preferredFramesPerSecond = fps }
        let shouldPause = paused || !configuration.visible || !moves || configuration.transitionProgress != nil
        if view.isPaused != shouldPause { view.isPaused = shouldPause }
        if shouldPause { view.draw() }
    }
    static func dismantleNSView(_ view: MTKView, coordinator: Renderer) {
        view.isPaused = true
        view.delegate = nil
    }

    final class Renderer: NSObject, MTKViewDelegate {
        private var configuration: VectorConfiguration?
        private let inFlight = DispatchSemaphore(value: 2)
        private var motion = SignalGridMotion()
        private var wasPaused = false

        func update(_ next: VectorConfiguration, paused: Bool) {
            let now = ProcessInfo.processInfo.systemUptime
            if configuration?.scene != next.scene {
                motion = SignalGridMotion(time: now, metric: next.metric, response: next.response, animated: next.animated && !paused)
            } else if configuration?.metric != next.metric || configuration?.response != next.response || configuration?.animated != next.animated || wasPaused != paused {
                motion.retarget(at: now, metric: next.metric, response: next.response, animated: next.animated && !paused)
            }
            wasPaused = paused
            configuration = next
        }
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        func draw(in view: MTKView) {
            guard var c = configuration, let gpu = VectorGPU.shared,
                  inFlight.wait(timeout: .now()) == .success else { return }
            guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
                  let command = gpu.queue.makeCommandBuffer(),
                  let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
                inFlight.signal(); return
            }
            if c.visible {
                let now = ProcessInfo.processInfo.systemUptime
                let frame = motion.sample(at: now)
                let elapsed = now - ConsoleAnimationEpoch.uptime
                c.uniforms.motion = SIMD4(
                    Float(elapsed.truncatingRemainder(dividingBy: 2 * .pi * 100)),
                    Float(frame.travel.truncatingRemainder(dividingBy: 20)),
                    Float(frame.wave.truncatingRemainder(dividingBy: 2 * .pi * 100)),
                    Float(frame.metric)
                )
                c.uniforms.extra.y = Float((elapsed * 42).truncatingRemainder(dividingBy: 360))
                c.uniforms.transition = c.transition?.uniforms(at: now) ?? SIMD4(-1, 0, 1, 1)
                if let progress = c.transitionProgress { c.uniforms.transition.x = progress }
                encoder.setRenderPipelineState(gpu.pipeline)
                encoder.setVertexBytes(&c.uniforms, length: MemoryLayout<VectorUniforms>.stride, index: 0)
                c.history.withUnsafeBytes { encoder.setVertexBytes($0.baseAddress!, length: $0.count, index: 1) }
                encoder.setVertexBuffer(gpu.coastlines, offset: 0, index: 3)
                encoder.setVertexBuffer(gpu.radarMaps[c.radarRegion ?? .israel], offset: 0, index: 4)
                let segments = c.segmentCount
                if c.targets.isEmpty {
                    var empty = SIMD4<Float>(repeating: 0)
                    encoder.setVertexBytes(&empty, length: MemoryLayout<SIMD4<Float>>.stride, index: 2)
                } else {
                    c.targets.withUnsafeBytes { encoder.setVertexBytes($0.baseAddress!, length: $0.count, index: 2) }
                }
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: segments * 6, instanceCount: c.uniforms.style.z > 0 ? 3 : 1)
            }
            encoder.endEncoding()
            command.present(drawable)
            let semaphore = inFlight
            command.addCompletedHandler { _ in semaphore.signal() }
            command.commit()
        }
    }
}

private final class VectorMetalView: MTKView {
    override func layout() {
        super.layout()
        if isPaused, bounds.width > 0, bounds.height > 0 { draw() }
    }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class VectorGPU {
    static let shared: VectorGPU? = {
        guard let device = MTLCreateSystemDefaultDevice(), let url = ConsoleMetalLibrary.url,
              let library = try? device.makeLibrary(URL: url),
              let vertex = library.makeFunction(name: "consoleVectorVertex"),
              let fragment = library.makeFunction(name: "consoleVectorFragment"),
              let queue = device.makeCommandQueue(),
              let coastlines = GlobeGeometry.coastlines.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }) else { return nil }
        var radarMaps: [RadarRegion: MTLBuffer] = [:]
        for region in RadarRegion.allCases {
            guard let map = RadarMapGeometry.segments(for: region).withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }) else { return nil }
            radarMaps[region] = map
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex; descriptor.fragmentFunction = fragment
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = .bgra8Unorm
        attachment.isBlendingEnabled = true
        attachment.sourceRGBBlendFactor = .one; attachment.sourceAlphaBlendFactor = .one
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha; attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        return VectorGPU(device: device, queue: queue, pipeline: pipeline, coastlines: coastlines, radarMaps: radarMaps)
    }()
    let device: MTLDevice
    let queue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState
    let coastlines: MTLBuffer
    let radarMaps: [RadarRegion: MTLBuffer]
    private init(device: MTLDevice, queue: MTLCommandQueue, pipeline: MTLRenderPipelineState, coastlines: MTLBuffer, radarMaps: [RadarRegion: MTLBuffer]) {
        self.device = device; self.queue = queue; self.pipeline = pipeline
        self.coastlines = coastlines
        self.radarMaps = radarMaps
    }
}
