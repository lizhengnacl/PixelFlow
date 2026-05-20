import AppKit

enum TrafficDirection: String, Hashable {
    case upload
    case download

    var label: String {
        switch self {
        case .upload:
            return "上传"
        case .download:
            return "下载"
        }
    }

    var arrow: String {
        switch self {
        case .upload:
            return "↑"
        case .download:
            return "↓"
        }
    }
}

struct TrafficRates {
    let uploadBytesPerSecond: Double
    let downloadBytesPerSecond: Double
    let timestamp: Date
    let source: TrafficSource
    let interfaceRates: [InterfaceTrafficRate]
}

enum TrafficSource: String {
    case interfaceCounters
    case nettopFallback

    var label: String {
        switch self {
        case .interfaceCounters:
            return "接口计数"
        case .nettopFallback:
            return "nettop 补偿"
        }
    }
}

struct InterfaceTrafficRate {
    let name: String
    let uploadBytesPerSecond: Double
    let downloadBytesPerSecond: Double

    var totalBytesPerSecond: Double {
        uploadBytesPerSecond + downloadBytesPerSecond
    }
}

enum SpriteMotion: String, Hashable {
    case idle
    case walk
    case run

    var frameCount: Int {
        switch self {
        case .idle:
            return 2
        case .walk:
            return 4
        case .run:
            return 6
        }
    }
}

struct AnimationProfile {
    let motion: SpriteMotion
    let normalizedTraffic: Double
    let frameDuration: TimeInterval

    static let highTrafficAnchor: Double = 50 * 1024 * 1024

    static func make(for bytesPerSecond: Double) -> AnimationProfile {
        let rate = max(0, bytesPerSecond)

        guard rate >= 1 else {
            return AnimationProfile(motion: .idle, normalizedTraffic: 0, frameDuration: 0.75)
        }

        let normalized = min(
            1,
            log10(1 + rate / 1024) / log10(1 + highTrafficAnchor / 1024)
        )

        let motion: SpriteMotion = rate >= 5 * 1024 * 1024 ? .run : .walk
        let speedFactor = 0.2 + normalized * 1.8
        let baseFramesPerSecond: Double = motion == .run ? 9 : 6
        let framesPerSecond = min(20, max(2, baseFramesPerSecond * speedFactor))

        return AnimationProfile(
            motion: motion,
            normalizedTraffic: normalized,
            frameDuration: 1 / framesPerSecond
        )
    }
}

enum TrafficFormatter {
    static func rate(_ bytesPerSecond: Double) -> String {
        let rate = max(0, bytesPerSecond)
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = rate
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

enum TrafficColorRamp {
    static func color(for normalizedTraffic: Double) -> NSColor {
        let value = max(0, min(1, normalizedTraffic))

        let green = RGB(red: 48, green: 209, blue: 88)
        let yellow = RGB(red: 255, green: 214, blue: 10)
        let red = RGB(red: 255, green: 69, blue: 58)

        let rgb: RGB
        if value < 0.5 {
            rgb = RGB.mix(green, yellow, fraction: value / 0.5)
        } else {
            rgb = RGB.mix(yellow, red, fraction: (value - 0.5) / 0.5)
        }

        return NSColor(
            calibratedRed: rgb.red / 255,
            green: rgb.green / 255,
            blue: rgb.blue / 255,
            alpha: 1
        )
    }

    private struct RGB {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat

        init(red: CGFloat, green: CGFloat, blue: CGFloat) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        static func mix(_ start: RGB, _ end: RGB, fraction: Double) -> RGB {
            let amount = max(0, min(1, fraction))
            return RGB(
                red: start.red + (end.red - start.red) * amount,
                green: start.green + (end.green - start.green) * amount,
                blue: start.blue + (end.blue - start.blue) * amount
            )
        }
    }
}
