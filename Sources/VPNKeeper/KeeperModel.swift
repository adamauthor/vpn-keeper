import AppKit
import Combine
import Foundation
import Network
import ServiceManagement
import VPNCore

@MainActor
final class KeeperModel: ObservableObject {
    @Published var profile: VPNProfile
    @Published var passwordDraft = ""
    @Published var pendingToken: TOTPToken?
    @Published var hasSavedCredentials: Bool
    @Published var keepConnected: Bool
    @Published var loginEnabled = false
    @Published var loginNeedsApproval = false
    @Published var state = "Проверка Cisco…"
    @Published var detail = ""
    @Published var diagnostic = ""
    @Published var busy = false
    @Published var connected = false
    @Published var importing = false
    @Published var importPreview: QRImportResult?
    @Published var events: [String] = []

    private let defaults = UserDefaults.standard
    private let monitor = NWPathMonitor()
    private var networkAvailable = false
    private var sleeping = false
    private var locked = false
    private var retry = RetryPolicy()
    private var retryAt: Date?
    private var active: CLIProcess?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var nextProbe = Date.distantPast
    private var automaticBlocked = false
    private var diagnosticsPassed = false
    private var generation = 0
    private var startupTask: Task<Void, Never>?
    private var savedProfile: VPNProfile?
    private var statusSubscription: AnyCancellable?
    private var lastConnectTrace: [String] = []
    private var lastFailure: String?
    private var lastAttempt: Date?

    static let ciscoPaths = ["/opt/cisco/secureclient/bin/vpn", "/opt/cisco/anyconnect/bin/vpn"]
    var executable: URL? {
        Self.ciscoPaths.first(where: FileManager.default.isExecutableFile(atPath:)).map { URL(fileURLWithPath: $0) }
    }
    var edited: Bool { profile != savedProfile || !passwordDraft.isEmpty || pendingToken != nil }
    var tokenDescription: String {
        if let token = pendingToken {
            return "\(token.label) · \(token.digits) цифр · \(token.period) сек. · сохранить"
        }
        return hasSavedCredentials
            ? "TOTP сохранён в Связке ключей" : "QR настройки TOTP или экспорт Google Authenticator"
    }

