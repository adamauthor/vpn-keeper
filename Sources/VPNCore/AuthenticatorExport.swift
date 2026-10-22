import Foundation

public struct QRAccount: Identifiable {
    public let id: Int
    public let name: String
    public let issuer: String
    public let token: TOTPToken?
    public let unavailableReason: String?
}

public struct QRImportResult: Identifiable {
    public let id = UUID()
    public let accounts: [QRAccount]
    public let notices: [String]
    public let requiresSelection: Bool

    public func selectedToken(id: Int) throws -> TOTPToken {
        guard let account = accounts.first(where: { $0.id == id }), let token = account.token else {
            throw KeeperError("Выберите поддерживаемый TOTP-аккаунт для VPN.")
        }
        return token
    }
}

/// Parses Google Authenticator's offline export locally. No raw URI or seed is logged.
/// Wire schema reference: https://github.com/beemdevelopment/Aegis/blob/master/app/src/main/proto/google_auth.proto
public enum AuthenticatorExport {
    struct Page {
        let accounts: [QRAccount]
        let batchSize: Int
        let batchIndex: Int
    }

    static func parse(_ uri: String) throws -> Page {
        guard uri.utf8.count <= 131072, let c = URLComponents(string: uri),
            c.scheme?.lowercased() == "otpauth-migration", c.host?.lowercased() == "offline",
            c.path.isEmpty || c.path == "/", c.user == nil, c.password == nil, c.port == nil,
            c.fragment == nil
        else { throw invalid() }
        let items = c.queryItems ?? []
        guard items.count == 1, items[0].name == "data", let encoded = items[0].value,
            !encoded.isEmpty
        else { throw invalid() }
        // URLComponents percent-decodes once and preserves '+', unlike form decoding.
        var base64 = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard
            base64.utf8.allSatisfy({
                (65...90).contains($0) || (97...122).contains($0)
                    || (48...57).contains($0) || [43, 47, 61].contains($0)
            })
        else { throw invalid() }
        base64 += String(repeating: "=", count: (4 - base64.utf8.count % 4) % 4)
        guard let data = Data(base64Encoded: base64), !data.isEmpty, data.count <= 65536 else { throw invalid() }
        let fields = try Proto.fields(data)
        let metadata = try unique(fields.filter { (2...5).contains($0.number) })
        let version = try scalar(metadata[2], default: 1)
        let size = try scalar(metadata[3], default: 1)
        let index = try scalar(metadata[4], default: 0)
        // A zero/omitted batch size is emitted by some compatible exporters for a single page.
        let batchSize = size == 0 ? 1 : size
        guard [UInt64(1), UInt64(2)].contains(version), batchSize <= 1000, index < batchSize else {
            throw KeeperError("Неподдерживаемая версия или неверные номера частей экспорта Google Authenticator.")
        }
        if let field = metadata[5] { _ = try scalar(field) }
        let records = fields.filter { $0.number == 1 }
        guard !records.isEmpty, records.count <= 100 else { throw invalid() }
        let accounts = try records.enumerated().map { i, field -> QRAccount in
            guard case .bytes(let bytes) = field.value else { throw invalid() }
            return try account(bytes, id: i)
        }
        return Page(accounts: accounts, batchSize: Int(batchSize), batchIndex: Int(index))
    }

