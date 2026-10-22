import Foundation

public enum VPNFailure: String, Error, Equatable {
    case authentication, certificate, banner, group, unsupported, signing, service, clientBusy, network, timeout,
        cancelled
    public var message: String {
        switch self {
        case .authentication:
            return "Cisco отклонил вход. Проверьте логин, пароль, группу, QR и время macOS. Автоповторы остановлены."
        case .certificate:
            return "Cisco не доверяет сертификату VPN. Проверьте адрес и сертификат через администратора."
        case .banner:
            return "VPN требует принять баннер. Прочитайте его в Cisco и разрешите принятие в настройках утилиты."
        case .group: return "Указанная группа не найдена в списке Cisco. Укажите точное название или номер группы."
        case .unsupported:
            return
                "Cisco запросил неподдерживаемый шаг входа. Проверьте режим авторизации; SSO и push-вход требуют ручного подключения."
        case .signing:
            return "CLI Cisco имеет ошибку подписи. Восстановите Cisco Secure Client из официального установщика."
        case .service: return "Сервис Cisco недоступен. Откройте Cisco Secure Client и проверьте его установку."
        case .clientBusy:
            return
                "Графический Cisco Secure Client удерживает управление подключением. Завершите его через меню Cisco → Quit и повторите подключение. Сервис Cisco должен продолжать работать."
        case .network: return "Не удалось установить VPN. Проверьте сеть и доступность сервера."
        case .timeout: return "Cisco не завершил операцию за отведённое время."
        case .cancelled: return "Операция остановлена."
        }
    }
    public var retryable: Bool { self == .network || self == .timeout }
}

public enum VPNState: Equatable { case connected, disconnected, connecting, reconnecting, unknown }

public enum CLIText {
    public static func state(_ text: String) -> VPNState {
        let regex = try! NSRegularExpression(pattern: #"(?im)^\s*(?:>>\s*)?state:\s*([a-z ]+)\s*$"#)
        let ns = text as NSString
        guard let m = regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).last else {
            return .unknown
        }
        switch ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces).lowercased() {
        case "connected": return .connected
        case "disconnected": return .disconnected
        case "connecting": return .connecting
        case "reconnecting": return .reconnecting
        default: return .unknown
        }
    }

    public static func failure(_ text: String) -> VPNFailure? {
        let t = text.lowercased()
        if t.contains("code signing requirements") { return .signing }
        if t.contains("another cisco secure client application acquired")
            || t.contains("another anyconnect application acquired")
        {
            return .clientBusy
        }
        if [
            "untrusted", "certificate validation failure", "certificate is invalid", "certificate verification failed",
            "certificate does not match", "not a trusted server", "connect anyway",
        ].contains(where: t.contains) {
            return .certificate
        }
        if [
            "login failed", "authentication failed", "authentication rejected", "authentication failure",
            "login denied", "invalid credentials", "incorrect password", "login error",
        ].contains(where: t.contains) {
            return .authentication
        }
        if [
            "unable to attach", "vpn service is not available", "vpn service is unavailable", "another vpn application",
        ].contains(where: t.contains) {
            return .service
        }
        if ["external browser", "saml", "single sign-on", "web authentication", "duo push"].contains(where: t.contains)
        {
            return .unsupported
        }
        return nil
    }
}

public struct LoginConversation {
    public enum Field: Equatable {
        case group(String)
        case username, password, otp, passwordPlusOTP, acceptBanner
    }
    public enum Action: Equatable {
        case send(Field)
        case connected
        case fail(VPNFailure)
    }
    private var buffer = ""
    private var sent: Set<String> = []
    private let profile: VPNProfile
    public init(profile: VPNProfile) { self.profile = profile }

