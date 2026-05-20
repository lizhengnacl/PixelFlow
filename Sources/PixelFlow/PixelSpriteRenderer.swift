import AppKit
import CoreGraphics

final class PixelSpriteRenderer {
    private struct CacheKey: Hashable {
        let direction: TrafficDirection
        let motion: SpriteMotion
        let frame: Int
        let colorBucket: Int
    }

    private struct MetricCacheKey: Hashable {
        let metric: SystemMetricKind
        let frame: Int
        let colorBucket: Int
        let isAvailable: Bool
    }

    private let logicalSize = 22
    private let scale = 2
    private var cache: [CacheKey: NSImage] = [:]
    private var metricCache: [MetricCacheKey: NSImage] = [:]

    func image(
        direction: TrafficDirection,
        motion: SpriteMotion,
        frame: Int,
        normalizedTraffic: Double
    ) -> NSImage {
        let bucket = Int((max(0, min(1, normalizedTraffic)) * 100).rounded())
        let key = CacheKey(
            direction: direction,
            motion: motion,
            frame: frame % motion.frameCount,
            colorBucket: bucket
        )

        if let image = cache[key] {
            return image
        }

        let image = render(
            direction: direction,
            motion: motion,
            frame: key.frame,
            tint: TrafficColorRamp.color(for: Double(bucket) / 100)
        )
        cache[key] = image
        return image
    }

    func image(
        metric: SystemMetricKind,
        frame: Int,
        normalizedValue: Double,
        isAvailable: Bool
    ) -> NSImage {
        let bucket = Int((max(0, min(1, normalizedValue)) * 100).rounded())
        let key = MetricCacheKey(
            metric: metric,
            frame: metric == .fanSpeed ? frame % 4 : 0,
            colorBucket: bucket,
            isAvailable: isAvailable
        )

        if let image = metricCache[key] {
            return image
        }

        let image = renderMetric(
            metric: metric,
            frame: key.frame,
            normalizedValue: Double(bucket) / 100,
            tint: TrafficColorRamp.color(for: Double(bucket) / 100),
            isAvailable: isAvailable
        )
        metricCache[key] = image
        return image
    }

