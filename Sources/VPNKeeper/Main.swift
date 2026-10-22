import AppKit
import Combine
import Darwin
import SwiftUI
import VPNCore

@main
enum Main {
    @MainActor static func main() {
        if CommandLine.arguments.count > 1 {
            do {
                try CommandInterface.run(Array(CommandLine.arguments.dropFirst()))
                exit(0)
            } catch {
                try? CommandInterface.output([
                    "error": (error as? KeeperError)?.message ?? "Не удалось выполнить локальную команду."
                ])
                exit(1)
            }
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = KeeperModel()
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private var subscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.toolTip = "VPN Keeper"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        subscription = model.$connected.sink { [weak self] connected in
            self?.statusItem.button?.image = NSImage(
                systemSymbolName: connected ? "lock.shield.fill" : "lock.shield", accessibilityDescription: "VPN Keeper"
            )
        }
        if !model.hasSavedCredentials || model.pendingToken != nil { showSettings() }
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "VPN Keeper")
        let quitItem = NSMenuItem(title: "Выйти из VPN Keeper", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Правка")
        for (title, action, key) in [
            ("Отменить", "undo:", "z"), ("Вырезать", "cut:", "x"),
            ("Копировать", "copy:", "c"), ("Вставить", "paste:", "v"),
            ("Выбрать всё", "selectAll:", "a"),
        ] {
            editMenu.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        let state = NSMenuItem(title: model.state, action: nil, keyEquivalent: "")
        state.isEnabled = false
        menu.addItem(state)
        menu.addItem(.separator())
        add("Настройки…", action: #selector(showSettings), to: menu, key: ",")
        add("Подключить и включить автоподключение", action: #selector(connect), to: menu, enabled: !model.busy)
        add("Выключить автоподключение", action: #selector(pause), to: menu, enabled: model.keepConnected)
        add("Отключить VPN", action: #selector(disconnect), to: menu, enabled: model.connected && !model.busy)
        menu.addItem(.separator())
        add("Открыть Cisco Secure Client", action: #selector(openCisco), to: menu)
        add("Выйти из VPN Keeper", action: #selector(quit), to: menu, key: "q")
    }

    private func add(_ title: String, action: Selector, to menu: NSMenu, key: String = "", enabled: Bool = true) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.isEnabled = enabled
        menu.addItem(item)
    }

    @objc func showSettings() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 790),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            window.title = "VPN Keeper"
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.minSize = NSSize(width: 610, height: 620)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        model.refreshLoginStatus()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    @objc private func connect() {
        showSettings()
        model.start()
    }
    @objc private func pause() { model.pause() }
    @objc private func disconnect() { model.disconnect() }
    @objc private func openCisco() {
        let url = URL(fileURLWithPath: "/Applications/Cisco/Cisco Secure Client.app")
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
    @objc private func quit() {
        model.shutdown()
        NSApp.terminate(nil)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
