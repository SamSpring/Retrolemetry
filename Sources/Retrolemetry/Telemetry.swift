import Foundation
import Combine
import Darwin

struct TelemetrySnapshot {
    var cpu: Double = 0
    var memory: Double = 0
    var disk: Double = 0
    var networkIn: Double = 0
    var networkOut: Double = 0
    var uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    var load: (Double, Double, Double) = (0, 0, 0)
}

@MainActor
final class TelemetryModel: ObservableObject {
    @Published private(set) var snapshot = TelemetrySnapshot()
    @Published private(set) var cpuHistory: [Double] = Array(repeating: 0, count: 96)
    @Published private(set) var memoryHistory: [Double] = Array(repeating: 0, count: 96)
    @Published private(set) var networkHistory: [Double] = Array(repeating: 0, count: 96)

    private var timer: Timer?
    private var previousCPU: (idle: UInt64, total: UInt64)?
    private var previousNetwork: (input: UInt64, output: UInt64, time: TimeInterval)?

    init() {
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let owner = self else { return }
            Task { @MainActor in owner.sample() }
        }
        timer?.tolerance = 0.12
    }

    deinit { timer?.invalidate() }

    private func sample() {
        snapshot.cpu = cpuUsage()
        snapshot.memory = memoryUsage()
        snapshot.disk = diskUsage()
        let network = networkRates()
        snapshot.networkIn = network.input
        snapshot.networkOut = network.output
        snapshot.uptime = ProcessInfo.processInfo.systemUptime

        var averages = [Double](repeating: 0, count: 3)
        if getloadavg(&averages, 3) == 3 {
            snapshot.load = (averages[0], averages[1], averages[2])
        }

        append(snapshot.cpu, to: &cpuHistory)
        append(snapshot.memory, to: &memoryHistory)
        append(min(1, (snapshot.networkIn + snapshot.networkOut) / 12_000_000), to: &networkHistory)
    }

    private func append(_ value: Double, to history: inout [Double]) {
        history.append(value)
        if history.count > 96 { history.removeFirst(history.count - 96) }
    }

    private func cpuUsage() -> Double {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return snapshot.cpu }

        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)
        let total = user + system + idle + nice
        defer { previousCPU = (idle, total) }
        guard let prior = previousCPU, total > prior.total else { return 0 }
        let totalDelta = total - prior.total
        let idleDelta = idle - prior.idle
        return min(1, max(0, 1 - Double(idleDelta) / Double(totalDelta)))
    }

    private func memoryUsage() -> Double {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result: kern_return_t = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return snapshot.memory }
        let used = Double(stats.active_count + stats.wire_count + stats.compressor_page_count)
        let available = used + Double(stats.inactive_count + stats.free_count + stats.speculative_count)
        return available > 0 ? min(1, used / available) : 0
    }

    private func diskUsage() -> Double {
        guard let values = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
              let total = values[.systemSize] as? NSNumber,
              let free = values[.systemFreeSize] as? NSNumber,
              total.doubleValue > 0 else { return snapshot.disk }
        return 1 - (free.doubleValue / total.doubleValue)
    }

    private func networkRates() -> (input: Double, output: Double) {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return (0, 0) }
        defer { freeifaddrs(pointer) }

        var input: UInt64 = 0
        var output: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let item = cursor {
            let flags = Int32(item.pointee.ifa_flags)
            if flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
               item.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
               let data = item.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                input += UInt64(data.pointee.ifi_ibytes)
                output += UInt64(data.pointee.ifi_obytes)
            }
            cursor = item.pointee.ifa_next
        }

        let now = ProcessInfo.processInfo.systemUptime
        defer { previousNetwork = (input, output, now) }
        guard let prior = previousNetwork, now > prior.time else { return (0, 0) }
        let elapsed = now - prior.time
        return (
            Double(input >= prior.input ? input - prior.input : 0) / elapsed,
            Double(output >= prior.output ? output - prior.output : 0) / elapsed
        )
    }
}

extension TimeInterval {
    var compactUptime: String {
        let seconds = Int(self)
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        return String(format: "%02dD:%02dH:%02dM", days, hours, minutes)
    }
}

func byteRate(_ value: Double) -> String {
    if value >= 1_000_000 { return String(format: "%.1f MB/S", value / 1_000_000) }
    if value >= 1_000 { return String(format: "%.0f KB/S", value / 1_000) }
    return String(format: "%.0f B/S", value)
}