    private func render(
        direction: TrafficDirection,
        motion: SpriteMotion,
        frame: Int,
        tint: NSColor
    ) -> NSImage {
        let pixelSize = logicalSize * scale
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else {
            return NSImage(size: NSSize(width: logicalSize, height: logicalSize))
        }

        context.clear(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
        context.setShouldAntialias(false)
        context.interpolationQuality = .none

        let draw = PixelDrawContext(
            context: context,
            logicalSize: logicalSize,
            scale: scale,
            mirrorHorizontally: direction == .download
        )

        drawSprite(draw: draw, motion: motion, frame: frame, tint: tint)

        let image = NSImage(size: NSSize(width: logicalSize, height: logicalSize))
        rep.size = image.size
        image.addRepresentation(rep)
        image.isTemplate = false
        return image
    }

    private func renderMetric(
        metric: SystemMetricKind,
        frame: Int,
        normalizedValue: Double,
        tint: NSColor,
        isAvailable: Bool
    ) -> NSImage {
        let pixelSize = logicalSize * scale
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else {
            return NSImage(size: NSSize(width: logicalSize, height: logicalSize))
        }

        context.clear(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
        context.setShouldAntialias(false)
        context.interpolationQuality = .none

        let draw = PixelDrawContext(
            context: context,
            logicalSize: logicalSize,
            scale: scale,
            mirrorHorizontally: false
        )

        drawMetricIcon(
            draw: draw,
            metric: metric,
            frame: frame,
            normalizedValue: normalizedValue,
            tint: tint,
            isAvailable: isAvailable
        )

        let image = NSImage(size: NSSize(width: logicalSize, height: logicalSize))
        rep.size = image.size
        image.addRepresentation(rep)
        image.isTemplate = false
        return image
    }

    private func drawSprite(
        draw: PixelDrawContext,
        motion: SpriteMotion,
        frame: Int,
        tint: NSColor
    ) {
        let body = NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.09, alpha: 1)
        let bodyMid = NSColor(calibratedRed: 0.14, green: 0.15, blue: 0.17, alpha: 1)
        let outline = NSColor(calibratedWhite: 0.92, alpha: 0.95)
        let shadow = NSColor(calibratedWhite: 0, alpha: 0.25)
        let eye = NSColor(calibratedWhite: 1, alpha: 1)

        let bob = bobOffset(motion: motion, frame: frame)
        let legA = legOffset(motion: motion, frame: frame, phase: 0)
        let legB = legOffset(motion: motion, frame: frame, phase: 1)
        let armA = armOffset(motion: motion, frame: frame, phase: 0)
        let armB = armOffset(motion: motion, frame: frame, phase: 1)
        let scarf = scarfLength(motion: motion, frame: frame)

        draw.rect(x: 5, y: 19, width: 11, height: 1, color: shadow)

        draw.rect(x: max(1, 7 - scarf), y: 6 + bob, width: scarf, height: 2, color: tint.withAlphaComponent(0.85))
        if motion == .run {
            draw.rect(x: max(1, 6 - scarf), y: 8 + bob, width: max(2, scarf - 1), height: 1, color: tint.withAlphaComponent(0.55))
        }

        draw.rect(x: 8 + legA, y: 15 + bob, width: 3, height: 4, color: outline)
        draw.rect(x: 9 + legA, y: 15 + bob, width: 2, height: 4, color: body)
        draw.rect(x: 7 + legA, y: 18 + bob, width: 4, height: 1, color: body)

        draw.rect(x: 12 + legB, y: 15 + bob, width: 3, height: 4, color: outline)
        draw.rect(x: 12 + legB, y: 15 + bob, width: 2, height: 4, color: body)
        draw.rect(x: 12 + legB, y: 18 + bob, width: 4, height: 1, color: body)

        draw.rect(x: 6 + armA, y: 10 + bob, width: 3, height: 5, color: outline)
        draw.rect(x: 7 + armA, y: 10 + bob, width: 2, height: 5, color: body)
        draw.rect(x: 14 + armB, y: 10 + bob, width: 3, height: 5, color: outline)
        draw.rect(x: 14 + armB, y: 10 + bob, width: 2, height: 5, color: body)

        draw.rect(x: 7, y: 8 + bob, width: 9, height: 8, color: outline)
        draw.rect(x: 8, y: 9 + bob, width: 7, height: 6, color: body)
        draw.rect(x: 9, y: 11 + bob, width: 5, height: 2, color: tint)

        draw.rect(x: 7, y: 3 + bob, width: 8, height: 6, color: outline)
        draw.rect(x: 8, y: 4 + bob, width: 6, height: 4, color: bodyMid)
        draw.rect(x: 9, y: 5 + bob, width: 5, height: 2, color: body)
        draw.rect(x: 13, y: 5 + bob, width: 1, height: 1, color: eye)
        draw.rect(x: 9, y: 3 + bob, width: 4, height: 1, color: tint)
    }

    private func bobOffset(motion: SpriteMotion, frame: Int) -> Int {
        switch motion {
        case .idle:
            return frame % 2
        case .walk:
            return [0, 1, 0, 1][frame % 4]
        case .run:
            return [0, 1, 1, 0, 1, 1][frame % 6]
        }
    }

    private func legOffset(motion: SpriteMotion, frame: Int, phase: Int) -> Int {
        switch motion {
        case .idle:
            return phase == 0 ? 0 : 1
        case .walk:
            let offsets = [-1, 0, 1, 0]
            return phase == 0 ? offsets[frame % 4] : -offsets[frame % 4]
        case .run:
            let offsets = [-2, -1, 1, 2, 1, -1]
            return phase == 0 ? offsets[frame % 6] : -offsets[frame % 6]
        }
    }

    private func armOffset(motion: SpriteMotion, frame: Int, phase: Int) -> Int {
        switch motion {
        case .idle:
            return 0
        case .walk:
            let offsets = [1, 0, -1, 0]
            return phase == 0 ? offsets[frame % 4] : -offsets[frame % 4]
        case .run:
            let offsets = [2, 1, -1, -2, -1, 1]
            return phase == 0 ? offsets[frame % 6] : -offsets[frame % 6]
        }
    }

    private func scarfLength(motion: SpriteMotion, frame: Int) -> Int {
        switch motion {
        case .idle:
            return frame % 2 == 0 ? 3 : 4
        case .walk:
            return [4, 5, 4, 5][frame % 4]
        case .run:
            return [6, 7, 8, 7, 8, 7][frame % 6]
        }
    }

    private func drawMetricIcon(
        draw: PixelDrawContext,
        metric: SystemMetricKind,
        frame: Int,
        normalizedValue: Double,
        tint: NSColor,
        isAvailable: Bool
    ) {
        let outline = NSColor(calibratedWhite: 0.92, alpha: 0.95)
        let body = NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.11, alpha: 1)
        let bodyMid = NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.20, alpha: 1)
        let muted = NSColor(calibratedWhite: 0.45, alpha: 0.8)
        let activeTint = isAvailable ? tint : muted
        let level = isAvailable ? max(0, min(1, normalizedValue)) : 0

