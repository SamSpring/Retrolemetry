import AppKit
import SwiftUI

/// The console window owns this state; hiding or sleeping must stop its animation clocks.
@MainActor
final class ConsoleRenderState: ObservableObject {
    @Published var isRendering = false
}
enum ConsoleAnimationEpoch {
    static let uptime = ProcessInfo.processInfo.systemUptime
}

/// The native and SwiftUI layers share one start time and easing curve.
struct ConsoleTransitionMotion {
    let start: Double
    let duration: Double
    let style: SceneTransitionStyle
    let direction: Int
    let incoming: Bool

    func uniforms(at time: Double) -> SIMD4<Float> {
        let t = min(1, max(0, (time - start) / duration))
        return SIMD4(Float(Self.ease(t)), Float(SceneTransitionStyle.allCases.firstIndex(of: style) ?? 0), incoming ? 1 : 0, direction >= 0 ? 1 : -1)
    }
    static func ease(_ t: Double) -> Double {
        // Invert the x component of cubic(0.30, 0.02, 0.18, 1).
        func curve(_ u: Double, _ a: Double, _ b: Double) -> Double {
            3 * (1-u) * (1-u) * u * a + 3 * (1-u) * u * u * b + u*u*u
        }
        var low = 0.0, high = 1.0
        for _ in 0..<20 {
            let middle = (low + high) / 2
            if curve(middle, 0.30, 0.18) < t { low = middle } else { high = middle }
        }
        return t <= 0 ? 0 : t >= 1 ? 1 : curve((low+high)/2, 0.02, 1)
    }
}

/// Interpolate once and hand the exact same progress to text masks and native vectors.
struct ConsoleTransitionSurface<Content: View>: View, Animatable {
    var progress: CGFloat
    @ViewBuilder let content: (CGFloat) -> Content
    var animatableData: CGFloat { get { progress } set { progress = newValue } }
    var body: some View { content(progress).transaction { $0.animation = nil } }
}

private struct ConsoleAnimationEnabledKey: EnvironmentKey {
    static let defaultValue = false
}

private struct ConsoleAnimationPausedKey: EnvironmentKey {
    static let defaultValue = false
}

private struct ConsoleFrameRateKey: EnvironmentKey {
    static let defaultValue = 30.0
}
private struct ConsoleGPUVectorsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var consoleGPUVectors: Bool {
        get { self[ConsoleGPUVectorsKey.self] }
        set { self[ConsoleGPUVectorsKey.self] = newValue }
    }
    var consoleAnimationEnabled: Bool {
        get { self[ConsoleAnimationEnabledKey.self] }
        set { self[ConsoleAnimationEnabledKey.self] = newValue }
    }
    var consoleAnimationPaused: Bool {
        get { self[ConsoleAnimationPausedKey.self] }
        set { self[ConsoleAnimationPausedKey.self] = newValue }
    }
    var consoleFrameRate: Double {
        get { self[ConsoleFrameRateKey.self] }
        set { self[ConsoleFrameRateKey.self] = newValue }
    }
}

/// Put a clock around the moving element, never around a whole scene of text and graphs.
/// Layout previews keep their supplied time and do not create an animation clock.
struct ConsoleTimeline<Content: View>: View {
    let time: Double
    var interval: Double? = nil
    @ViewBuilder let content: (Double) -> Content
    @Environment(\.consoleAnimationEnabled) private var enabled
    @Environment(\.consoleAnimationPaused) private var paused
    @Environment(\.consoleFrameRate) private var frameRate

    var body: some View {
        if enabled {
            TimelineView(.animation(minimumInterval: interval ?? 1 / max(15, min(60, frameRate)), paused: paused)) { tick in
                content(tick.date.timeIntervalSinceReferenceDate)
            }
        } else {
            content(time)
        }
    }
}

enum CRTTubeGeometry {
    static func sourcePoint(for point: CGPoint, size: CGSize, strength: Double) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return point }
        let x = point.x / size.width * 2 - 1
        let y = point.y / size.height * 2 - 1
        let amount = CGFloat(min(1, max(0, strength))) * 0.18
        return CGPoint(
            x: (x * (1 + amount * y * y) + 1) * size.width / 2,
            y: (y * (1 + amount * x * x) + 1) * size.height / 2
        )
    }
}

