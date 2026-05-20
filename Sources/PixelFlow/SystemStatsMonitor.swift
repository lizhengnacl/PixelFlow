import Darwin
import Foundation
import IOKit

final class SystemStatsMonitor {
    var onUpdate: ((SystemMetricsSnapshot) -> Void)?

    private let interval: TimeInterval
    private var timer: Timer?
    private var previousCPUTicks: CPUTicks?
    private let smcClient = SMCClient()

    init(interval: TimeInterval = 1.0) {
        self.interval = interval
    }

    func start() {
        stop()
        previousCPUTicks = Self.readCPUTicks()
        sample()

        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.sample()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        previousCPUTicks = nil
    }

    func pause() {
        timer?.fireDate = .distantFuture
    }

    func resume() {
        previousCPUTicks = Self.readCPUTicks()
        timer?.fireDate = Date(timeIntervalSinceNow: interval)
    }

    private func sample() {
        var readings: [SystemMetricKind: SystemMetricReading] = [:]

        readings[.memoryUsage] = memoryUsageReading()
        readings[.diskUsage] = diskUsageReading()
        readings[.cpuTemperature] = cpuTemperatureReading()
        readings[.fanSpeed] = fanSpeedReading()
        readings[.cpuUsage] = cpuUsageReading()
        readings[.gpuUsage] = gpuUsageReading()

        onUpdate?(SystemMetricsSnapshot(timestamp: Date(), readings: readings))
    }

    private func memoryUsageReading() -> SystemMetricReading {
        guard let usage = Self.readMemoryUsage() else {
            return unavailable(.memoryUsage)
        }

        return SystemMetricReading(
            kind: .memoryUsage,
            valueText: SystemMetricFormatter.storage(
                usedBytes: usage.usedBytes,
                totalBytes: usage.totalBytes
            ),
            normalizedValue: usage.fraction,
            isAvailable: true
        )
    }

    private func diskUsageReading() -> SystemMetricReading {
        guard let usage = Self.readDiskUsage() else {
            return unavailable(.diskUsage)
        }

        return SystemMetricReading(
            kind: .diskUsage,
            valueText: SystemMetricFormatter.storage(
                usedBytes: usage.usedBytes,
                totalBytes: usage.totalBytes
            ),
            normalizedValue: usage.fraction,
            isAvailable: true
        )
    }

    private func cpuTemperatureReading() -> SystemMetricReading {
        guard let temperature = smcClient?.cpuTemperatureCelsius() else {
            return unavailable(.cpuTemperature)
        }

        return SystemMetricReading(
            kind: .cpuTemperature,
            valueText: SystemMetricFormatter.temperature(temperature),
            normalizedValue: Self.normalize(temperature, low: 35, high: 95),
            isAvailable: true
        )
    }

    private func fanSpeedReading() -> SystemMetricReading {
        guard let speed = smcClient?.primaryFanSpeedRPM() else {
            return unavailable(.fanSpeed)
        }

        let maxRPM = speed.maxRPM ?? 6000
        return SystemMetricReading(
            kind: .fanSpeed,
            valueText: SystemMetricFormatter.fanSpeed(speed.currentRPM),
            normalizedValue: maxRPM > 0 ? max(0, min(1, speed.currentRPM / maxRPM)) : 0,
            isAvailable: true
        )
    }

    private func cpuUsageReading() -> SystemMetricReading {
        guard let usage = readCPUUsage() else {
            return unavailable(.cpuUsage)
        }

        return SystemMetricReading(
            kind: .cpuUsage,
            valueText: SystemMetricFormatter.percent(usage),
            normalizedValue: usage,
            isAvailable: true
        )
    }

    private func gpuUsageReading() -> SystemMetricReading {
        guard let usage = Self.readGPUUsage() else {
            return unavailable(.gpuUsage)
        }

        return SystemMetricReading(
            kind: .gpuUsage,
            valueText: SystemMetricFormatter.percent(usage),
            normalizedValue: usage,
            isAvailable: true
        )
    }

    private func unavailable(_ kind: SystemMetricKind) -> SystemMetricReading {
        SystemMetricReading(
            kind: kind,
            valueText: "不可用",
            normalizedValue: 0,
            isAvailable: false
        )
    }

