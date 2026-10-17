import Foundation
import CoreGraphics
import IOKit
import IOKit.ps

struct PowerReading {
    var voltage: Double?
    var current: Double?
    var onACPower = false
    var isCharging = false

    /// Battery flow is not CPU/package power or total computer power consumption.
    var watts: Double? {
        guard let voltage, let current else { return nil }
        return abs(voltage * current)
    }

    var status: String {
        guard voltage != nil || current != nil else { return "SENSOR UNAVAILABLE" }
        if isCharging { return "BATTERY CHARGING" }
        return onACPower ? "AC / BATTERY FLOW" : "BATTERY DISCHARGE"
    }
}

/// Read only exported properties with public IOKit functions. Driver counters are
/// optional and may disappear on other hardware/OS versions; never substitute CPU load.
final class HardwareMetricsReader {
    private var accelerators: [io_service_t] = []
    private var battery: io_service_t = 0
    private var lastDiscovery = Date.distantPast

    init() { discoverServices() }

    deinit {
        for service in accelerators { IOObjectRelease(service) }
        if battery != 0 { IOObjectRelease(battery) }
    }

    func gpuUsage() -> Double? {
        if Date().timeIntervalSince(lastDiscovery) >= 30 { discoverServices() }
        // On multi-GPU Macs report the busiest exposed device, not a sum of percentages.
        return accelerators.compactMap { service in
            guard let stats = property(service, "PerformanceStatistics") as? [String: Any] else { return nil }
            return Self.gpuUsage(statistics: stats)
        }.max()
    }

    static func gpuUsage(statistics: [String: Any]) -> Double? {
        guard let value = statistics["Device Utilization %"] as? NSNumber else { return nil }
        let percent = value.doubleValue
        guard percent.isFinite, (0...100).contains(percent) else { return nil }
        return percent / 100
    }

    func powerReading() -> PowerReading {
        var reading = PowerReading()
        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                guard let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                      info[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
                reading.voltage = Self.volts(info[kIOPSVoltageKey] as? NSNumber)
                reading.current = Self.amps(info[kIOPSCurrentKey] as? NSNumber)
                reading.onACPower = info[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
                reading.isCharging = (info[kIOPSIsChargingKey] as? NSNumber)?.boolValue ?? false
                break
            }
        }
        // macOS sometimes omits voltage and rounds battery current in IOPowerSources.
        // The exported battery properties give mV/mA without opening a private sensor connection.
        if battery != 0 {
            if reading.voltage == nil {
                reading.voltage = Self.volts(property(battery, "Voltage") as? NSNumber)
            }
            let current = property(battery, "InstantAmperage") as? NSNumber
                ?? property(battery, "Amperage") as? NSNumber
            if let amps = Self.amps(current) { reading.current = amps }
            if let external = property(battery, "ExternalConnected") as? NSNumber { reading.onACPower = external.boolValue }
            if let charging = property(battery, "IsCharging") as? NSNumber { reading.isCharging = charging.boolValue }
        }
        return reading
    }

    static func volts(_ millivolts: NSNumber?) -> Double? {
        guard let millivolts else { return nil }
        let value = millivolts.doubleValue / 1000
        return value.isFinite && value > 0 && value <= 100 ? value : nil
    }

    static func amps(_ milliamps: NSNumber?) -> Double? {
        guard let milliamps else { return nil }
        // Some drivers encode negative discharge current as an unsigned two's-complement value.
        let value = Double(milliamps.int64Value) / 1000
        return abs(value) <= 100 ? value : nil
    }

    private func property(_ service: io_service_t, _ key: String) -> CFTypeRef? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private func discoverServices() {
        lastDiscovery = Date()
        for service in accelerators { IOObjectRelease(service) }
        accelerators = []
        var iterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS {
            defer { IOObjectRelease(iterator) }
            var service = IOIteratorNext(iterator)
            while service != 0 {
                accelerators.append(service)
                service = IOIteratorNext(iterator)
            }
        }
        if battery != 0 { IOObjectRelease(battery) }
        battery = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    }
}

/// Missing samples produce gaps, not a fabricated zero or a line joining across an outage.
enum UsageHistoryGeometry {
    static func segments(_ values: [Double?], in rect: CGRect) -> [[CGPoint]] {
        guard !values.isEmpty else { return [] }
        var segments: [[CGPoint]] = []
        var current: [CGPoint] = []
        for (index, value) in values.enumerated() {
            guard let value, value.isFinite, (0...1).contains(value) else {
                if !current.isEmpty { segments.append(current); current = [] }
                continue
            }
            let x = rect.minX + rect.width * CGFloat(index) / CGFloat(max(1, values.count - 1))
            let y = rect.maxY - rect.height * CGFloat(value)
            current.append(CGPoint(x: x, y: y))
        }
        if !current.isEmpty { segments.append(current) }
        return segments
    }
}
