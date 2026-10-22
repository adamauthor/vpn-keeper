import CryptoKit
import Foundation

public struct KeeperError: LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct TOTPToken: Codable, Equatable {
    public enum Algorithm: String, Codable {
        case sha1 = "SHA1"
        case sha256 = "SHA256"
        case sha512 = "SHA512"
    }
    public let secret: Data
    public let algorithm: Algorithm
    public let digits: Int
    public let period: Int
    public let label: String

    public init(
        secret: Data, algorithm: Algorithm = .sha1, digits: Int = 6,
        period: Int = 30, label: String = "VPN"
    ) throws {
        guard secret.count >= 10, secret.count <= 512,
            [6, 8].contains(digits), (10...120).contains(period)
        else {
            throw KeeperError("Некорректные параметры TOTP: нужны 6 или 8 цифр и период 10–120 секунд.")
        }
        self.secret = secret
        self.algorithm = algorithm
        self.digits = digits
        self.period = period
        self.label = String(label.prefix(120))
    }

    public static func parse(_ uri: String) throws -> TOTPToken {
        guard uri.count <= 8192, let c = URLComponents(string: uri),
            c.scheme?.lowercased() == "otpauth", c.host?.lowercased() == "totp",
            c.user == nil, c.password == nil, c.port == nil, c.fragment == nil
        else {
            throw KeeperError(
                "Нужен QR настройки TOTP (otpauth://totp). Экспорт Google Authenticator добавьте через импорт QR. QR входа и HOTP не поддерживаются."
            )
        }
        var values: [String: String] = [:]
        for item in c.queryItems ?? [] {
            let key = item.name.lowercased()
            guard values[key] == nil, let value = item.value else {
                throw KeeperError("В QR повторяются или отсутствуют параметры TOTP.")
            }
            values[key] = value
        }
        guard let text = values["secret"],
            let algorithm = Algorithm(rawValue: (values["algorithm"] ?? "SHA1").uppercased()),
            let digits = Int(values["digits"] ?? "6"),
            let period = Int(values["period"] ?? "30")
        else {
            throw KeeperError("QR содержит неподдерживаемые параметры TOTP.")
        }
        return try TOTPToken(
            secret: Base32.decode(text), algorithm: algorithm,
            digits: digits, period: period,
            label: String(c.path.dropFirst()))
    }

    public func code(at date: Date = Date()) throws -> String {
        // Validate again because Codable can read data from an older or damaged keychain item.
        _ = try TOTPToken(secret: secret, algorithm: algorithm, digits: digits, period: period)
        let seconds = date.timeIntervalSince1970
        guard seconds.isFinite, seconds >= 0, seconds < Double(UInt64.max) else {
            throw KeeperError("Проверьте дату и время macOS.")
        }
        var counter = UInt64(seconds / Double(period)).bigEndian
        let message = withUnsafeBytes(of: &counter) { Data($0) }
        let key = SymmetricKey(data: secret)
        let mac: [UInt8]
        switch algorithm {
        case .sha1: mac = Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: key))
        case .sha256: mac = Array(HMAC<SHA256>.authenticationCode(for: message, using: key))
        case .sha512: mac = Array(HMAC<SHA512>.authenticationCode(for: message, using: key))
        }
        let offset = Int(mac.last! & 15)
        let binary =
            (UInt32(mac[offset] & 127) << 24) | (UInt32(mac[offset + 1]) << 16)
            | (UInt32(mac[offset + 2]) << 8) | UInt32(mac[offset + 3])
        let modulus: UInt32 = digits == 6 ? 1_000_000 : 100_000_000
        return String(format: "%0*u", digits, binary % modulus)
    }

    public func secondsRemaining(at date: Date = Date()) -> TimeInterval {
        guard period > 0 else { return 0 }
        return Double(period) - date.timeIntervalSince1970.truncatingRemainder(dividingBy: Double(period))
    }
}

public enum Base32 {
    public static func decode(_ text: String) throws -> Data {
        let chars = Array(text.uppercased().utf8)
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".utf8)
        let unpadded = Array(chars.prefix { $0 != 61 })
        let padding = chars.count - unpadded.count
        let validLengths = [0, 2, 4, 5, 7]
        guard !unpadded.isEmpty, validLengths.contains(unpadded.count % 8),
            chars.dropFirst(unpadded.count).allSatisfy({ $0 == 61 }),
            padding == 0 || (chars.count % 8 == 0 && padding == (8 - unpadded.count % 8) % 8)
        else {
            throw KeeperError("Секрет в QR имеет неверный формат Base32.")
        }
        var buffer: UInt32 = 0
        var bits = 0
        var output = Data()
        for char in unpadded {
            guard let index = alphabet.firstIndex(of: char) else {
                throw KeeperError("Секрет в QR имеет неверный формат Base32.")
            }
            buffer = (buffer << 5) | UInt32(index)
            bits += 5
            if bits >= 8 {
                bits -= 8
                output.append(UInt8((buffer >> bits) & 255))
                buffer &= (1 << bits) - 1
            }
        }
        guard buffer == 0 else { throw KeeperError("Неканонический секрет Base32 в QR.") }
        return output
    }
}
