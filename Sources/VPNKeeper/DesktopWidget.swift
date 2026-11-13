import AppKit
import SwiftUI
import VPNCore

/// Небольшая карточка на рабочем столе: статус VPN и кнопка «Подключить / Отключить».
/// Лежит над обоями и значками, под окнами приложений, видна на всех рабочих столах и не забирает фокус.
/// Нативный WidgetKit-виджет требует полного Xcode, поэтому здесь обычное окно приложения.
@MainActor
final class DesktopWidgetController {
    private let model: KeeperModel
    private var panel: NSPanel?
    private let frameKey = "widgetFrame"

    init(model: KeeperModel) {
        self.model = model
        model.onWidgetChange = { [weak self] visible in visible ? self?.show() : self?.hide() }
        if model.widgetVisible { show() }
    }

    func show() {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 232, height: 112),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isMovableByWindowBackground = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: DesktopWidgetView(model: model))
            if let saved = UserDefaults.standard.string(forKey: frameKey) {
                let frame = NSRectFromString(saved)
                if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
                    panel.setFrame(frame, display: false)
                }
            } else if let screen = NSScreen.main {
                let area = screen.visibleFrame
                panel.setFrameOrigin(NSPoint(x: area.maxX - 232 - 24, y: area.maxY - 112 - 24))
            }
            NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification, object: panel, queue: .main
            ) { [weak panel] _ in
                guard let frame = panel?.frame else { return }
                UserDefaults.standard.set(NSStringFromRect(frame), forKey: "widgetFrame")
            }
            self.panel = panel
        }
        panel?.orderFront(nil)
    }

    func hide() { panel?.orderOut(nil) }
}

struct DesktopWidgetView: View {
    @ObservedObject var model: KeeperModel

    private var tone: Color {
        if model.connected { return .green }
        if model.busy || model.state.contains("Повтор") || model.state.contains("Подключение") { return .orange }
        return .gray
    }
    private var title: String {
        if model.connected { return "VPN подключён" }
        if model.busy { return "Подключение…" }
        return "VPN отключён"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(tone).frame(width: 9, height: 9)
                Text(title).font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 0)
                Image(systemName: model.connected ? "lock.shield.fill" : "lock.shield")
                    .foregroundStyle(model.connected ? Color.teal : Color.secondary)
            }
            Text(model.modeText).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            Button(action: toggle) {
                Text(model.connected ? "Отключить" : "Подключить").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(model.connected ? .gray : .teal).controlSize(.regular)
            .disabled(model.busy && !model.connected)
        }
        .padding(14).frame(width: 232, height: 112)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.18), lineWidth: 0.5))
    }

    private func toggle() {
        if model.connected { model.handle(.disconnect) } else { model.handle(.connect(holdMinutes: nil)) }
    }
}
