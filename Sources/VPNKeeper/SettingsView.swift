import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import VPNCore

struct SettingsView: View {
    @ObservedObject var model: KeeperModel
    @State private var resetting = false
    @State private var dropTargeted = false
    @FocusState private var passwordFocused: Bool
    @State private var passwordKeyboardUnavailable = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: model.connected ? "lock.shield.fill" : "lock.shield")
                    .font(.system(size: 31, weight: .medium)).foregroundStyle(.teal)
                    .frame(width: 56, height: 56).background(
                        .teal.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 4) {
                    Text("VPN Keeper").font(.title2.bold())
                    Text("Автоподключение через Cisco Secure Client")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(
                        "Версия \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev") · английская раскладка для пароля"
                    )
                    .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Circle().fill(model.connected ? Color.green : Color.orange).frame(width: 8, height: 8)
                            Text(model.state).font(.headline)
                            Spacer()
                            Text(model.keepConnected ? "АВТО ВКЛ" : "АВТО ВЫКЛ")
                                .font(.caption2.bold()).foregroundStyle(.secondary)
                        }
                        if !model.detail.isEmpty {
                            Text(model.detail).font(.callout).foregroundStyle(.secondary).fixedSize(
                                horizontal: false, vertical: true)
                        }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))

                    GroupBox {
                        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                            row("Адрес VPN") {
                                TextField("vpn.example.com или vpn.example.com/group", text: $model.profile.server)
                                    .accessibilityIdentifier("server")
                            }
                            row("Группа") {
                                TextField("Точное название или номер группы", text: $model.profile.group)
                                    .accessibilityIdentifier("group")
                            }
                            row("Логин") {
                                TextField("Имя пользователя", text: $model.profile.username)
                                    .accessibilityIdentifier("username")
                            }
                            row("Пароль") {
                                VStack(alignment: .leading, spacing: 5) {
                                    SecureField(
                                        model.hasSavedCredentials
                                            ? "Сохранён · оставьте пустым, чтобы не менять" : "Пароль VPN",
                                        text: $model.passwordDraft
                                    )
                                    .accessibilityIdentifier("password")
                                    .focused($passwordFocused)
                                    .help("При выборе поля включается английская раскладка")
                                    if passwordKeyboardUnavailable {
                                        Text(
                                            "Не удалось включить английскую раскладку. Выберите её вручную в строке меню macOS."
                                        )
                                        .font(.caption).foregroundStyle(.orange)
                                        .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }.textFieldStyle(.roundedBorder).padding(12)
                    } label: {
                        Label("Подключение", systemImage: "network").font(.headline)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: "qrcode").font(.system(size: 30)).foregroundStyle(.teal)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(model.tokenDescription).font(.callout)
                                    Text("Исходный QR или экспорт · можно перетащить файл сюда")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(model.importing ? "Чтение…" : "Выбрать QR…", action: chooseQR)
                                    .disabled(model.importing || model.busy)
                            }
                            Picker("Порядок полей", selection: $model.profile.authMode) {
                                ForEach(VPNCore.AuthMode.allCases) { mode in Text(mode.title).tag(mode) }
                            }
                            Text(
                                "QR распознаётся на этом Mac. Пароль и секрет TOTP сохраняются в Связке ключей без синхронизации iCloud. Исходная картинка не копируется."
                            )
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }.padding(12)
                    } label: {
                        Label("Одноразовые коды", systemImage: "key").font(.headline)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 8).stroke(dropTargeted ? Color.teal : Color.clear, lineWidth: 2)
                    )
                    .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted, perform: drop)

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle(
                                "Запускать VPN Keeper после входа в macOS",
                                isOn: Binding(
                                    get: { model.loginEnabled }, set: { model.setLogin($0) }))
                            if model.loginNeedsApproval {
                                Button("Разрешить в настройках macOS…") { SMAppService.openSystemSettingsLoginItems() }
                            }
                            Toggle(
                                "Закрывать графический Cisco при конфликте подключения",
                                isOn: $model.profile.releaseCiscoGUI)
                            Text(
                                "Утилита запрашивает обычный выход из окна Cisco, только когда оно блокирует подключение и VPN отключён. Системный сервис Cisco остаётся работать."
                            )
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Toggle("Автоматически принимать баннер VPN", isOn: $model.profile.acceptBanner)
                            Text(
                                "Включайте принятие баннера после того, как прочитаете его в Cisco. При разрыве соединения: до 3 повторов с паузами 30, 60 и 120 секунд. Ошибка входа останавливает повторы."
                            )
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }.padding(12)
                    } label: {
                        Label("Автоматизация", systemImage: "arrow.triangle.2.circlepath").font(.headline)
                    }

                    DisclosureGroup("Диагностика и события") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(model.diagnostic).font(.callout).textSelection(.enabled)
                            HStack {
                                Button("Проверить Cisco") { Task { await model.diagnose() } }.disabled(model.busy)
                                Button("Открыть Cisco") {
                                    NSWorkspace.shared.openApplication(
                                        at: URL(fileURLWithPath: "/Applications/Cisco/Cisco Secure Client.app"),
                                        configuration: .init())
                                }
                            }
                            ForEach(Array(model.events.enumerated()), id: \.offset) { _, event in
                                Text(event).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                    }
                    HStack {
                        Text("Закрытие окна оставляет приложение в строке меню.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Удалить профиль…", role: .destructive) { resetting = true }.disabled(model.busy)
                    }
                }.padding(24)
            }
            Divider()
            HStack(spacing: 10) {
                Button("Сохранить") { model.saveClicked() }.disabled(model.busy || model.importing)
                if model.keepConnected { Button("Выключить авто") { model.pause() } }
                Spacer()
                if model.connected {
                    Button("Отключить VPN") { model.disconnect() }.disabled(model.busy)
                }
                Button("Подключить") { model.start() }
                    .buttonStyle(.borderedProminent).disabled(model.busy || model.importing)
                    .help("Сохранить настройки, подключиться и восстанавливать VPN при разрывах")
            }.padding(18)
        }
        .tint(.teal)
        .frame(minWidth: 610, minHeight: 600)
        .onChange(of: passwordFocused) { focused in
            if focused { selectPasswordKeyboard() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if passwordFocused { selectPasswordKeyboard() }
        }
        .sheet(item: $model.importPreview) { preview in
            AccountImportView(preview: preview, confirm: model.confirmImport, cancel: model.cancelImport)
                .interactiveDismissDisabled()
        }
        .confirmationDialog("Удалить профиль, пароль и секрет TOTP?", isPresented: $resetting) {
            Button("Удалить профиль и секреты", role: .destructive) { model.reset() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Автозапуск будет выключен. Текущий VPN-туннель останется активным.")
        }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            content().frame(maxWidth: .infinity)
        }
    }
    private func selectPasswordKeyboard() {
        passwordKeyboardUnavailable = !PasswordKeyboard.selectEnglish()
    }
    private func chooseQR() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .bmp]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Выберите QR настройки TOTP или экспорта Google Authenticator. Он будет прочитан локально."
        if panel.runModal() == .OK, let url = panel.url { model.importQR(url) }
    }
    private func drop(_ providers: [NSItemProvider]) -> Bool {
        guard !model.busy, !model.importing, let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url, url.isFileURL else { return }
            Task { @MainActor in model.importQR(url) }
        }
        return true
    }
}