    private static func account(_ data: Data, id: Int) throws -> QRAccount {
        let fields = try unique(Proto.fields(data).filter { (1...7).contains($0.number) })
        let name = try text(fields[2])
        let issuer = try text(fields[3])
        let displayName = name.isEmpty ? "Аккаунт \(id + 1)" : name
        func unavailable(_ reason: String) -> QRAccount {
            QRAccount(id: id, name: displayName, issuer: issuer, token: nil, unavailableReason: reason)
        }
        let type = try scalar(fields[6])
        guard type == 0 || type == 2 else {
            return unavailable(type == 1 ? "HOTP со счётчиком не поддерживается" : "Неизвестный тип одноразового кода")
        }
        if type == 0, try scalar(fields[7]) != 0 { return unavailable("HOTP со счётчиком не поддерживается") }
        let algorithm: TOTPToken.Algorithm
        switch try scalar(fields[4]) {
        case 0, 1: algorithm = .sha1
        case 2: algorithm = .sha256
        case 3: algorithm = .sha512
        default: return unavailable("Алгоритм TOTP не поддерживается")
        }
        let digits: Int
        switch try scalar(fields[5]) {
        case 0, 1: digits = 6
        case 2: digits = 8
        default: return unavailable("Количество цифр TOTP не поддерживается")
        }
        guard let field = fields[1], case .bytes(let secret) = field.value else {
            return unavailable("В аккаунте отсутствует секрет TOTP")
        }
        let label = issuer.isEmpty || displayName.hasPrefix(issuer + ":") ? displayName : issuer + ":" + displayName
        do {
            // Migration exports carry no period. Google Authenticator uses 30 seconds.
            let token = try TOTPToken(secret: secret, algorithm: algorithm, digits: digits, period: 30, label: label)
            return QRAccount(id: id, name: displayName, issuer: issuer, token: token, unavailableReason: nil)
        } catch { return unavailable("Секрет TOTP отсутствует или имеет неподдерживаемую длину") }
    }

    private static func unique(_ fields: [Proto.Field]) throws -> [Int: Proto.Field] {
        var result: [Int: Proto.Field] = [:]
        for field in fields {
            guard result[field.number] == nil else { throw invalid() }
            result[field.number] = field
        }
        return result
    }

    private static func scalar(_ field: Proto.Field?, default fallback: UInt64 = 0) throws -> UInt64 {
        guard let field else { return fallback }
        guard case .number(let value) = field.value else { throw invalid() }
        return value
    }

    private static func text(_ field: Proto.Field?) throws -> String {
        guard let field else { return "" }
        guard case .bytes(let bytes) = field.value, bytes.count <= 4096,
            let value = String(data: bytes, encoding: .utf8)
        else { throw invalid() }
        return displayText(value)
    }

    static func displayText(_ value: String) -> String {
        let clean = value.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }.joined()
        return String(clean.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
    }

    private static func invalid() -> KeeperError {
        KeeperError("Экспорт Google Authenticator повреждён или имеет неподдерживаемый формат.")
    }

    /// Bounded protobuf reader: handles unknown varint, fixed and length-delimited fields.
    /// Deprecated protobuf groups and malformed/overflowing lengths are rejected.
    private enum Proto {
        enum Value {
            case number(UInt64)
            case bytes(Data)
            case fixed
        }
        struct Field {
            let number: Int
            let value: Value
        }
        static func fields(_ data: Data) throws -> [Field] {
            let bytes = Array(data)
            var offset = 0
            var fields: [Field] = []
            func varint() throws -> UInt64 {
                var result: UInt64 = 0
                for i in 0..<10 {
                    guard offset < bytes.count else { throw invalid() }
                    let byte = bytes[offset]
                    offset += 1
                    guard i != 9 || byte <= 1 else { throw invalid() }
                    result |= UInt64(byte & 127) << (i * 7)
                    if byte & 128 == 0 { return result }
                }
                throw invalid()
            }
            while offset < bytes.count {
                guard fields.count < 4096 else { throw invalid() }
                let key = try varint()
                let number = key >> 3
                guard number > 0, number < (1 << 29) else { throw invalid() }
                let value: Value
                switch key & 7 {
                case 0: value = .number(try varint())
                case 1, 5:
                    let length = key & 7 == 1 ? 8 : 4
                    guard length <= bytes.count - offset else { throw invalid() }
                    offset += length
                    value = .fixed
                case 2:
                    let length = try varint()
                    guard length <= UInt64(bytes.count - offset) else { throw invalid() }
                    let end = offset + Int(length)
                    value = .bytes(Data(bytes[offset..<end]))
                    offset = end
                default: throw invalid()
                }
                fields.append(Field(number: Int(number), value: value))
            }
            return fields
        }
    }
}
