import AppKit
import Foundation

final class StatusItemAnimator {
    private let statusItem: NSStatusItem
    private let direction: TrafficDirection
    private let renderer: PixelSpriteRenderer

    private var bytesPerSecond: Double = 0
    private var frameIndex: Int = 0
    private var frameAccumulator: TimeInterval = 0
    private var needsRender = true
    private var lastProfile = AnimationProfile.make(for: 0)

    init(
        statusItem: NSStatusItem,
        direction: TrafficDirection,
        renderer: PixelSpriteRenderer
    ) {
        self.statusItem = statusItem
        self.direction = direction
        self.renderer = renderer

        configureButton()
        render()
    }

    func setRate(_ bytesPerSecond: Double) {
        self.bytesPerSecond = bytesPerSecond
        needsRender = true
    }

    func tick(deltaTime: TimeInterval) {
        let profile = AnimationProfile.make(for: bytesPerSecond)

        if profile.motion != lastProfile.motion {
            frameIndex = 0
            frameAccumulator = 0
            needsRender = true
        }

        frameAccumulator += deltaTime
        while frameAccumulator >= profile.frameDuration {
            frameAccumulator -= profile.frameDuration
            frameIndex = (frameIndex + 1) % profile.motion.frameCount
            needsRender = true
        }

        lastProfile = profile

        if needsRender {
            render(profile: profile)
        }
    }

    private func configureButton() {
        statusItem.length = NSStatusItem.squareLength

        guard let button = statusItem.button else {
            return
        }

        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyUpOrDown
        button.toolTip = "PixelFlow \(direction.label)"
    }

    private func render(profile: AnimationProfile? = nil) {
        let profile = profile ?? AnimationProfile.make(for: bytesPerSecond)
        let image = renderer.image(
            direction: direction,
            motion: profile.motion,
            frame: frameIndex,
            normalizedTraffic: profile.normalizedTraffic
        )

        statusItem.button?.image = image
        needsRender = false
    }
}
