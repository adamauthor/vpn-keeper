import Foundation

public enum AuthMode: String, Codable, CaseIterable, Identifiable {
    case otpThenPassword, passwordThenOTP, passwordPlusOTP, otpOnly
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .otpThenPassword: return "Password = OTP · Second Password = пароль"
        case .passwordThenOTP: return "Password = пароль · затем OTP"
        case .passwordPlusOTP: return "Password = пароль + OTP"
        case .otpOnly: return "Password = только OTP"
        }
    }
}

public struct VPNProfile: Codable, Equatable {
    public var server = ""
    public var group = ""
    public var username = ""
    public var authMode: AuthMode = .otpThenPassword
    public var acceptBanner = false
    public var releaseCiscoGUI = true
    public init() {}

    enum CodingKeys: String, CodingKey { case server, group, username, authMode, acceptBanner, releaseCiscoGUI }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        server = try c.decodeIfPresent(String.self, forKey: .server) ?? ""
        group = try c.decodeIfPresent(String.self, forKey: .group) ?? ""
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        authMode = try c.decodeIfPresent(AuthMode.self, forKey: .authMode) ?? .otpThenPassword
        acceptBanner = try c.decodeIfPresent(Bool.self, forKey: .acceptBanner) ?? false
        releaseCiscoGUI = try c.decodeIfPresent(Bool.self, forKey: .releaseCiscoGUI) ?? true
    }

    public func validated() throws -> VPNProfile {
        var result = self
        result.server = server.trimmingCharacters(in: .whitespacesAndNewlines)
        result.group = group.trimmingCharacters(in: .whitespacesAndNewlines)
        result.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let fields = [result.server, result.group, result.username]
        guard
            fields.allSatisfy({
                $0.count <= 1024 && !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            }),
            !result.username.isEmpty, !result.server.isEmpty,
            !result.server.contains(where: { $0.isWhitespace })
        else {
            throw KeeperError("Укажите адрес VPN и логин без переводов строк и управляющих символов.")
        }
        let address = result.server.contains("://") ? result.server : "https://" + result.server
        guard let c = URLComponents(string: address), c.scheme?.lowercased() == "https",
            let host = c.host,
            host.range(
                of: #"^(?:[a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?|\[[0-9a-fA-F:.]+\])$"#, options: .regularExpression)
                != nil,
            c.user == nil, c.password == nil,
            c.query == nil, c.fragment == nil,
            c.port.map({ (1...65535).contains($0) }) ?? true,
            let url = c.url
        else {
            throw KeeperError("Адрес должен быть HTTPS-хостом VPN, при необходимости с портом и путём группы.")
        }
        result.server = url.absoluteString
        return result
    }
}

public struct VaultEntry: Codable {
    public var password: String
    public var token: TOTPToken
    public init(password: String, token: TOTPToken) {
        self.password = password
        self.token = token
    }
    public func validate(for profile: VPNProfile) throws {
        guard password.utf8.count <= 4096,
            !password.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
            profile.authMode == .otpOnly || !password.isEmpty
        else {
            throw KeeperError("Введите пароль без управляющих символов.")
        }
        _ = try token.code()
    }
}

public struct RetryPolicy {
    public private(set) var failures = 0
    public init() {}
    public mutating func reset() { failures = 0 }
    /// Network errors only. Authentication, certificate and unknown prompts stop immediately.
    public mutating func nextDelay() -> TimeInterval? {
        failures += 1
        guard failures <= 3 else { return nil }
        return [30.0, 60.0, 120.0][failures - 1]
    }
}
