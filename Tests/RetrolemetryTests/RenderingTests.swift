import XCTest
@testable import Retrolemetry

final class RenderingTests: XCTestCase {
    func testGridAdvancesWithoutFrameStateWrites() {
        let motion = SignalGridMotion(time: 100, metric: 0.75, response: .medium, animated: true)
        let frame = motion.sample(at: 110)
        XCTAssertEqual(frame.travel, 1.1, accuracy: 0.00001)
        XCTAssertEqual(frame.wave, 12.25, accuracy: 0.00001)
        XCTAssertEqual(frame.metric, 0.75, accuracy: 0.00001)
    }

    func testGridRetargetingIsContinuousAndReflectsLoad() {
        var motion = SignalGridMotion(time: 100, metric: 0.1, response: .high, animated: true)
        let before = motion.sample(at: 102)
        motion.retarget(at: 102, metric: 0.9, response: .high, animated: true)
        let after = motion.sample(at: 102)
        XCTAssertEqual(before.travel, after.travel)
        XCTAssertEqual(before.wave, after.wave)
        XCTAssertEqual(before.metric, after.metric, accuracy: 0.0000001)
        XCTAssertGreaterThan(motion.sample(at: 103).metric, 0.89)
        XCTAssertGreaterThan(motion.sample(at: 103).wave - after.wave, before.wave / 2)
    }

    func testGridPauseDoesNotAccumulateMotion() {
        var motion = SignalGridMotion(time: 100, metric: 0.5, response: .medium, animated: true)
        motion.retarget(at: 102, metric: 0.5, response: .medium, animated: false)
        let paused = motion.sample(at: 102)
        XCTAssertEqual(motion.sample(at: 200).wave, paused.wave)
        motion.retarget(at: 200, metric: 0.5, response: .medium, animated: true)
        XCTAssertEqual(motion.sample(at: 200).wave, paused.wave)
        XCTAssertGreaterThan(motion.sample(at: 201).wave, paused.wave)
    }

    func testMetalUniformLayout() {
        XCTAssertEqual(MemoryLayout<CRTParameters>.stride, 48)
        XCTAssertEqual(MemoryLayout<CRTParameters>.alignment, 16)
        XCTAssertEqual(MemoryLayout<VectorUniforms>.stride, 160)
        XCTAssertEqual(MemoryLayout<VectorUniforms>.alignment, 16)
    }

    func testRadarMapSegmentCountsMatchNativeBuffers() async {
        await MainActor.run {
            let suite = "RetrolemetryTests.\(UUID())"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = LayoutStore(defaults: defaults)
            for region in RadarRegion.allCases {
                let configuration = VectorConfiguration(scene: .radar, layouts: store,
                    snapshot: TelemetrySnapshot(), gpuHistory: [], weather: WeatherSnapshot(radarRegion: region), tubeStrength: 0.35, bloom: 0.7)
                XCTAssertEqual(configuration.uniforms.extra.z, Float(RadarMapGeometry.segments(for: region).count))
                XCTAssertEqual(configuration.uniforms.extra.w, Float(RadarMapGeometry.countrySegmentCount(for: region)))
                XCTAssertEqual(configuration.segmentCount, 412 + RadarMapGeometry.segments(for: region).count + configuration.targets.count * 32)
            }
            XCTAssertEqual(MemoryLayout<SIMD4<Float>>.stride, 16)
        }
    }

    func testVectorHistoryPreservesZeroAndUnavailableGaps() async {
        await MainActor.run {
            let configuration = VectorConfiguration(
                scene: .signal, layouts: LayoutStore.shared,
                snapshot: TelemetrySnapshot(), gpuHistory: [0, .nan, nil, 1, 1.5],
                weather: WeatherSnapshot(), tubeStrength: 0.35, bloom: 0.8
            )
            XCTAssertEqual(Array(configuration.history.prefix(5)), [0, -1, -1, 1, -1])
            XCTAssertEqual(configuration.history.count, 96)
            let saved = LayoutStore.shared.frame(.signal, "scope")
            XCTAssertEqual(configuration.visible, saved.visible)
            if saved.visible {
                XCTAssertEqual(configuration.uniforms.rect.x, Float(saved.x))
                XCTAssertEqual(configuration.uniforms.rect.z, Float(saved.width))
            }
        }
    }
}