    init() {
        let stored = defaults.data(forKey: "profile").flatMap { try? JSONDecoder().decode(VPNProfile.self, from: $0) }
        profile = stored ?? VPNProfile()
        savedProfile = stored
        hasSavedCredentials = defaults.bool(forKey: "hasCredentials")
        keepConnected = defaults.bool(forKey: "keepConnected")
        automaticBlocked = defaults.bool(forKey: "automaticBlocked")
        if defaults.bool(forKey: "hasPendingImportedToken") {
            if let entry = try? KeychainStore.load(interactive: false) {
                pendingToken = entry.token
                detail = "QR импортирован локально. Заполните недостающие поля и нажмите «Подключить»."
            }
        }
        refreshLoginStatus()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let wasAvailable = self.networkAvailable
                self.networkAvailable = path.status == .satisfied
                if !self.networkAvailable {
                    self.generation += 1
                    self.active?.cancel()
                    self.state = "Ожидание сети"
                    self.connected = false
                } else if !wasAvailable {
                    self.nextProbe = .distantPast
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "kz.local.VPNKeeper.network"))
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(
            workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) {
                [weak self] _ in
                Task { @MainActor in self?.suspend() }
            })
        observers.append(
            workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) {
                [weak self] _ in
                Task { @MainActor in
                    self?.sleeping = false
                    self?.nextProbe = Date().addingTimeInterval(5)
                    self?.state = "Проверка после сна…"
                }
            })
        observers.append(
            workspace.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) {
                [weak self] _ in
                Task { @MainActor in
                    self?.locked = true
                    self?.generation += 1
                    self?.active?.cancel()
                }
            })
        observers.append(
            workspace.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) {
                [weak self] _ in
                Task { @MainActor in
                    self?.locked = false
                    self?.nextProbe = .distantPast
                }
            })
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.publishRuntime()
                await self?.tick()
                self?.publishRuntime()
            }
        }
        statusSubscription = objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.publishRuntime() }
        }
        publishRuntime()
        startupTask = Task { await diagnose() }
    }

    private func publishRuntime() {
        var status: [String: Any] = [
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
            "state": state, "detail": detail, "diagnostic": diagnostic, "busy": busy,
            "networkAvailable": networkAvailable, "sleeping": sleeping, "locked": locked,
            "diagnosticsPassed": diagnosticsPassed, "automaticBlocked": automaticBlocked,
            "hasSavedCredentials": hasSavedCredentials, "hasSavedProfile": savedProfile != nil,
            "connectTrace": lastConnectTrace,
        ]
        if let lastFailure { status["lastFailure"] = lastFailure }
        if let lastAttempt { status["lastAttempt"] = ISO8601DateFormatter().string(from: lastAttempt) }
        if let retryAt { status["retryAt"] = ISO8601DateFormatter().string(from: retryAt) }
        if let data = try? JSONSerialization.data(withJSONObject: status, options: [.sortedKeys]) {
            defaults.set(data, forKey: "runtimeStatus")
        }
    }

    private func log(_ text: String) {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        events.insert("\(stamp)  \(text)", at: 0)
        if events.count > 15 { events.removeLast() }
    }

    private func setKeeping(_ enabled: Bool) {
        keepConnected = enabled
        defaults.set(enabled, forKey: "keepConnected")
    }

    func refreshLoginStatus() {
        loginEnabled = SMAppService.mainApp.status == .enabled
        loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            refreshLoginStatus()
            detail =
                loginNeedsApproval
                ? "Разрешите VPN Keeper в настройках входа macOS." : "Настройка автозапуска обновлена."
        } catch {
            detail = "macOS не удалось изменить автозапуск. Проверьте «Объекты входа» в Системных настройках."
            refreshLoginStatus()
        }
    }

    func save() throws {
        guard !busy else { throw KeeperError("Дождитесь завершения операции Cisco.") }
        guard !importing, importPreview == nil else { throw KeeperError("Завершите выбор аккаунта в окне импорта QR.") }
        let validated = try profile.validated()
        let previous = try KeychainStore.load(interactive: true)
        guard let token = pendingToken ?? previous?.token else { throw KeeperError("Добавьте QR настройки TOTP.") }
        let entry = VaultEntry(password: passwordDraft.isEmpty ? previous?.password ?? "" : passwordDraft, token: token)
        try entry.validate(for: validated)
        try KeychainStore.save(entry)
        defaults.set(try JSONEncoder().encode(validated), forKey: "profile")
        defaults.set(true, forKey: "hasCredentials")
        defaults.removeObject(forKey: "hasPendingImportedToken")
        profile = validated
        savedProfile = validated
        passwordDraft = ""
        pendingToken = nil
        hasSavedCredentials = true
        automaticBlocked = false
        retry.reset()
        retryAt = nil
        defaults.set(false, forKey: "automaticBlocked")
        detail = "Настройки сохранены. Пароль и TOTP находятся в Связке ключей."
        log("Настройки сохранены")
    }

    func saveClicked() {
        do { try save() } catch { detail = error.localizedDescription }
    }

    func importQR(_ url: URL) {
        guard !importing, importPreview == nil else { return }
        importing = true
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) { try QRImport.readAccounts(url) }.value
                if result.requiresSelection {
                    importPreview = result
                    detail = "Выберите аккаунт VPN из QR. Остальные аккаунты не сохраняются."
                } else if let account = result.accounts.first {
                    pendingToken = try result.selectedToken(id: account.id)
                    detail = "QR прочитан локально. Нажмите «Сохранить»."
                }
            } catch {
                detail = (error as? KeeperError)?.message ?? "Не удалось распознать QR. Выберите другое изображение."
            }
            importing = false
        }
    }

    func confirmImport(id: Int) {
        guard let preview = importPreview else { return }
        do {
            pendingToken = try preview.selectedToken(id: id)
            importPreview = nil
            detail = "Аккаунт выбран. Нажмите «Сохранить» или «Подключить»."
        } catch { detail = error.localizedDescription }
    }

    func cancelImport() {
        importPreview = nil
        detail = "Импорт отменён."
    }

    func start() {
        guard !busy else { return }
        do { try save() } catch {
            detail = error.localizedDescription
            return
        }
        setKeeping(true)
        automaticBlocked = false
        retry.reset()
        retryAt = nil
        nextProbe = .distantPast
        Task { await tick(force: true) }
    }

    func pause() {
        setKeeping(false)
        generation += 1
        active?.cancel()
        retryAt = nil
        state = connected ? "VPN подключён · автоподключение выключено" : "Автоподключение выключено"
        detail = "Текущий туннель сохранится. Для отключения используйте кнопку «Отключить VPN»."
        log("Автоподключение выключено")
    }

    func shutdown() {
        generation += 1
        active?.cancel()
    }

    func disconnect() {
        guard !busy, let executable else { return }
        pause()
        Task {
            busy = true
            state = "Отключение…"
            let result = await execute(executable, .disconnect)
            busy = false
            if result == .state(.disconnected) {
                connected = false
                state = "VPN отключён"
                detail = "Автоподключение выключено."
                log("VPN отключён пользователем")
            } else if case .failed(let failure) = result {
                detail = failure.message
            }
        }
    }

    func reset() {
        guard !busy else { return }
        pause()
        do {
            try KeychainStore.delete()
            if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                try SMAppService.mainApp.unregister()
            }
            ["profile", "hasCredentials", "keepConnected", "automaticBlocked", "hasPendingImportedToken"].forEach(
                defaults.removeObject(forKey:))
            profile = VPNProfile()
            savedProfile = nil
            passwordDraft = ""
            pendingToken = nil
            hasSavedCredentials = false
            detail = "Профиль и секреты удалены. Текущий VPN-туннель не изменён."
            refreshLoginStatus()
        } catch { detail = "Не удалось полностью удалить настройки: " + error.localizedDescription }
    }

    func diagnose() async {
        guard !busy else { return }
        guard let executable else {
            diagnosticsPassed = false
            state = "Нужен Cisco Secure Client"
            diagnostic = "CLI Cisco не найден в /opt/cisco/secureclient/bin/vpn или /opt/cisco/anyconnect/bin/vpn."
            return
        }
        busy = true
        let result = await execute(executable, .state)
        busy = false
        switch result {
        case .state(let status):
            diagnosticsPassed = true
            diagnostic = "CLI Cisco доступен."
            connected = status == .connected
            state = connected ? "Cisco VPN подключён" : "Готов к подключению"
        case .failed(let failure):
            diagnosticsPassed = false
            diagnostic = failure.message
            detail = failure.message
            state = "Требуется внимание"
        }
        nextProbe = Date().addingTimeInterval(15)
    }

    private func execute(_ executable: URL, _ request: CLIProcess.Request) async -> CLIResult {
        guard CiscoTrust.isValid(executable) else { return .failed(.signing) }
        let connecting: Bool
        if case .connect = request {
            connecting = true
            lastConnectTrace = []
            lastAttempt = Date()
            lastFailure = nil
        } else {
            connecting = false
        }
        let operation = CLIProcess(
            executable: executable, request: request,
            onPhase: { [weak self] phase in
                guard connecting else { return }
                Task { @MainActor in
                    self?.lastConnectTrace.append(phase.rawValue)
                    self?.publishRuntime()
                }
            })
        active = operation
        let result = await operation.run()
        active = nil
        return result
    }

    private func suspend() {
        sleeping = true
        generation += 1
        active?.cancel()
        state = "Компьютер спит"
    }

    private func fail(_ failure: VPNFailure) {
        guard failure != .cancelled else { return }
        lastFailure = failure.rawValue
        connected = false
        if failure.retryable, let delay = retry.nextDelay() {
            retryAt = Date().addingTimeInterval(delay)
            state = "Повтор через \(Int(delay)) сек."
            detail = failure.message
            log("Сетевая ошибка; повтор через \(Int(delay)) сек.")
        } else {
            automaticBlocked = true
            retryAt = nil
            defaults.set(true, forKey: "automaticBlocked")
            state = "Автоподключение приостановлено"
            detail =
                failure.retryable ? "Лимит повторов достигнут. Проверьте сеть и нажмите «Подключить»." : failure.message
            log(failure.retryable ? "Лимит сетевых повторов достигнут" : "Вход остановлен: требуется внимание")
        }
    }

    func tick(force: Bool = false) async {
        guard !busy, !sleeping, !locked, networkAvailable else { return }
        guard force || Date() >= nextProbe else { return }
        nextProbe = Date().addingTimeInterval(15)
        if !diagnosticsPassed {
            if force { await diagnose() }
            guard diagnosticsPassed else { return }
        }
        guard let executable else { return }
        let revision = generation
        busy = true
        defer { busy = false }
        let result = await execute(executable, .state)
        guard revision == generation else { return }
        switch result {
        case .failed(let failure):
            if keepConnected && !automaticBlocked { fail(failure) } else { diagnostic = failure.message }
            return
        case .state(.connected):
            if !connected { log("Cisco сообщил: VPN подключён") }
            connected = true
            state = "Cisco VPN подключён"
            // Cisco reports global tunnel state. Do not assume which server owns it.
            detail = "Туннель Cisco активен. Адрес текущего туннеля не проверяется."
            retry.reset()
            retryAt = nil
            return
        case .state(.connecting), .state(.reconnecting):
            connected = false
            state = "Cisco устанавливает соединение…"
            return
        case .state:
            connected = false
        }
        guard keepConnected, !automaticBlocked, hasSavedCredentials, let savedProfile else {
            if !automaticBlocked { state = "VPN отключён" }
            return
        }
        if let retryAt, retryAt > Date() {
            state = "Повтор через \(max(1, Int(retryAt.timeIntervalSinceNow))) сек."
            return
        }
        do {
            let validated = try savedProfile.validated()
            guard let credentials = try KeychainStore.load(interactive: force) else {
                throw KeeperError("Пароль и QR не найдены в Связке ключей. Сохраните настройки заново.")
            }
            try credentials.validate(for: validated)
            state = "Подключение к VPN…"
            detail = "Cisco получает группу, логин, OTP и пароль."
            log("Начата попытка подключения")
            var connectedResult = await execute(executable, .connect(validated, credentials))
            if connectedResult == .failed(.clientBusy), validated.releaseCiscoGUI, revision == generation {
                state = "Освобождение управления Cisco…"
                detail = "Графический клиент Cisco мешает автоподключению. Сервис VPN продолжит работать."
                let current = await execute(executable, .state)
                guard revision == generation else { return }
                if current == .state(.connected) {
                    connectedResult = current
                } else if current == .state(.connecting) || current == .state(.reconnecting) {
                    state = "Cisco устанавливает соединение…"
                    return
                } else if current == .state(.disconnected), await CiscoGUI.releaseConnectionControl() {
                    guard revision == generation, keepConnected, !sleeping, !locked, networkAvailable else { return }
                    log("Закрыт графический Cisco для освобождения управления")
                    // The failed capability request sent no credentials. Retry once after normal Quit.
                    connectedResult = await execute(executable, .connect(validated, credentials))
                }
            }
            guard revision == generation else { return }
            switch connectedResult {
            case .state(.connected):
                connected = true
                state = "Cisco VPN подключён"
                detail = "Автоподключение включено. Проверка состояния каждые 15 секунд."
                retry.reset()
                retryAt = nil
                log("Соединение установлено")
            case .failed(let failure): fail(failure)
            default: fail(.network)
            }
        } catch {
            automaticBlocked = true
            defaults.set(true, forKey: "automaticBlocked")
            state = "Требуется настройка"
            detail = error.localizedDescription
        }
    }
}
