import CoreImage
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import VPNCore

struct AuthenticatorExportTests {
    // Independently encoded with Python, using the public RFC 6238 seed, never a user export.
    private let reference =
        "otpauth-migration://offline?data=CjYKFDEyMzQ1Njc4OTAxMjM0NTY3ODkwEhFhbGljZUBleGFtcGxlLmNvbRoFQ2lzY28gASgBMAIQARgBIAAoKg=="

    @Test func testIndependentExportFixtureProducesKnownOTP() throws {
        let result = try QRImport.parsePayloads([reference])
        checkTrue(result.requiresSelection)
        checkEqual(result.accounts.count, 1)
        checkEqual(result.accounts[0].name, "alice@example.com")
        checkEqual(result.accounts[0].issuer, "Cisco")
        let selected = try result.selectedToken(id: 0)
        checkEqual(selected.label, "Cisco:alice@example.com")
        checkEqual(selected.period, 30)
        checkEqual(try selected.code(at: Date(timeIntervalSince1970: 59)), "287082")
    }

    @Test func testMultipleAccountsRequireExplicitChoiceAndKeepTheirOwnSecrets() throws {
        let sha256 = Data("12345678901234567890123456789012".utf8)
        let payload = page([
            entry(name: "Personal"),
            entry(name: "VPN", secret: sha256, algorithm: 2, digits: 2),
            entry(name: "Counter", type: 1),
        ])
        let result = try QRImport.parsePayloads([uri(payload)])
        checkEqual(result.accounts.count, 3)
        checkTrue(result.requiresSelection)
        checkEqual(try result.selectedToken(id: 1).secret, sha256)
        checkEqual(try result.selectedToken(id: 1).code(at: Date(timeIntervalSince1970: 59)), "46119246")
        checkNil(result.accounts[2].token)
        checkThrows(try result.selectedToken(id: 2))
        checkThrows(try result.selectedToken(id: 999))
    }

    @Test func testURLSafeBase64AndLiteralPlusAreBothAccepted() throws {
        let seed = Data(repeating: 255, count: 20)
        let data = page([entry(secret: seed)])
        let prefix = "otpauth-migration://offline?data="
        let base64 = data.base64EncodedString()
        checkTrue(base64.contains("+") || base64.contains("/"))
        let urlSafe = base64.replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let percentEncoded = base64.replacingOccurrences(of: "+", with: "%2B")
            .replacingOccurrences(of: "/", with: "%2F").replacingOccurrences(of: "=", with: "%3D")
        for value in [base64, urlSafe, percentEncoded] {
            checkEqual(try QRImport.parsePayloads([prefix + value]).selectedToken(id: 0).secret, seed)
        }
    }

    @Test func testGoogleDefaultsAndSHA512Mapping() throws {
        let unspecified = entry(algorithm: 0, digits: 0, type: 0)
        let sha512 = entry(
            secret: Data("1234567890123456789012345678901234567890123456789012345678901234".utf8), algorithm: 3,
            digits: 2)
        let result = try QRImport.parsePayloads([uri(page([unspecified, sha512]))])
        checkEqual(try result.selectedToken(id: 0).code(at: Date(timeIntervalSince1970: 59)), "287082")
        checkEqual(try result.selectedToken(id: 1).code(at: Date(timeIntervalSince1970: 59)), "90693936")
    }

    @Test func testUnsupportedEntriesDoNotHideValidTOTPAndAreNeverDowngraded() throws {
        let result = try QRImport.parsePayloads([
            uri(
                page([
                    entry(), entry(algorithm: 4), entry(algorithm: 99), entry(digits: 99),
                    entry(type: 1), entry(type: 99), entry(secret: Data()),
                ]))
        ])
        checkTrue(result.accounts[0].token != nil)
        for index in 1..<result.accounts.count {
            checkNil(result.accounts[index].token)
            checkThrows(try result.selectedToken(id: index))
        }
    }

    @Test func testBatchPageIsExplicitAndRepeatedQRIsNotDuplicated() throws {
        let value = uri(page([entry()], size: 3, index: 1))
        let result = try QRImport.parsePayloads([value, value, "https://irrelevant.example"])
        checkEqual(result.accounts.count, 1)
        checkEqual(result.notices.count, 1)
        checkTrue(result.notices[0].contains("2 из 3"))
    }

