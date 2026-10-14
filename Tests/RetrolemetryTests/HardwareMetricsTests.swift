import XCTest
@testable import Retrolemetry

final class HardwareMetricsTests: XCTestCase {
    func testGPUCounterUsesPercentAndAllowsRealZero() {
        XCTAssertEqual(HardwareMetricsReader.gpuUsage(statistics: ["Device Utilization %": 68]), 0.68)
        XCTAssertEqual(HardwareMetricsReader.gpuUsage(statistics: ["Device Utilization %": 0]), 0)
        XCTAssertEqual(HardwareMetricsReader.gpuUsage(statistics: ["Device Utilization %": 100]), 1)
    }

    func testGPUCounterRejectsMissingAndInvalidRatherThanInventingZero() {
        for stats: [String: Any] in [[:], ["systemLoad": 8], ["Device Utilization %": -1],
                                    ["Device Utilization %": 101], ["Device Utilization %": "busy"],
                                    ["Device Utilization %": Double.nan]] {
            XCTAssertNil(HardwareMetricsReader.gpuUsage(statistics: stats))
        }
    }

    func testBatteryUnitsAndSignedCurrent() {
        XCTAssertEqual(HardwareMetricsReader.volts(12161), 12.161)
        XCTAssertEqual(HardwareMetricsReader.amps(-850), -0.85)
        let unsignedDischarge = NSNumber(value: UInt64(bitPattern: Int64(-850)))
        XCTAssertEqual(HardwareMetricsReader.amps(unsignedDischarge), -0.85)
        let reading = PowerReading(voltage: 12, current: -0.85)
        XCTAssertEqual(reading.watts!, 10.2, accuracy: 0.0001)
        XCTAssertEqual(reading.status, "BATTERY DISCHARGE")
        XCTAssertEqual(PowerReading(voltage: 12, current: 0, onACPower: true).watts, 0)
    }

    func testUnavailablePowerIsNotReportedAsZero() {
        XCTAssertNil(PowerReading().watts)
        XCTAssertNil(PowerReading(voltage: 12).watts)
        XCTAssertNil(PowerReading(current: 1).watts)
        XCTAssertNil(HardwareMetricsReader.volts(0))
        XCTAssertNil(HardwareMetricsReader.volts(200_000))
        XCTAssertNil(HardwareMetricsReader.amps(200_000))
        XCTAssertEqual(PowerReading().status, "SENSOR UNAVAILABLE")
    }

    func testHistoryDoesNotBridgeMissingOrInvalidSamples() {
        let rect = CGRect(x: 10, y: 20, width: 100, height: 50)
        let segments = UsageHistoryGeometry.segments([0, 1, nil, 0.5, .nan, 0.25], in: rect)
        XCTAssertEqual(segments.map(\.count), [2, 1, 1])
        XCTAssertEqual(segments[0], [CGPoint(x: 10, y: 70), CGPoint(x: 30, y: 20)])
        XCTAssertEqual(segments[1][0], CGPoint(x: 70, y: 45))
        XCTAssertTrue(UsageHistoryGeometry.segments([nil, nil], in: rect).isEmpty)
        XCTAssertTrue(UsageHistoryGeometry.segments([], in: rect).isEmpty)
    }
}
