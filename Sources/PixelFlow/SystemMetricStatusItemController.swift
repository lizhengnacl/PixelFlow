import AppKit
import Foundation

final class SystemMetricStatusItemController {
    private let kind: SystemMetricKind
    private let renderer: PixelSpriteRenderer
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    private var reading: SystemMetricReading?
    private var frameIndex = 0
    private var frameAccumulator: TimeInterval = 0
    private var needsRender = true

    init(kind: SystemMetricKind, menu: NSMenu, renderer: PixelSpriteRenderer) {
        self.kind = kind
        self.renderer = renderer

        configureButton()
        statusItem.menu = menu
        render()
    }

    func setReading(_ reading: SystemMetricReading) {
        self.reading = reading
        if let diagnostic = reading.diagnostic {
            statusItem.button?.toolTip = "\(kind.label): \(reading.valueText)\n\(diagnostic)"
        } else {
            statusItem.button?.toolTip = "\(kind.label): \(reading.valueText)"
        }
        needsRender = true
    }

    func tick(deltaTime: TimeInterval) {
        guard kind == .fanSpeed else {
            if needsRender {
                render()
            }
            return
        }

        guard reading?.isAvailable == true else {
            if needsRender {
                render()
            }
            return
        }

        let normalizedSpeed = reading?.normalizedValue ?? 0
        guard normalizedSpeed > 0.01 else {
            if needsRender {
                render()
            }
            return
        }

        let framesPerSecond = 2 + normalizedSpeed * 10
        frameAccumulator += deltaTime

        while frameAccumulator >= 1 / framesPerSecond {
            frameAccumulator -= 1 / framesPerSecond
            frameIndex = (frameIndex + 1) % 4
            needsRender = true
        }

        if needsRender {
            render()
        }
    }

    func removeFromStatusBar() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func configureButton() {
        statusItem.length = NSStatusItem.squareLength

        guard let button = statusItem.button else {
            return
        }

        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyUpOrDown
        button.toolTip = kind.label
    }

    private func render() {
        let currentReading = reading ?? SystemMetricReading(
            kind: kind,
            valueText: "采集中",
            normalizedValue: 0,
            isAvailable: false,
            diagnostic: "尚未采集"
        )

        statusItem.button?.image = renderer.image(
            metric: kind,
            frame: frameIndex,
            normalizedValue: currentReading.normalizedValue,
            isAvailable: currentReading.isAvailable
        )
        needsRender = false
    }
}