        draw.rect(x: 5, y: 19, width: 12, height: 1, color: NSColor(calibratedWhite: 0, alpha: 0.22))

        switch metric {
        case .memoryUsage:
            drawMemoryIcon(draw: draw, level: level, tint: activeTint, outline: outline, body: body, bodyMid: bodyMid)
        case .diskUsage:
            drawDiskIcon(draw: draw, level: level, tint: activeTint, outline: outline, body: body, bodyMid: bodyMid)
        case .cpuTemperature:
            drawThermometerIcon(draw: draw, level: level, tint: activeTint, outline: outline, body: body, bodyMid: bodyMid)
        case .fanSpeed:
            drawFanIcon(draw: draw, frame: frame, tint: activeTint, outline: outline, body: body, bodyMid: bodyMid)
        case .cpuUsage:
            drawCPUUsageIcon(draw: draw, level: level, tint: activeTint, outline: outline, body: body, bodyMid: bodyMid)
        case .gpuUsage:
            drawGPUUsageIcon(draw: draw, level: level, tint: activeTint, outline: outline, body: body, bodyMid: bodyMid)
        }

        if !isAvailable {
            drawUnavailableSlash(draw: draw, color: muted)
        }
    }

    private func drawMemoryIcon(
        draw: PixelDrawContext,
        level: Double,
        tint: NSColor,
        outline: NSColor,
        body: NSColor,
        bodyMid: NSColor
    ) {
        for y in stride(from: 7, through: 15, by: 3) {
            draw.rect(x: 3, y: y, width: 2, height: 1, color: outline)
            draw.rect(x: 17, y: y, width: 2, height: 1, color: outline)
        }

        draw.rect(x: 5, y: 5, width: 12, height: 12, color: outline)
        draw.rect(x: 6, y: 6, width: 10, height: 10, color: body)
        draw.rect(x: 8, y: 8, width: 2, height: 2, color: bodyMid)
        draw.rect(x: 12, y: 8, width: 2, height: 2, color: bodyMid)

        let fillHeight = Int((8 * level).rounded())
        draw.rect(x: 7, y: 15 - fillHeight, width: 8, height: fillHeight, color: tint.withAlphaComponent(0.85))
        draw.rect(x: 8, y: 13, width: 6, height: 1, color: tint)
    }

    private func drawDiskIcon(
        draw: PixelDrawContext,
        level: Double,
        tint: NSColor,
        outline: NSColor,
        body: NSColor,
        bodyMid: NSColor
    ) {
        draw.rect(x: 5, y: 5, width: 12, height: 2, color: outline)
        draw.rect(x: 4, y: 7, width: 14, height: 9, color: outline)
        draw.rect(x: 5, y: 6, width: 12, height: 1, color: bodyMid)
        draw.rect(x: 5, y: 8, width: 12, height: 7, color: body)

        let fillHeight = Int((7 * level).rounded())
        draw.rect(x: 6, y: 15 - fillHeight, width: 10, height: fillHeight, color: tint.withAlphaComponent(0.9))
        draw.rect(x: 5, y: 15, width: 12, height: 2, color: outline)
        draw.rect(x: 6, y: 15, width: 10, height: 1, color: bodyMid)
        draw.rect(x: 8, y: 10, width: 6, height: 1, color: tint)
    }

    private func drawThermometerIcon(
        draw: PixelDrawContext,
        level: Double,
        tint: NSColor,
        outline: NSColor,
        body: NSColor,
        bodyMid: NSColor
    ) {
        draw.rect(x: 9, y: 3, width: 4, height: 13, color: outline)
        draw.rect(x: 10, y: 4, width: 2, height: 11, color: body)
        draw.rect(x: 7, y: 14, width: 8, height: 6, color: outline)
        draw.rect(x: 8, y: 15, width: 6, height: 4, color: bodyMid)

        let columnHeight = Int((10 * level).rounded())
        draw.rect(x: 10, y: 14 - columnHeight, width: 2, height: columnHeight, color: tint)
        draw.rect(x: 9, y: 16, width: 4, height: 2, color: tint)
    }

    private func drawFanIcon(
        draw: PixelDrawContext,
        frame: Int,
        tint: NSColor,
        outline: NSColor,
        body: NSColor,
        bodyMid: NSColor
    ) {
        draw.rect(x: 6, y: 6, width: 10, height: 10, color: outline)
        draw.rect(x: 7, y: 7, width: 8, height: 8, color: body)

        if frame % 2 == 0 {
            draw.rect(x: 10, y: 3, width: 2, height: 6, color: tint)
            draw.rect(x: 10, y: 13, width: 2, height: 6, color: tint)
            draw.rect(x: 3, y: 10, width: 6, height: 2, color: tint)
            draw.rect(x: 13, y: 10, width: 6, height: 2, color: tint)
        } else {
            draw.rect(x: 6, y: 5, width: 3, height: 3, color: tint)
            draw.rect(x: 13, y: 5, width: 3, height: 3, color: tint)
            draw.rect(x: 6, y: 14, width: 3, height: 3, color: tint)
            draw.rect(x: 13, y: 14, width: 3, height: 3, color: tint)
        }

        draw.rect(x: 9, y: 9, width: 4, height: 4, color: outline)
        draw.rect(x: 10, y: 10, width: 2, height: 2, color: bodyMid)
    }

    private func drawCPUUsageIcon(
        draw: PixelDrawContext,
        level: Double,
        tint: NSColor,
        outline: NSColor,
        body: NSColor,
        bodyMid: NSColor
    ) {
        for x in stride(from: 7, through: 14, by: 3) {
            draw.rect(x: x, y: 3, width: 1, height: 2, color: outline)
            draw.rect(x: x, y: 17, width: 1, height: 2, color: outline)
        }

        for y in stride(from: 7, through: 14, by: 3) {
            draw.rect(x: 3, y: y, width: 2, height: 1, color: outline)
            draw.rect(x: 17, y: y, width: 2, height: 1, color: outline)
        }

        draw.rect(x: 5, y: 5, width: 12, height: 12, color: outline)
        draw.rect(x: 6, y: 6, width: 10, height: 10, color: body)
        draw.rect(x: 8, y: 8, width: 6, height: 6, color: bodyMid)

        let barCount = Int((4 * level).rounded())
        for index in 0..<barCount {
            draw.rect(x: 8 + index * 2, y: 12 - index, width: 1, height: 2 + index, color: tint)
        }
    }

    private func drawGPUUsageIcon(
        draw: PixelDrawContext,
        level: Double,
        tint: NSColor,
        outline: NSColor,
        body: NSColor,
        bodyMid: NSColor
    ) {
        draw.rect(x: 3, y: 7, width: 16, height: 9, color: outline)
        draw.rect(x: 4, y: 8, width: 14, height: 7, color: body)
        draw.rect(x: 8, y: 16, width: 8, height: 2, color: outline)
        draw.rect(x: 9, y: 16, width: 6, height: 1, color: bodyMid)
        draw.rect(x: 18, y: 10, width: 2, height: 3, color: outline)

        draw.rect(x: 5, y: 9, width: 5, height: 5, color: bodyMid)
        draw.rect(x: 6, y: 10, width: 3, height: 3, color: tint.withAlphaComponent(0.75))
        draw.rect(x: 7, y: 11, width: 1, height: 1, color: outline)

        let barCount = Int((4 * level).rounded())
        for index in 0..<barCount {
            draw.rect(x: 12 + index, y: 13 - index, width: 1, height: 1 + index, color: tint)
        }
    }

    private func drawUnavailableSlash(draw: PixelDrawContext, color: NSColor) {
        for offset in 0..<10 {
            draw.rect(x: 15 - offset, y: 5 + offset, width: 2, height: 1, color: color)
        }
    }
}

private struct PixelDrawContext {
    let context: CGContext
    let logicalSize: Int
    let scale: Int
    let mirrorHorizontally: Bool

    func rect(x: Int, y: Int, width: Int, height: Int, color: NSColor) {
        guard width > 0, height > 0 else {
            return
        }

        let drawX = mirrorHorizontally ? logicalSize - x - width : x
        let drawY = logicalSize - y - height
        let rect = CGRect(
            x: drawX * scale,
            y: drawY * scale,
            width: width * scale,
            height: height * scale
        )

        context.setFillColor(color.usingColorSpace(.deviceRGB)?.cgColor ?? color.cgColor)
        context.fill(rect)
    }
}
