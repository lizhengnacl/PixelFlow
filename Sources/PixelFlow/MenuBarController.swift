import AppKit
import Foundation

final class MenuBarController: NSObject, NSMenuDelegate {
    private let renderer = PixelSpriteRenderer()
    private let monitor = NetworkStatsMonitor()
    private let systemMonitor = SystemStatsMonitor()
    private let launchAtLoginController = LaunchAtLoginController()

    private let downloadStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let uploadStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var systemMetricStatusItems: [SystemMetricKind: SystemMetricStatusItemController] = [:]

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
    private let networkHeaderItem = NSMenuItem(title: "网络流量", action: nil, keyEquivalent: "")
    private let downloadSpeedItem = NSMenuItem(title: "↓ 下载  0 B/s", action: nil, keyEquivalent: "")
    private let uploadSpeedItem = NSMenuItem(title: "↑ 上传  0 B/s", action: nil, keyEquivalent: "")
    private let sourceItem = NSMenuItem(title: "来源: 接口计数", action: nil, keyEquivalent: "")
    private let diagnosticsItem = NSMenuItem(title: "采集诊断", action: nil, keyEquivalent: "")
    private let systemStatusHeaderItem = NSMenuItem(title: "系统状态", action: nil, keyEquivalent: "")
    private let displayItemsItem = NSMenuItem(title: "显示项目", action: nil, keyEquivalent: "")
    private let launchAtLoginItem = NSMenuItem(title: "开机自动启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let ninjaThemeItem = NSMenuItem(title: "忍者", action: nil, keyEquivalent: "")
    private var trafficToggleButtons: [TrafficDirection: NSButton] = [:]
    private var systemMetricValueItems: [SystemMetricKind: NSMenuItem] = [:]
    private var systemMetricToggleButtons: [SystemMetricKind: NSButton] = [:]

    private var animationTimer: Timer?
    private var lastAnimationDate = Date()
    private var visibleTrafficDirections = TrafficVisibilityStore.load()
    private var visibleSystemMetrics = SystemMetricVisibilityStore.load()
    private var currentSystemSnapshot = SystemMetricsSnapshot.empty
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

        ensureVisibleStatusItem()
        buildMenu()
        uploadStatusItem.menu = menu
        downloadStatusItem.menu = menu
        syncTrafficStatusItems()
        syncSystemMetricStatusItems()

        monitor.onUpdate = { [weak self] rates in
            self?.updateRates(rates)
        }
        monitor.start()

        systemMonitor.onUpdate = { [weak self] snapshot in
            self?.updateSystemMetrics(snapshot)
        }
        systemMonitor.start()

        startAnimationTimer()
        observeWorkspacePowerEvents()
    }

