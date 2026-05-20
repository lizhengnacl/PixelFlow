import AppKit
import CoreGraphics

final class PixelSpriteRenderer {
    private struct CacheKey: Hashable {
        let direction: TrafficDirection
        let motion: SpriteMotion
        let frame: Int
        let colorBucket: Int
    }

    private let logicalSize = 22
    private let scale = 2
    private var cache: [CacheKey: NSImage] = [:]

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