    @Test func testVersionTwoExportUsesSameValidatedAccountSchema() throws {
        let payload = bytes(1, entry()) + number(2, 2) + number(3, 1) + number(4, 0)
        let result = try QRImport.parsePayloads([uri(payload)])
        checkEqual(result.accounts.count, 1)
        checkEqual(try result.selectedToken(id: 0).code(at: Date(timeIntervalSince1970: 59)), "287082")
        let unknownVersion = bytes(1, entry()) + number(2, 3) + number(3, 1)
        checkThrows(try QRImport.parsePayloads([uri(unknownVersion)]))
    }

    @Test func testMalformedProtobufAndAmbiguousEnvelopesFailSafely() {
        let duplicateSeed = entry() + bytes(1, Data(repeating: 1, count: 20))
        for data in [
            Data([0]), Data([0x0a, 0xff, 0x7f]), Data(repeating: 0x80, count: 12),
            number(1, 2), page([duplicateSeed]), page([entry()], size: 1, index: 1),
            page([entry()]) + number(2, 1),
        ] {
            checkThrows(try QRImport.parsePayloads([uri(data)]))
        }
        for value in [
            reference + "&data=AA==", reference + "&other=x",
            "otpauth-migration://online?data=AA==", "otpauth-migration://offline?data=%%%",
            "otpauth-migration://offline?data=", uri(Data()),
        ] {
            checkThrows(try QRImport.parsePayloads([value]))
        }
    }

    @Test func testUnknownProtobufFieldsAreSkippedWithoutChangingOTP() throws {
        let unknown =
            number(99, 123) + bytes(100, Data([1, 2, 3]))
            + varint((101 << 3) | 1) + Data(repeating: 0, count: 8)
            + varint((102 << 3) | 5) + Data(repeating: 0, count: 4)
        let result = try QRImport.parsePayloads([uri(page([entry()]) + unknown)])
        checkEqual(try result.selectedToken(id: 0).code(at: Date(timeIntervalSince1970: 59)), "287082")
    }

    @Test func testActualMigrationQRImageImport() throws {
        let filter = try #require(CIFilter(name: "CIQRCodeGenerator"))
        filter.setValue(Data(reference.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        let qr = try #require(filter.outputImage)
        let image = qr.composited(over: CIImage(color: .white).cropped(to: qr.extent.insetBy(dx: -4, dy: -4)))
            .transformed(by: .init(scaleX: 8, y: 8))
        let cgImage = try #require(
            CIContext(options: [.useSoftwareRenderer: true]).createCGImage(image, from: image.extent))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, cgImage, nil)
        checkTrue(CGImageDestinationFinalize(destination))
        let result = try QRImport.readAccounts(url)
        checkTrue(result.requiresSelection)
        checkEqual(try result.selectedToken(id: 0).code(at: Date(timeIntervalSince1970: 59)), "287082")
    }

    private func uri(_ data: Data) -> String { "otpauth-migration://offline?data=" + data.base64EncodedString() }
    private func entry(
        name: String = "VPN", secret: Data = Data("12345678901234567890".utf8),
        algorithm: UInt64 = 1, digits: UInt64 = 1, type: UInt64 = 2
    ) -> Data {
        bytes(1, secret) + bytes(2, Data(name.utf8)) + bytes(3, Data("Cisco".utf8))
            + number(4, algorithm) + number(5, digits) + number(6, type)
    }
    private func page(_ entries: [Data], size: UInt64 = 1, index: UInt64 = 0) -> Data {
        entries.reduce(into: Data()) { $0 += bytes(1, $1) }
            + number(2, 1) + number(3, size) + number(4, index) + number(5, 42)
    }
    private func number(_ field: UInt64, _ value: UInt64) -> Data { varint(field << 3) + varint(value) }
    private func bytes(_ field: UInt64, _ value: Data) -> Data {
        varint((field << 3) | 2) + varint(UInt64(value.count)) + value
    }
    private func varint(_ number: UInt64) -> Data {
        var n = number
        var result = Data()
        while n >= 128 {
            result.append(UInt8(n & 127) | 128)
            n >>= 7
        }
        result.append(UInt8(n))
        return result
    }
}
