import CoreImage
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import VPNCore

struct TOTPTests {
    @Test func testPreviouslySavedVaultRemainsReadable() throws {
        // Original persisted format, using only the public RFC 6238 seed.
        let legacy = Data(
            #"{"password":"synthetic-password","token":{"secret":"MTIzNDU2Nzg5MDEyMzQ1Njc4OTA=","algorithm":"SHA1","digits":6,"period":30,"label":"legacy"}}"#
                .utf8)
        let entry = try JSONDecoder().decode(VaultEntry.self, from: legacy)
        checkEqual(entry.password, "synthetic-password")
        checkEqual(try entry.token.code(at: Date(timeIntervalSince1970: 59)), "287082")
        let saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any]
        checkEqual((saved?["token"] as? [String: Any])?["algorithm"] as? String, "SHA1")
    }

    @Test func testRFC6238AllEighteenVectors() throws {
        let times: [TimeInterval] = [59, 1_111_111_109, 1_111_111_111, 1_234_567_890, 2_000_000_000, 20_000_000_000]
        let vectors: [(TOTPToken.Algorithm, String, [String])] = [
            (.sha1, "12345678901234567890", ["94287082", "07081804", "14050471", "89005924", "69279037", "65353130"]),
            (
                .sha256, "12345678901234567890123456789012",
                ["46119246", "68084774", "67062674", "91819424", "90698825", "77737706"]
            ),
            (
                .sha512, "1234567890123456789012345678901234567890123456789012345678901234",
                ["90693936", "25091201", "99943326", "93441116", "38618901", "47863826"]
            ),
        ]
        for (algorithm, secret, expected) in vectors {
            let token = try TOTPToken(secret: Data(secret.utf8), algorithm: algorithm, digits: 8)
            for (index, time) in times.enumerated() {
                checkEqual(try token.code(at: Date(timeIntervalSince1970: time)), expected[index])
            }
        }
    }

    @Test func testURIAndLeadingZero() throws {
        let token = try TOTPToken.parse(
            "otpauth://totp/Example:alice?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&algorithm=SHA1&digits=8&period=30")
        checkEqual(try token.code(at: Date(timeIntervalSince1970: 1_111_111_109)), "07081804")
        checkEqual(token.label, "Example:alice")
        checkEqual(token.secondsRemaining(at: Date(timeIntervalSince1970: 58)), 2)
    }

    @Test func testRejectsUnsupportedOrAmbiguousQR() {
        for uri in [
            "otpauth://hotp/test?secret=JBSWY3DPEHPK3PXP&counter=1",
            "otpauth-migration://offline?data=test", "https://example.com/qr",
            "otpauth://totp/test?secret=JBSWY3DPEHPK3PXP&digits=9",
            "otpauth://totp/test?secret=JBSWY3DPEHPK3PXP&secret=AAAAAAAAAAAAAAAA",
            "otpauth://totp/test?secret=JBSWY3DPEHPK3PXP&period=0",
            "otpauth://totp/test?secret=bad-secret",
        ] { checkThrows(try TOTPToken.parse(uri)) }
        checkThrows(try Base32.decode("AB"))  // Non-zero trailing padding bits.
    }

    @Test func testActualImageQRImport() throws {
        let uri = "otpauth://totp/Test:demo?secret=JBSWY3DPEHPK3PXP&issuer=Test"
        let filter = CIFilter(name: "CIQRCodeGenerator")!
        filter.setValue(Data(uri.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        let qr = filter.outputImage!
        let background = CIImage(color: .white).cropped(to: qr.extent.insetBy(dx: -4, dy: -4))
        let image = qr.composited(over: background).transformed(by: .init(scaleX: 8, y: 8))
        let cgImage = try #require(
            CIContext(options: [.useSoftwareRenderer: true]).createCGImage(image, from: image.extent))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, cgImage, nil)
        checkTrue(CGImageDestinationFinalize(destination))
        let imported = try QRImport.read(url)
        checkEqual(imported, try TOTPToken.parse(uri))
    }

    @Test func testProfileRejectsInjectionAndInsecureAddress() throws {
        var p = VPNProfile()
        p.username = "user"
        p.server = "vpn.example.com/group"
        checkEqual(try p.validated().server, "https://vpn.example.com/group")
        for address in [
            "http://vpn.example.com", "https://user:pass@vpn.example.com", "vpn.example.com\nconnect bad",
            "https://vpn.example.com?password=test", "--help", "https://vpn.example.com:99999",
        ] {
            p.server = address
            checkThrows(try p.validated())
        }
    }
}