    func stop() {
        monitor.stop()
        systemMonitor.stop()
        animationTimer?.invalidate()
        animationTimer = nil
        systemMetricStatusItems.values.forEach { $0.removeFromStatusBar() }
        systemMetricStatusItems.removeAll()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func buildMenu() {
        menu.delegate = self
        menu.autoenablesItems = false

        networkHeaderItem.isEnabled = false
        uploadSpeedItem.isEnabled = true
        downloadSpeedItem.isEnabled = true
        sourceItem.isEnabled = false
        menu.addItem(networkHeaderItem)
        menu.addItem(downloadSpeedItem)
        menu.addItem(uploadSpeedItem)
        menu.addItem(sourceItem)
        menu.addItem(.separator())

        systemStatusHeaderItem.isEnabled = false
        menu.addItem(systemStatusHeaderItem)
        for kind in SystemMetricKind.menuOrder {
            let item = NSMenuItem(title: "\(kind.shortLabel)  采集中", action: nil, keyEquivalent: "")
            item.isEnabled = true
            menu.addItem(item)
            systemMetricValueItems[kind] = item
        }
        menu.addItem(.separator())

        let displayItemsMenu = NSMenu(title: "显示项目")
        for direction in [TrafficDirection.download, .upload] {
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            item.view = makeTrafficToggleButton(for: direction)
            displayItemsMenu.addItem(item)
        }

        displayItemsMenu.addItem(.separator())

        for kind in SystemMetricKind.menuOrder {
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            item.view = makeSystemMetricToggleButton(for: kind)
            displayItemsMenu.addItem(item)
        }
        displayItemsItem.submenu = displayItemsMenu
        menu.addItem(displayItemsItem)
        menu.addItem(.separator())

        diagnosticsItem.submenu = NSMenu(title: "采集诊断")
        menu.addItem(diagnosticsItem)
        menu.addItem(.separator())

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
        systemMetricStatusItems.values.forEach { $0.tick(deltaTime: deltaTime) }
    }

    private func updateRates(_ rates: TrafficRates) {
        currentRates = rates
        uploadAnimator.setRate(rates.uploadBytesPerSecond)
        downloadAnimator.setRate(rates.downloadBytesPerSecond)
        updateMenuItems()
    }

    private func updateSystemMetrics(_ snapshot: SystemMetricsSnapshot) {
        currentSystemSnapshot = snapshot

        for (kind, controller) in systemMetricStatusItems {
            controller.setReading(snapshot.reading(for: kind))
        }

        updateSystemMetricMenu()
    }

    private func updateMenuItems() {
        uploadSpeedItem.title = "\(TrafficDirection.upload.arrow) \(TrafficDirection.upload.label)  \(TrafficFormatter.rate(currentRates.uploadBytesPerSecond))"
        downloadSpeedItem.title = "\(TrafficDirection.download.arrow) \(TrafficDirection.download.label)  \(TrafficFormatter.rate(currentRates.downloadBytesPerSecond))"
        sourceItem.title = "来源: \(currentRates.source.label)"
        updateDiagnosticsMenu()
        updateTrafficDisplayMenu()
        updateSystemMetricMenu()

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

    private func updateSystemMetricMenu() {
        for kind in SystemMetricKind.menuOrder {
            let reading = currentSystemSnapshot.reading(for: kind)

            if let valueItem = systemMetricValueItems[kind] {
                valueItem.title = "\(kind.shortLabel)  \(reading.valueText)"
                valueItem.isEnabled = true
            }

            if let toggleButton = systemMetricToggleButtons[kind] {
                toggleButton.state = visibleSystemMetrics.contains(kind) ? .on : .off
            }
        }
    }

    private func updateTrafficDisplayMenu() {
        for direction in [TrafficDirection.download, .upload] {
            if let toggleButton = trafficToggleButtons[direction] {
                toggleButton.state = visibleTrafficDirections.contains(direction) ? .on : .off
            }
        }
    }

    private func makeTrafficToggleButton(for direction: TrafficDirection) -> NSButton {
        let button = NSButton(
            checkboxWithTitle: "\(direction.label)网速",
            target: self,
            action: #selector(toggleTrafficButton)
        )
        button.identifier = NSUserInterfaceItemIdentifier(direction.rawValue)
        button.font = .menuFont(ofSize: 0)
        button.state = visibleTrafficDirections.contains(direction) ? .on : .off
        button.frame = NSRect(x: 0, y: 0, width: 168, height: 24)
        button.setButtonType(.switch)
        trafficToggleButtons[direction] = button
        return button
    }

    private func makeSystemMetricToggleButton(for kind: SystemMetricKind) -> NSButton {
        let button = NSButton(checkboxWithTitle: kind.label, target: self, action: #selector(toggleSystemMetricButton))
        button.identifier = NSUserInterfaceItemIdentifier(kind.rawValue)
        button.font = .menuFont(ofSize: 0)
        button.state = visibleSystemMetrics.contains(kind) ? .on : .off
        button.frame = NSRect(x: 0, y: 0, width: 168, height: 24)
        button.setButtonType(.switch)
        systemMetricToggleButtons[kind] = button
        return button
    }

    private func syncTrafficStatusItems() {
        uploadStatusItem.isVisible = visibleTrafficDirections.contains(.upload)
        downloadStatusItem.isVisible = visibleTrafficDirections.contains(.download)
    }

    private func syncSystemMetricStatusItems() {
        for kind in SystemMetricKind.menuOrder {
            if visibleSystemMetrics.contains(kind) {
                if systemMetricStatusItems[kind] == nil {
                    let controller = SystemMetricStatusItemController(
                        kind: kind,
                        menu: menu,
                        renderer: renderer
                    )
                    controller.setReading(currentSystemSnapshot.reading(for: kind))
                    systemMetricStatusItems[kind] = controller
                }
            } else if let controller = systemMetricStatusItems.removeValue(forKey: kind) {
                controller.removeFromStatusBar()
            }
        }
    }

    private func ensureVisibleStatusItem() {
        guard visibleTrafficDirections.isEmpty, visibleSystemMetrics.isEmpty else {
            return
        }

        visibleTrafficDirections.insert(.download)
        TrafficVisibilityStore.save(visibleTrafficDirections)
    }

    private func hasVisibleStatusItem(
        trafficDirections: Set<TrafficDirection>,
        systemMetrics: Set<SystemMetricKind>
    ) -> Bool {
        !trafficDirections.isEmpty || !systemMetrics.isEmpty
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
        systemMonitor.pause()
        animationTimer?.fireDate = .distantFuture
    }

    @objc private func systemDidWake() {
        monitor.resume()
        systemMonitor.resume()
        lastAnimationDate = Date()
        animationTimer?.fireDate = Date()
    }

    @objc private func toggleTrafficButton(_ sender: NSButton) {
        guard
            let rawValue = sender.identifier?.rawValue,
            let direction = TrafficDirection(rawValue: rawValue)
        else {
            return
        }

        var nextDirections = visibleTrafficDirections
        if sender.state == .on {
            nextDirections.insert(direction)
        } else {
            nextDirections.remove(direction)
        }

        guard hasVisibleStatusItem(trafficDirections: nextDirections, systemMetrics: visibleSystemMetrics) else {
            sender.state = .on
            return
        }

        visibleTrafficDirections = nextDirections
        TrafficVisibilityStore.save(visibleTrafficDirections)
        syncTrafficStatusItems()
        updateTrafficDisplayMenu()
    }

    @objc private func toggleSystemMetricButton(_ sender: NSButton) {
        guard
            let rawValue = sender.identifier?.rawValue,
            let kind = SystemMetricKind(rawValue: rawValue)
        else {
            return
        }

        var nextMetrics = visibleSystemMetrics
        if sender.state == .on {
            nextMetrics.insert(kind)
        } else {
            nextMetrics.remove(kind)
        }

        guard hasVisibleStatusItem(trafficDirections: visibleTrafficDirections, systemMetrics: nextMetrics) else {
            sender.state = .on
            return
        }

        visibleSystemMetrics = nextMetrics
        SystemMetricVisibilityStore.save(visibleSystemMetrics)
        syncSystemMetricStatusItems()
        updateSystemMetricMenu()
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
        alert.informativeText = "macOS 菜单栏像素风网络流量与系统指标动画\n上传、下载和系统指标会根据实时数据改变动画速度与颜色。"
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

private enum TrafficVisibilityStore {
    private static let key = "visibleTrafficDirections"

    static func load() -> Set<TrafficDirection> {
        guard let rawValues = UserDefaults.standard.array(forKey: key) as? [String] else {
            return [.upload, .download]
        }

        return Set(rawValues.compactMap(TrafficDirection.init(rawValue:)))
    }

    static func save(_ directions: Set<TrafficDirection>) {
        let rawValues = [TrafficDirection.download, .upload]
            .filter { directions.contains($0) }
            .map(\.rawValue)
        UserDefaults.standard.set(rawValues, forKey: key)
    }
}

private enum SystemMetricVisibilityStore {
    private static let key = "visibleSystemMetrics"

    static func load() -> Set<SystemMetricKind> {
        guard let rawValues = UserDefaults.standard.array(forKey: key) as? [String] else {
            return Set(SystemMetricKind.allCases)
        }

        return Set(rawValues.compactMap(SystemMetricKind.init(rawValue:)))
    }

    static func save(_ metrics: Set<SystemMetricKind>) {
        let rawValues = SystemMetricKind.allCases
            .filter { metrics.contains($0) }
            .map(\.rawValue)
        UserDefaults.standard.set(rawValues, forKey: key)
    }
}
