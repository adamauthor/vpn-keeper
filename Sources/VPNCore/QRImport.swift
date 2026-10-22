import Foundation
import ImageIO
import Vision

public enum QRImport {
    public static func read(_ url: URL) throws -> TOTPToken {
        let result = try readAccounts(url)
        guard result.accounts.count == 1, let account = result.accounts.first else {
            throw KeeperError("На изображении несколько аккаунтов. Выберите нужный в окне импорта.")
        }
        return try result.selectedToken(id: account.id)
    }

    public static func readAccounts(_ url: URL) throws -> QRImportResult {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber, size.intValue <= 20_000_000,
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
            let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
            width.doubleValue * height.doubleValue <= 40_000_000
        else {
            throw KeeperError("Выберите изображение QR размером до 20 МБ и 40 мегапикселей.")
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw KeeperError("Не удалось прочитать изображение QR.")
        }
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try VNImageRequestHandler(cgImage: image).perform([request])
        return try parsePayloads((request.results ?? []).compactMap(\.payloadStringValue))
    }

    public static func parsePayloads(_ payloads: [String]) throws -> QRImportResult {
        var seen = Set<String>()
        let candidates = payloads.filter { seen.insert($0).inserted }.filter {
            $0.lowercased().hasPrefix("otpauth://totp/") || $0.lowercased().hasPrefix("otpauth-migration:")
        }
        guard !candidates.isEmpty, candidates.count <= 32 else {
            throw KeeperError("QR настройки TOTP или экспорта Google Authenticator не найден на изображении.")
        }
        var accounts: [QRAccount] = []
        var notices: [String] = []
        var migration = false
        for candidate in candidates {
            if candidate.lowercased().hasPrefix("otpauth-migration:") {
                let page = try AuthenticatorExport.parse(candidate)
                migration = true
                if page.batchSize > 1 {
                    notices.append(
                        "Часть экспорта \(page.batchIndex + 1) из \(page.batchSize). В списке только аккаунты с этой картинки. Если нужного нет, выберите другую часть экспорта."
                    )
                }
                for account in page.accounts {
                    accounts.append(
                        QRAccount(
                            id: accounts.count, name: account.name, issuer: account.issuer,
                            token: account.token, unavailableReason: account.unavailableReason))
                }
            } else {
                let token = try TOTPToken.parse(candidate)
                let name = AuthenticatorExport.displayText(token.label)
                accounts.append(
                    QRAccount(
                        id: accounts.count, name: name.isEmpty ? "TOTP-аккаунт" : name,
                        issuer: "", token: token, unavailableReason: nil))
            }
            guard accounts.count <= 256 else {
                throw KeeperError("Слишком много аккаунтов на одном изображении. Выберите QR только для VPN.")
            }
        }
        return QRImportResult(accounts: accounts, notices: notices, requiresSelection: migration || accounts.count > 1)
    }
}