    /// Incremental parser: a prompt may arrive without a newline, or split across reads.
    public mutating func receive(_ chunk: String) -> Action? {
        buffer += chunk.replacingOccurrences(of: "\r", with: "\n")
        if buffer.utf8.count > 65536 { return .fail(.unsupported) }
        if let failure = CLIText.failure(buffer) { return .fail(failure) }
        if CLIText.state(buffer) == .connected { return .connected }
        if !profile.group.isEmpty, !sent.contains("group") {
            let fixedGroup = try! NSRegularExpression(pattern: #"(?im)^\s*(?:vpn>\s*)?group:\s*([^\[\]\r\n:]+)\s*$"#)
            let ns = buffer as NSString
            if let m = fixedGroup.firstMatch(in: buffer, range: NSRange(location: 0, length: ns.length)) {
                let group = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
                if !group.isEmpty && group.caseInsensitiveCompare(profile.group) != .orderedSame {
                    return .fail(.group)
                }
            }
        }
        let line =
            buffer.components(separatedBy: "\n").last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?
            .trimmingCharacters(in: .whitespaces) ?? ""
        let lower = line.lowercased()
        let field: Field
        let key: String
        if lower.range(
            of: #"^(?:vpn>\s*)?group(?:\s*\[[^\]]*\])?\s*:(?:\s*\[[^\]]*\])?\s*$"#, options: .regularExpression) != nil
        {
            key = "group"
            guard !profile.group.isEmpty else { return .fail(.group) }
            let regex = try! NSRegularExpression(pattern: #"(?m)^\s*(\d+)[).]\s+(.+?)\s*$"#)
            let ns = buffer as NSString
            let choices = regex.matches(in: buffer, range: NSRange(location: 0, length: ns.length))
            if choices.isEmpty {
                field = .group(profile.group)
            } else {
                guard
                    let choice = choices.first(where: {
                        ns.substring(with: $0.range(at: 2)).caseInsensitiveCompare(profile.group) == .orderedSame
                            || ns.substring(with: $0.range(at: 1)) == profile.group
                    })
                else { return .fail(.group) }
                field = .group(ns.substring(with: choice.range(at: 1)))
            }
        } else if lower.range(
            of: #"^(?:vpn>\s*)?(?:username|user name)(?:\s*\[[^\]]*\])?\s*:(?:\s*\[[^\]]*\])?\s*$"#,
            options: .regularExpression) != nil
        {
            key = "username"
            field = .username
        } else if lower.range(of: #"^(?:vpn>\s*)?(?:second|secondary)\s+password\s*:\s*$"#, options: .regularExpression)
            != nil
        {
            key = "secondary"
            guard sent.contains("primary") else { return .fail(.unsupported) }
            switch profile.authMode {
            case .otpThenPassword: field = .password
            case .passwordThenOTP: field = .otp
            default: return .fail(.unsupported)
            }
        } else if lower.range(of: #"^(?:vpn>\s*)?password\s*:\s*$"#, options: .regularExpression) != nil {
            key = "primary"
            switch profile.authMode {
            case .otpThenPassword, .otpOnly: field = .otp
            case .passwordThenOTP: field = .password
            case .passwordPlusOTP: field = .passwordPlusOTP
            }
        } else if lower.range(
            of: #"^(?:vpn>\s*)?(?:answer|response|passcode|otp|verification code|token code)\s*:\s*$"#,
            options: .regularExpression) != nil
        {
            key = "secondary"
            guard sent.contains("primary"), profile.authMode == .passwordThenOTP else { return .fail(.unsupported) }
            field = .otp
        } else if lower.range(of: #"^(?:vpn>\s*)?accept\?\s*\[y/n\]\s*:?\s*$"#, options: .regularExpression) != nil {
            key = "banner"
            guard profile.acceptBanner else { return .fail(.banner) }
            field = .acceptBanner
        } else {
            // Never guess at arbitrary server-supplied fields or trust/certificate prompts.
            if lower.hasSuffix(":") || lower.hasSuffix("?") || lower.contains("[y/n]") || lower.contains("[yes/no]") {
                return .fail(.unsupported)
            }
            return nil
        }
        guard !sent.contains(key) else { return .fail(.authentication) }
        sent.insert(key)
        buffer = ""
        return .send(field)
    }
}
