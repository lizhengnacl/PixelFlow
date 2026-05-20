import AppKit
import Foundation

final class MenuBarController: NSObject, NSMenuDelegate {
    private let renderer = PixelSpriteRenderer()
    private let monitor = NetworkStatsMonitor()
    private let launchAtLoginController = LaunchAtLoginController()

    private let downloadStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let uploadStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    private lazy var uploadAnimator = StatusItemAnimator(
        statusItem: uploadStatusItem,
        direction: .upload,
        renderer: renderer
    )
    private lazy var downloadAnimator = StatusItemAnimator(
        statusItem: downloadStatusItem,
        direction: .download,
        renderer: renderer
    )

    private let menu = NSMenu()
    private let uploadSpeedItem = NSMenuItem(title: "↑ 上传: 0 B/s", action: nil, keyEquivalent: "")
    private let downloadSpeedItem = NSMenuItem(title: "↓ 下载: 0 B/s", action: nil, keyEquivalent: "")
    private let sourceItem = NSMenuItem(title: "来源: 接口计数", action: nil, keyEquivalent: "")
    private let diagnosticsItem = NSMenuItem(title: "采集诊断", action: nil, keyEquivalent: "")
    private let launchAtLoginItem = NSMenuItem(title: "开机自动启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let ninjaThemeItem = NSMenuItem(title: "忍者", action: nil, keyEquivalent: "")

    private var animationTimer: Timer?
    private var lastAnimationDate = Date()
    private var currentRates = TrafficRates(
        uploadBytesPerSecond: 0,
        downloadBytesPerSecond: 0,
        timestamp: Date(),
        source: .interfaceCounters,
        interfaceRates: []
    )

    func start() {
        _ = uploadAnimator
        _ = downloadAnimator

        buildMenu()
        uploadStatusItem.menu = menu
        downloadStatusItem.menu = menu

        monitor.onUpdate = { [weak self] rates in
            self?.updateRates(rates)
        }
        monitor.start()

        startAnimationTimer()
        observeWorkspacePowerEvents()
    }

    func stop() {
        monitor.stop()
        animationTimer?.invalidate()
        animationTimer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func buildMenu() {
        menu.delegate = self
        menu.autoenablesItems = false

        uploadSpeedItem.isEnabled = true
        downloadSpeedItem.isEnabled = true
        sourceItem.isEnabled = false
        menu.addItem(uploadSpeedItem)
        menu.addItem(downloadSpeedItem)
        menu.addItem(sourceItem)
        menu.addItem(.separator())

        diagnosticsItem.submenu = NSMenu(title: "采集诊断")
        menu.addItem(diagnosticsItem)

        let themeItem = NSMenuItem(title: "主题: 忍者", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu(title: "主题")
        ninjaThemeItem.state = .on
        ninjaThemeItem.isEnabled = false
        themeMenu.addItem(ninjaThemeItem)
        themeItem.submenu = themeMenu
        menu.addItem(themeItem)

        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)
        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "关于 PixelFlow", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        updateMenuItems()
    }

    private func startAnimationTimer() {
        lastAnimationDate = Date()

        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tickAnimation()
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func tickAnimation() {
        let now = Date()
        let deltaTime = min(0.1, now.timeIntervalSince(lastAnimationDate))
        lastAnimationDate = now

        uploadAnimator.tick(deltaTime: deltaTime)
        downloadAnimator.tick(deltaTime: deltaTime)
    }

    private func updateRates(_ rates: TrafficRates) {
        currentRates = rates
        uploadAnimator.setRate(rates.uploadBytesPerSecond)
        downloadAnimator.setRate(rates.downloadBytesPerSecond)
        updateMenuItems()
    }

    private func updateMenuItems() {
        uploadSpeedItem.title = "\(TrafficDirection.upload.arrow) \(TrafficDirection.upload.label): \(TrafficFormatter.rate(currentRates.uploadBytesPerSecond))"
        downloadSpeedItem.title = "\(TrafficDirection.download.arrow) \(TrafficDirection.download.label): \(TrafficFormatter.rate(currentRates.downloadBytesPerSecond))"
        sourceItem.title = "来源: \(currentRates.source.label)"
        updateDiagnosticsMenu()

        if launchAtLoginController.isAvailable {
            launchAtLoginItem.title = "开机自动启动"
            launchAtLoginItem.isEnabled = true
            launchAtLoginItem.state = launchAtLoginController.isEnabled ? .on : .off
        } else {
            launchAtLoginItem.title = "开机自动启动（需 .app）"
            launchAtLoginItem.isEnabled = false
            launchAtLoginItem.state = .off
        }
    }

    private func updateDiagnosticsMenu() {
        let diagnosticsMenu = diagnosticsItem.submenu ?? NSMenu(title: "采集诊断")
        diagnosticsMenu.removeAllItems()

        if currentRates.interfaceRates.isEmpty {
            let item = NSMenuItem(title: "无接口增量", action: nil, keyEquivalent: "")
            item.isEnabled = false
            diagnosticsMenu.addItem(item)
        } else {
            for rate in currentRates.interfaceRates.prefix(8) {
                let item = NSMenuItem(
                    title: "\(rate.name) ↓ \(TrafficFormatter.rate(rate.downloadBytesPerSecond))  ↑ \(TrafficFormatter.rate(rate.uploadBytesPerSecond))",
                    action: nil,
                    keyEquivalent: ""
                )
                item.isEnabled = false
                diagnosticsMenu.addItem(item)
            }
        }

        diagnosticsItem.submenu = diagnosticsMenu
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateMenuItems()
    }

    private func observeWorkspacePowerEvents() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func systemWillSleep() {
        monitor.pause()
        animationTimer?.fireDate = .distantFuture
    }

    @objc private func systemDidWake() {
        monitor.resume()
        lastAnimationDate = Date()
        animationTimer?.fireDate = Date()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try launchAtLoginController.setEnabled(!launchAtLoginController.isEnabled)
            updateMenuItems()
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "PixelFlow"
        alert.informativeText = "macOS 菜单栏像素风网络流量动画\n上传和下载角色会根据实时网络速率改变动画速度与颜色。"
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "PixelFlow"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