    private struct CapacityUsage {
        let usedBytes: UInt64
        let totalBytes: UInt64

        var fraction: Double {
            guard totalBytes > 0 else {
                return 0
            }

            return max(0, min(1, Double(usedBytes) / Double(totalBytes)))
        }
    }

    private static func readMemoryUsage() -> CapacityUsage? {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }

        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else {
            return nil
        }

        let totalBytes = ProcessInfo.processInfo.physicalMemory
        let reclaimablePages = UInt64(statistics.free_count + statistics.inactive_count + statistics.speculative_count)
        let availableBytes = reclaimablePages * UInt64(pageSize)
        let usedBytes = totalBytes > availableBytes ? totalBytes - availableBytes : 0

        return CapacityUsage(usedBytes: usedBytes, totalBytes: totalBytes)
    }

    private static func readDiskUsage() -> CapacityUsage? {
        guard
            let attributes = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
            let total = attributes[.systemSize] as? NSNumber,
            let free = attributes[.systemFreeSize] as? NSNumber
        else {
            return nil
        }

        let totalBytes = total.uint64Value
        let freeBytes = free.uint64Value
        let usedBytes = totalBytes > freeBytes ? totalBytes - freeBytes : 0

        return CapacityUsage(usedBytes: usedBytes, totalBytes: totalBytes)
    }

    private struct CPUTicks {
        let user: UInt64
        let system: UInt64
        let idle: UInt64
        let nice: UInt64
    }

    private func readCPUUsage() -> Double? {
        guard let current = Self.readCPUTicks() else {
            return nil
        }

        defer {
            previousCPUTicks = current
        }

        guard let previous = previousCPUTicks else {
            return nil
        }

        let user = Self.delta(current.user, previous.user)
        let system = Self.delta(current.system, previous.system)
        let idle = Self.delta(current.idle, previous.idle)
        let nice = Self.delta(current.nice, previous.nice)
        let active = user + system + nice
        let total = active + idle

        guard total > 0 else {
            return nil
        }

        return max(0, min(1, Double(active) / Double(total)))
    }

    private static func readCPUTicks() -> CPUTicks? {
        var cpuLoad = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &cpuLoad) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }

        return CPUTicks(
            user: UInt64(cpuLoad.cpu_ticks.0),
            system: UInt64(cpuLoad.cpu_ticks.1),
            idle: UInt64(cpuLoad.cpu_ticks.2),
            nice: UInt64(cpuLoad.cpu_ticks.3)
        )
    }

    private static func delta(_ current: UInt64, _ previous: UInt64) -> UInt64 {
        current >= previous ? current - previous : 0
    }

    private static func readGPUUsage() -> Double? {
        let classNames = ["IOAccelerator", "IOAccelerator2", "AGXAccelerator"]
        var samples: [Double] = []

        for className in classNames {
            guard let matching = IOServiceMatching(className) else {
                continue
            }

            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
                continue
            }

            defer {
                IOObjectRelease(iterator)
            }

            while true {
                let service = IOIteratorNext(iterator)
                guard service != 0 else {
                    break
                }

                if let usage = gpuUsage(from: service) {
                    samples.append(usage)
                }

                IOObjectRelease(service)
            }
        }

        guard let highest = samples.max() else {
            return nil
        }

        return max(0, min(1, highest / 100))
    }

    private static func gpuUsage(from service: io_object_t) -> Double? {
        guard let property = IORegistryEntryCreateCFProperty(
            service,
            "PerformanceStatistics" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        var candidates: [Double] = []
        let preferredKeys = [
            "Device Utilization %",
            "GPU Core Utilization",
            "Renderer Utilization %",
            "Tiler Utilization %"
        ]

        for key in preferredKeys {
            if let value = numericValue(property[key]) {
                candidates.append(value)
            }
        }

        for (key, value) in property where key.localizedCaseInsensitiveContains("utilization") {
            if let numericValue = numericValue(value) {
                candidates.append(numericValue)
            }
        }

        return candidates.max()
    }

    private static func numericValue(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private static func normalize(_ value: Double, low: Double, high: Double) -> Double {
        guard high > low else {
            return 0
        }

        return max(0, min(1, (value - low) / (high - low)))
    }
}
