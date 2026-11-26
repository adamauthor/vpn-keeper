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
    private var placing = false
    private static let size = NSSize(width: 232, height: 112)
    private static let margin: CGFloat = 24
    private static let placementKey = "widgetPlacement"

    init(model: KeeperModel) {
        self.model = model
        model.onWidgetChange = { [weak self] visible in visible ? self?.show() : self?.hide() }
        if model.widgetVisible { show() }
        // Подключили/отключили монитор, поменяли разрешение или расположение экранов — ставим виджет заново.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.place() }
        }
    }

    func show() {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: Self.size),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: DesktopWidgetView(model: model))
            NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification, object: panel, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.remember() }
            }
            self.panel = panel
            place()
        }
        panel?.orderFront(nil)
    }

    func hide() { panel?.orderOut(nil) }

    /// Позиция хранится относительно экрана: его номер и отступ от правого верхнего угла рабочей области.
    /// Так виджет остаётся на «своём» мониторе в том же углу, как бы ни менялась раскладка экранов.
    private struct Placement: Codable {
        var display: UInt32
        var right: CGFloat
        var top: CGFloat
    }

    private static func displayID(_ screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private func place() {
        guard let panel, let primary = NSScreen.screens.first else { return }
        let saved = UserDefaults.standard.data(forKey: Self.placementKey)
            .flatMap { try? JSONDecoder().decode(Placement.self, from: $0) }
        let screen = saved.flatMap { p in NSScreen.screens.first { Self.displayID($0) == p.display } } ?? primary
        let area = screen.visibleFrame
        let right = saved.map { $0.right } ?? Self.margin
        let top = saved.map { $0.top } ?? Self.margin
        // Целиком внутри рабочей области экрана, даже если он стал меньше.
        let x = min(max(area.maxX - right - Self.size.width, area.minX), area.maxX - Self.size.width)
        let y = min(max(area.maxY - top - Self.size.height, area.minY), area.maxY - Self.size.height)
        placing = true
        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: Self.size), display: true)
        placing = false
    }

    /// Сохраняем только перемещение пользователем: временную перестановку на другой экран (свой монитор отключён)
    /// не запоминаем, чтобы при его возвращении виджет вернулся на место.
    private func remember() {
        guard !placing, let panel, let screen = panel.screen, let display = Self.displayID(screen) else { return }
        let area = screen.visibleFrame
        let placement = Placement(
            display: display, right: area.maxX - panel.frame.maxX, top: area.maxY - panel.frame.maxY)
        if let data = try? JSONEncoder().encode(placement) {
            UserDefaults.standard.set(data, forKey: Self.placementKey)
        }
    }
}

/// Подложка карточки, за которую её можно перетащить. SwiftUI-содержимое не умеет двигать окно «за фон»,
/// поэтому перетаскивание запускается явно; кнопка лежит поверх и получает свои нажатия как обычно.
private struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
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
        .background(WindowDragArea())
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.18), lineWidth: 0.5))
    }

    private func toggle() {
        if model.connected { model.handle(.disconnect) } else { model.handle(.connect(holdMinutes: nil)) }
    }
}
