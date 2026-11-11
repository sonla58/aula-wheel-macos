import AppKit
import AulaWheelCore
import ServiceManagement

extension AppDelegate {
    func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let symbol: String
        if !Permissions.accessibility || !Permissions.inputMonitoring {
            symbol = "exclamationmark.triangle"
        } else if !enabled {
            symbol = "pause.circle"
        } else {
            symbol = controller.currentMode.symbol
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "AulaWheel")
            ?? NSImage(systemSymbolName: "dial.low", accessibilityDescription: "AulaWheel")
        image?.isTemplate = true
        button.image = image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(disabled("AulaWheel — \(controller.currentMode.name)"))
        menu.addItem(disabled(hid.deviceCount > 0 ? "Keyboard: connected" : "Keyboard: not found"))
        for permission in Permission.allCases where !permission.isGranted {
            menu.addItem(item("\(permission.title): missing — Fix…", #selector(openSetupPermissions)))
        }
        if let configError {
            menu.addItem(disabled("Config error: \(configError.prefix(80))"))
        }
        menu.addItem(.separator())

        for mode in controller.modes {
            let entry = item(mode.name, #selector(selectMode(_:)))
            entry.representedObject = mode.id
            entry.image = NSImage(systemSymbolName: mode.symbol, accessibilityDescription: nil)
            entry.state = mode.id == controller.currentMode.id ? .on : .off
            menu.addItem(entry)
        }
        menu.addItem(.separator())

        let speedItem = NSMenuItem(title: "Scroll Speed", action: nil, keyEquivalent: "")
        let speedMenu = NSMenu()
        for speed in ScrollSpeed.allCases {
            let entry = item(speed.rawValue.capitalized, #selector(selectSpeed(_:)))
            entry.representedObject = speed.rawValue
            entry.state = speed == controller.scrollSpeed ? .on : .off
            speedMenu.addItem(entry)
        }
        speedItem.submenu = speedMenu
        menu.addItem(speedItem)
        menu.addItem(.separator())

        let enabledItem = item("Enabled", #selector(toggleEnabled))
        enabledItem.state = enabled ? .on : .off
        menu.addItem(enabledItem)
        let loginItem = item("Launch at Login", #selector(toggleLaunchAtLogin))
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(item("Open Config File", #selector(openConfig)))
        menu.addItem(item("Reload Config", #selector(reloadConfigFromMenu)))
        menu.addItem(item("Setup Guide…", #selector(openSetup)))
        menu.addItem(.separator())
        menu.addItem(item("Quit AulaWheel", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        apply(controller.selectMode(id: id))
    }

    @objc private func selectSpeed(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let speed = ScrollSpeed(rawValue: raw) else { return }
        apply(controller.setScrollSpeed(speed))
    }

    @objc private func toggleEnabled() {
        enabled.toggle()
        if enabled { activate() } else { deactivate() }
        updateStatusIcon()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            hud.showBanner(symbol: "exclamationmark.triangle.fill", title: "Launch at Login failed",
                           subtitle: error.localizedDescription)
        }
    }

    @objc private func openConfig() {
        NSWorkspace.shared.open(store.url)
    }

    @objc private func reloadConfigFromMenu() {
        reloadConfig(force: true)
    }

    @objc private func openSetupPermissions() {
        setup.show(step: .permissions)
    }

    @objc private func openSetup() {
        setup.show(step: .welcome)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