/// Integrate the smoothed metric analytically. Animation reads this value without
/// writing SwiftUI state every frame (which used to redraw the scope twice).
struct SignalGridMotion {
    struct Frame {
        var travel = 0.0
        var wave = 0.0
        var metric = 0.0
    }
    private var anchor = Frame()
    private var time = 0.0
    private var target = 0.0
    private var response = SignalGridResponse.medium
    private var animated = false

    init() {}
    init(time: Double, metric: Double, response: SignalGridResponse, animated: Bool) {
        self.time = time
        anchor.metric = metric
        target = metric
        self.response = response
        self.animated = animated
    }

    func sample(at now: Double) -> Frame {
        guard animated else { return anchor }
        let elapsed = max(0, now - time)
        let decay = exp(-elapsed * response.smoothingRate)
        let integral = target * elapsed + (anchor.metric - target) * (1 - decay) / response.smoothingRate
        return Frame(
            travel: anchor.travel + (0.020 * elapsed + integral * 0.12) * response.multiplier,
            wave: anchor.wave + (0.25 * elapsed + integral * 1.30) * response.multiplier,
            metric: target + (anchor.metric - target) * decay
        )
    }

    mutating func retarget(at now: Double, metric: Double, response: SignalGridResponse, animated: Bool) {
        anchor = sample(at: now)
        time = now
        target = metric
        if !animated { anchor.metric = metric }
        self.response = response
        self.animated = animated
    }
}

enum ConsoleMetalLibrary {
    // The packager compiles this once. Loading the GPU library never happens per frame.
    static let url: URL? = {
        let resource = Bundle.main.url(forResource: "default", withExtension: "metallib")
        let sidecar = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("default.metallib")
        guard let url = [resource, sidecar].compactMap({ $0 }).first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else { return nil }
        return url
    }()
    static let library: ShaderLibrary? = url.map { ShaderLibrary(url: $0) }
}

struct CRTTubeEffect: ViewModifier {
    static var isAvailable: Bool { ConsoleMetalLibrary.library != nil }
    let enabled: Bool
    let strength: Double
    var size = CGSize(width: 960, height: 540)
    var opaqueBackground = true

    @ViewBuilder
    func body(content: Content) -> some View {
        if let library = ConsoleMetalLibrary.library, enabled, strength > 0.001 {
            let amount = min(1, max(0, strength))
            content
                .compositingGroup()
                .distortionEffect(
                    library.crtTube(.float2(size), .float(amount)),
                    maxSampleOffset: CGSize(width: size.width * amount * 0.09, height: size.height * amount * 0.09)
                )
                .clipped()
                .background(opaqueBackground ? Color.black : Color.clear)
        } else {
            content
        }
    }
}

/// Small reusable alpha textures replace hundreds of individual grain draws per frame.
enum CRTNoiseTextures {
    struct Frame {
        let phosphor: CGImage
        let white: CGImage
    }

    static let frames: [Frame] = (0..<12).compactMap { frame in
        func texture(white: Bool) -> CGImage? {
            guard let context = CGContext(
                data: nil, width: 960, height: 540,
                bitsPerComponent: 8, bytesPerRow: 960 * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
            ) else { return nil }
            context.setShouldAntialias(false)
            context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            for index in 0..<820 where index.isMultiple(of: 5) == white {
                let hash = (index &* 73_856_093) ^ (frame &* 19_349_663)
                let positive = hash & 0x7fff_ffff
                let x = (positive &* 37) % 960
                let y = (positive &* 91 + index &* 17) % 540
                let width = index.isMultiple(of: 7) ? 2.5 : 1.0
                context.fill(CGRect(x: Double(x), y: Double(y), width: width, height: 1))
            }
            return context.makeImage()
        }
        guard let phosphor = texture(white: false), let white = texture(white: true) else { return nil }
        return Frame(phosphor: phosphor, white: white)
    }
}
