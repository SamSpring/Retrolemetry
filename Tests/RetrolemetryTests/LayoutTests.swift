import XCTest
@testable import Retrolemetry

final class LayoutTests: XCTestCase {
    func testMetricsDefaultsFitWithoutOverlap() {
        let modules = LayoutDefaults.modules(for: .fullMetrics)
        let frames = LayoutDefaults.frames(for: .fullMetrics)
        XCTAssertEqual(modules.count, 13)
        XCTAssertEqual(Set(modules.map(\.id)).count, modules.count)
        XCTAssertEqual(Set(modules.map(\.id)), Set(frames.keys))
        for (id, frame) in frames {
            XCTAssertTrue(frame.visible, id)
            XCTAssertGreaterThanOrEqual(frame.x, 15, id)
            XCTAssertGreaterThanOrEqual(frame.y, 45, id)
            XCTAssertLessThanOrEqual(frame.rect.maxX, 945, id)
            XCTAssertLessThanOrEqual(frame.rect.maxY, 505, id)
            for (otherID, other) in frames where otherID != id {
                XCTAssertFalse(frame.rect.intersects(other.rect), "\(id) overlaps \(otherID)")
            }
        }
    }

    func testCustomFramesAndVisibilityArePreserved() {
        let custom = ModuleFrame(x: 35, y: 90, width: 340, height: 220, visible: false)
        let merged = LayoutDefaults.merging(["graphCPU": custom], for: .fullMetrics)
        XCTAssertEqual(merged["graphCPU"], custom)
        for id in ["metricGPU", "metricPower", "graphGPU"] { XCTAssertEqual(merged[id]?.visible, false) }
    }

    func testUntouchedLegacyDefaultsCanAdoptExpandedLayout() {
        let old = ModuleFrame(x: 28, y: 55, width: 217, height: 116)
        let merged = LayoutDefaults.merging(["metricCPU": old], for: .fullMetrics)
        XCTAssertEqual(merged, LayoutDefaults.frames(for: .fullMetrics))
    }

    func testNewModuleChoicesSurviveReload() {
        var saved = LayoutDefaults.frames(for: .fullMetrics)
        saved["metricGPU"]?.visible = false
        saved["graphGPU"]?.x = 320
        XCTAssertEqual(LayoutDefaults.merging(saved, for: .fullMetrics), saved)
    }

    func testUnrelatedSceneFramesAndPickerSelectionsArePreserved() {
        let custom = ModuleFrame(x: 30, y: 70, width: 370, height: 370)
        XCTAssertEqual(LayoutDefaults.merging(["radar": custom], for: .radar)["radar"], custom)
        XCTAssertEqual(SignalDisplayMode(rawValue: "memoryHorizon"), .gpuHorizon)
        XCTAssertEqual(SignalGridMetric(rawValue: "gpuProxy"), .gpu)
    }
}
