import AppKit
import MetalKit
import SwiftUI

/// One small GPU pass for the moving CRT overlay. Its clock never invalidates the
/// SwiftUI scene underneath, and no full-screen grain images are retained.
struct CRTDisplay: NSViewRepresentable {
    let scanlines: Double
    let noise: Double
    let tracking: Bool
    let firstThickness: Double
    let secondThickness: Double
    let tubeStrength: Double
    let color: Color
    let paused: Bool
    let frameRate: Double

    static var isAvailable: Bool { CRTGPU.shared != nil }

    func makeCoordinator() -> Renderer { Renderer() }

    func makeNSView(context: Context) -> MTKView {
        let view = CRTMetalView(frame: .zero, device: CRTGPU.shared?.device)
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.framebufferOnly = true
        view.autoResizeDrawable = false
        // Effects are specified in the console's 960x540 coordinates, including
        // on Retina/4K monitors. Avoid a wasteful full-resolution noise buffer.
        view.drawableSize = CGSize(width: 960, height: 540)
        view.layer?.isOpaque = false
        view.delegate = context.coordinator
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        let rgb = NSColor(color).usingColorSpace(.sRGB) ?? .green
        let parameters = CRTParameters(
            color: SIMD4(Float(rgb.redComponent), Float(rgb.greenComponent), Float(rgb.blueComponent), 1),
            effects: SIMD4(Float(scanlines), Float(noise), tracking ? 1 : 0, Float(tubeStrength)),
            motion: SIMD4(0, Float(firstThickness), Float(secondThickness), 0)
        )
        let changed = parameters != context.coordinator.parameters
        context.coordinator.parameters = parameters
        let fps = tracking ? max(15, min(60, Int(frameRate))) : 14
        if view.preferredFramesPerSecond != fps { view.preferredFramesPerSecond = fps }
        let shouldPause = paused || (!tracking && noise <= 0.001)
        if view.isPaused != shouldPause { view.isPaused = shouldPause }
        if shouldPause && (changed || !context.coordinator.hasDrawn) { view.draw() }
    }

    static func dismantleNSView(_ view: MTKView, coordinator: Renderer) {
        view.isPaused = true
        view.delegate = nil
    }

    final class Renderer: NSObject, MTKViewDelegate {
        var parameters = CRTParameters()
        private(set) var hasDrawn = false
        // Prevent building a queue of obsolete frames when the Mac is busy.
        private let inFlight = DispatchSemaphore(value: 2)
        private let epoch = ProcessInfo.processInfo.systemUptime

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let gpu = CRTGPU.shared, inFlight.wait(timeout: .now()) == .success else { return }
            guard let pass = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable,
                  let command = gpu.queue.makeCommandBuffer(),
                  let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
                inFlight.signal()
                return
            }
            var uniforms = parameters
            // A short relative clock avoids precision loss from large timestamps.
            uniforms.motion.x = Float((ProcessInfo.processInfo.systemUptime - epoch).truncatingRemainder(dividingBy: 4096))
            encoder.setRenderPipelineState(gpu.pipeline)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<CRTParameters>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            command.present(drawable)
            let semaphore = inFlight
            command.addCompletedHandler { _ in semaphore.signal() }
            command.commit()
            hasDrawn = true
        }
    }
}

private final class CRTMetalView: MTKView {
    override func layout() {
        super.layout()
        if isPaused, bounds.width > 0, bounds.height > 0 { draw() }
    }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct CRTParameters: Equatable {
    var color = SIMD4<Float>(0.34, 1, 0.43, 1)
    var effects = SIMD4<Float>(0, 0, 0, 0)
    var motion = SIMD4<Float>(0, 1.5, 8, 0)
}

private final class CRTGPU {
    static let shared: CRTGPU? = {
        guard let device = MTLCreateSystemDefaultDevice(),
              let url = ConsoleMetalLibrary.url,
              let library = try? device.makeLibrary(URL: url),
              let vertex = library.makeFunction(name: "crtOverlayVertex"),
              let fragment = library.makeFunction(name: "crtOverlayFragment"),
              let queue = device.makeCommandQueue() else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        return CRTGPU(device: device, queue: queue, pipeline: pipeline)
    }()
    let device: MTLDevice
    let queue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState
    private init(device: MTLDevice, queue: MTLCommandQueue, pipeline: MTLRenderPipelineState) {
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
    }
}
