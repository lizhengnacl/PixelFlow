import Foundation

enum SystemMetricKind: String, CaseIterable, Hashable {
    case memoryUsage
    case diskUsage
    case cpuTemperature
    case fanSpeed
    case cpuUsage
    case gpuUsage

    static let menuOrder: [SystemMetricKind] = [
        .memoryUsage,
        .diskUsage,
        .cpuUsage,
        .gpuUsage,
        .cpuTemperature,
        .fanSpeed
    ]

    var label: String {
        switch self {
        case .memoryUsage:
            return "内存占用"
        case .diskUsage:
            return "磁盘占用"
        case .cpuTemperature:
            return "CPU 温度"
        case .fanSpeed:
            return "风扇转速"
        case .cpuUsage:
            return "CPU 占用"
        case .gpuUsage:
            return "GPU 占用"
        }
    }

    var shortLabel: String {
        switch self {
        case .memoryUsage:
            return "内存"
        case .diskUsage:
            return "磁盘"
        case .cpuTemperature:
            return "温度"
        case .fanSpeed:
            return "风扇"
        case .cpuUsage:
            return "CPU"
        case .gpuUsage:
            return "GPU"
        }
    }
}

struct SystemMetricReading {
    let kind: SystemMetricKind
    let valueText: String
    let normalizedValue: Double
    let isAvailable: Bool
    let diagnostic: String?
}

struct SystemMetricsSnapshot {
    let timestamp: Date
    let readings: [SystemMetricKind: SystemMetricReading]

    static let empty = SystemMetricsSnapshot(timestamp: Date(), readings: [:])

    func reading(for kind: SystemMetricKind) -> SystemMetricReading {
        readings[kind] ?? SystemMetricReading(
            kind: kind,
            valueText: "不可用",
            normalizedValue: 0,
            isAvailable: false,
            diagnostic: "尚未采集"
        )
    }
}

enum SystemMetricFormatter {
    static func percent(_ value: Double) -> String {
        "\(Int((max(0, min(1, value)) * 100).rounded()))%"
    }

    static func temperature(_ celsius: Double) -> String {
        String(format: "%.0f°C", celsius)
    }

    static func fanSpeed(_ rpm: Double) -> String {
        "\(Int(max(0, rpm).rounded())) RPM"
    }

    static func storage(usedBytes: UInt64, totalBytes: UInt64) -> String {
        guard totalBytes > 0 else {
            return "不可用"
        }

        let fraction = Double(usedBytes) / Double(totalBytes)
        return "\(bytes(usedBytes)) / \(bytes(totalBytes)) (\(percent(fraction)))"
    }

    private static func bytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = 0

        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            return "\(Int(value.rounded())) \(units[unitIndex])"
        }

        if value >= 10 {
            return String(format: "%.0f %@", value, units[unitIndex])
        }

        return String(format: "%.1f %@", value, units[unitIndex])
    }
}
