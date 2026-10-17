import XCTest
import SwiftUI
import AppKit
@testable import Retrolemetry

final class TelemetryPanelTests: XCTestCase {
    func testCompactCapacityUnitsKeepPrecisionAndUseLessSpace() {
        XCTAssertEqual(CapacitySideReading.compactAmount(32_600_000_000), "32.6GB")
        XCTAssertEqual(CapacitySideReading.compactAmount(19_200_000_000), "19.2GB")
        XCTAssertEqual(CapacitySideReading.compactAmount(2_500_000_000_000), "2.50TB")
        XCTAssertEqual(CapacitySideReading.compactAmount(nil), "N/A")
        XCTAssertEqual(CapacitySideReading.compactAmount(.nan), "N/A")
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 20, weight: .bold)]
        let compact = (CapacitySideReading.compactAmount(32_600_000_000) as NSString).size(withAttributes: attributes)
        let original = (capacityAmount(32_600_000_000) as NSString).size(withAttributes: attributes)
        XCTAssertLessThan(compact.width, original.width)
        XCTAssertFalse(CapacitySideReading.compactAmount(19_200_000_000).contains(where: \.isWhitespace))
    }

    @MainActor
    func testCapacitySideTypeIsTwentyPercentSmallerWithCloseLabel() {
        let actual = NSHostingView(rootView:
            CapacitySideReading(title: "USED", bytes: 32_600_000_000, fit: 1)
                .fixedSize()
                .environment(\.consoleTypography, ConsoleTypography())
        ).fittingSize
        let expected = NSHostingView(rootView:
            VStack(spacing: 1) {
                Text("USED").font(.system(size: 13 * 0.8, weight: .bold, design: .monospaced))
                Text("32.6GB").font(.system(size: 20 * 0.8, weight: .bold, design: .monospaced))
            }.fixedSize()
        ).fittingSize
        XCTAssertGreaterThan(actual.width, 0)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.1)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.1)
    }

    @MainActor
    func testCapacitySideReadingsFollowDarkTextNotMetricsSlider() {
        func measured(dark: Double, primary: Double) -> NSSize {
            let root = CapacitySideReading(title: "USED", bytes: 32_600_000_000, fit: 1)
                .fixedSize()
                .environment(\.consoleTypography, ConsoleTypography(groups: ["primary": primary, "secondary": 3, "dark": dark]))
            return NSHostingView(rootView: root).fittingSize
        }
        let original = measured(dark: 1, primary: 1)
        let largerMetrics = measured(dark: 1, primary: 3)
        XCTAssertGreaterThan(original.width, 0)
        XCTAssertEqual(original.width, largerMetrics.width, accuracy: 0.1)
        XCTAssertEqual(original.height, largerMetrics.height, accuracy: 0.1)
        XCTAssertGreaterThan(measured(dark: 2, primary: 1).width, original.width)
        XCTAssertGreaterThan(measured(dark: 2, primary: 1).height, original.height)
    }

    func testCapacityCountsAndPercentageAgree() throws {
        let reading = try XCTUnwrap(CapacityReading(totalBytes: 1_000_000_000_000, usedBytes: 970_000_000_000))
        XCTAssertEqual(reading.freeBytes, 30_000_000_000)
        XCTAssertEqual(reading.usedBytes + reading.freeBytes, reading.totalBytes)
        XCTAssertEqual(reading.fractionUsed, 0.97)
        XCTAssertEqual(capacityAmount(reading.usedBytes), "970.0 GB")
        XCTAssertEqual(capacityAmount(reading.freeBytes), "30.0 GB")
        XCTAssertEqual(capacityAmount(2_500_000_000_000), "2.50 TB")
        XCTAssertEqual(capacityAmount(0), "0.0 GB")
    }

    func testMemoryUsesHostPageSizeAndPhysicalTotal() throws {
        for pageSize: UInt64 in [4096, 16384] {
            let reading = try XCTUnwrap(CapacityReading.memory(active: 100, wired: 200, compressed: 300,
                pageSize: pageSize, physicalBytes: 1000 * pageSize))
            XCTAssertEqual(reading.usedBytes, Double(600 * pageSize))
            XCTAssertEqual(reading.freeBytes, Double(400 * pageSize))
            XCTAssertEqual(reading.fractionUsed, 0.6)
        }
    }

    func testInvalidCapacityIsUnavailableNotZero() {
        for (total, used): (Double, Double) in [(0, 0), (-1, 0), (100, -1), (100, 101), (.nan, 10), (100, .infinity)] {
            XCTAssertNil(CapacityReading(totalBytes: total, usedBytes: used))
        }
        XCTAssertNil(CapacityReading.memory(active: 1, wired: 1, compressed: 1, pageSize: 0, physicalBytes: 100))
        XCTAssertEqual(capacityAmount(nil), "N/A")
        XCTAssertEqual(capacityAmount(.nan), "N/A")
    }

    func testDuplexGraphHasCommonScaleWithoutOldSpeedCeiling() {
        let scale = NetworkHistoryGeometry.scale(receive: [0, 20_000_000], transmit: [0, 5_000_000])
        XCTAssertEqual(scale, 20_000_000)
        let top = CGRect(x: 0, y: 0, width: 100, height: 50)
        let bottom = CGRect(x: 0, y: 50, width: 100, height: 50)
        let tx = NetworkHistoryGeometry.segments([0, 5_000_000], in: top, scale: scale, transmit: true)[0]
        let rx = NetworkHistoryGeometry.segments([0, 20_000_000], in: bottom, scale: scale, transmit: false)[0]
        XCTAssertEqual(tx, [CGPoint(x: 0, y: 50), CGPoint(x: 100, y: 37.5)])
        XCTAssertEqual(rx, [CGPoint(x: 0, y: 50), CGPoint(x: 100, y: 100)])
        // The same byte rate has the same height, reflected across the center.
        let equalRX = NetworkHistoryGeometry.segments([0, 5_000_000], in: bottom, scale: scale, transmit: false)[0]
        XCTAssertEqual(50 - tx[1].y, equalRX[1].y - 50)
    }

    func testDuplexGraphZerosAndInvalidSamples() {
        XCTAssertEqual(NetworkHistoryGeometry.scale(receive: [], transmit: [.nan, -1]), 1000)
        let rect = CGRect(x: 10, y: 20, width: 100, height: 50)
        let segments = NetworkHistoryGeometry.segments([0, 1000, .nan, 500, -1, 250], in: rect, scale: 1000, transmit: true)
        XCTAssertEqual(segments.map(\.count), [2, 1, 1])
        XCTAssertEqual(segments[0].first, CGPoint(x: 10, y: 70))
        XCTAssertTrue(segments.flatMap { $0 }.allSatisfy {
            $0.x.isFinite && $0.y.isFinite && (rect.minX...rect.maxX).contains($0.x) && (rect.minY...rect.maxY).contains($0.y)
        })
        XCTAssertTrue(NetworkHistoryGeometry.segments([], in: rect, scale: 1000, transmit: false).isEmpty)
        XCTAssertTrue(NetworkHistoryGeometry.segments([100], in: .zero, scale: 1000, transmit: false).isEmpty)
    }

    func testNetworkReadoutKeepsSavedIDAndCustomFrame() {
        let saved = ModuleFrame(x: 630, y: 401, width: 290, height: 98, visible: true)
        let merged = LayoutDefaults.merging(["statusTX": saved], for: .fullMetrics)
        XCTAssertEqual(merged["statusTX"], saved)
        XCTAssertTrue(LayoutDefaults.modules(for: .fullMetrics).contains { $0.id == "statusTX" })
    }

    @MainActor
    func testLiveCapacitySamplesAndSeparateHistoriesAreConsistent() throws {
        let model = TelemetryModel()
        let memory = try XCTUnwrap(model.snapshot.memoryCapacity)
        let disk = try XCTUnwrap(model.snapshot.diskCapacity)
        XCTAssertEqual(memory.totalBytes, Double(ProcessInfo.processInfo.physicalMemory))
        XCTAssertEqual(model.snapshot.memory, memory.fractionUsed)
        XCTAssertEqual(model.snapshot.disk, disk.fractionUsed)
        XCTAssertEqual(memory.usedBytes + memory.freeBytes, memory.totalBytes)
        XCTAssertEqual(disk.usedBytes + disk.freeBytes, disk.totalBytes)
        XCTAssertEqual(model.networkReceiveHistory.count, 96)
        XCTAssertEqual(model.networkTransmitHistory.count, 96)
        XCTAssertEqual(model.networkReceiveHistory.last, model.snapshot.networkIn)
        XCTAssertEqual(model.networkTransmitHistory.last, model.snapshot.networkOut)
    }

    /// Synthetic panel-only captures: no production preferences, API keys, location or network requests.
    @MainActor
    func testNativePanelsRenderAtAllTextSizesAndThemes() throws {
        let suite = "RetrolemetryTests.Panels.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let oldPalette = ThemeRuntime.palette
        defer { defaults.removePersistentDomain(forName: suite); ThemeRuntime.palette = oldPalette }
        let rx = (0..<96).map { 150_000 + max(0, sin(Double($0) * 0.29)) * 20_000_000 }
        let tx = (0..<96).map { 90_000 + max(0, cos(Double($0) * 0.41)) * 9_000_000 }
        let cpu = (0..<96).map { 0.4 + sin(Double($0) * 0.2) * 0.15 }
        for style in ConsoleStyle.allCases {
            defaults.set(style.rawValue, forKey: "DockTelemetry.visualStyle")
            ThemeRuntime.palette = style.palette
            for scale in [1.0, 2.0, 3.0] {
                let root = VStack(spacing: 14) {
                    HStack(spacing: 14) {
                        LargeMetricTile(label: "MEMORY", value: "076%", level: 0.76, showsCapacity: true,
                            capacity: CapacityReading(totalBytes: 32_000_000_000, usedBytes: 24_320_000_000))
                        LargeMetricTile(label: "DISK USED", value: "097%", level: 0.97, showsCapacity: true,
                            capacity: CapacityReading(totalBytes: 1_000_000_000_000, usedBytes: 970_000_000_000))
                    }.frame(height: 116)
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 14) {
                            MiniTrace(label: "CPU", values: cpu, value: "40%")
                            MiniTrace(label: "MEMORY", values: cpu, value: "76%")
                        }.frame(width: 200, height: 170)
                        VStack(spacing: 12) {
                            NetworkTrafficPanel(transmit: 683_000, receiveHistory: rx, transmitHistory: tx)
                                .frame(height: 240)
                            LargeStatusReadout(label: "NETWORK RX", value: "19.7 MB/S").frame(height: 95)
                        }.frame(width: 300)
                        LargeDataGraph(label: "CPU // 96 SEC", value: "040%", values: cpu)
                            .frame(height: 240)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16).frame(width: 960, height: 540)
                .foregroundStyle(phosphor).background(Color.black)
                .defaultAppStorage(defaults)
                .environment(\.consoleTypography, ConsoleTypography(primary: scale, secondary: scale, other: scale))
                let renderer = ImageRenderer(content: root)
                renderer.scale = 1
                let cgImage = try XCTUnwrap(renderer.cgImage)
                XCTAssertEqual(cgImage.width, 960)
                XCTAssertEqual(cgImage.height, 540)
                if let output = ProcessInfo.processInfo.environment["RETROLEMETRY_QA_OUTPUT"] {
                    let bitmap = NSBitmapImageRep(cgImage: cgImage)
                    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    try png.write(to: URL(fileURLWithPath: output).appendingPathComponent("panels-\(style.rawValue)-\(Int(scale * 100)).png"))
                }
            }
        }
    }
}
