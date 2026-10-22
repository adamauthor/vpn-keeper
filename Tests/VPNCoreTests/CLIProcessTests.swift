import Foundation
import Testing

@testable import VPNCore

struct CLIProcessTests {
    private func fixture(_ script: String) throws -> (URL, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("fake-vpn")
        try ("#!/bin/sh\n" + script).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return (directory, url)
    }

    @Test func testFullStreamingLoginWithRealChildProcess() async throws {
        let (directory, url) = try fixture(
            """
            [ "$1" = '-s' ] && [ "$2" = 'connect' ] || exit 7
            printf '1) Guests\n2) Staff\nGroup: '
            IFS= read -r answer
            [ "$answer" = '2' ] || exit 8
            printf 'Username: '
            IFS= read -r answer
            [ "$answer" = 'alice' ] || exit 9
            printf 'Password: '
            IFS= read -r answer
            case "$answer" in *[!0-9]*|'') exit 10;; esac
            [ "${#answer}" = '6' ] || exit 11
            printf 'Second Password: '
            IFS= read -r answer
            [ "$answer" = 'test!$`password' ] || exit 12
            printf '\n >> state: Connected\n'
            """)
        defer { try? FileManager.default.removeItem(at: directory) }
        var p = VPNProfile()
        p.server = "https://vpn.example.com"
        p.group = "Staff"
        p.username = "alice"
        let vault = VaultEntry(
            password: "test!$`password", token: try TOTPToken.parse("otpauth://totp/test?secret=JBSWY3DPEHPK3PXP"))
        let result = await CLIProcess(executable: url, request: .connect(p, vault)).run()
        checkEqual(result, .state(.connected))
    }

    @Test func testFailedAuthenticationIsNotAConnection() async throws {
        let (directory, url) = try fixture("printf 'Login failed.\n'; exit 0")
        defer { try? FileManager.default.removeItem(at: directory) }
        let result = await CLIProcess(executable: url, request: .state).run()
        checkEqual(result, .failed(.authentication))
    }

    @Test func testEchoedPasswordIsRemovedBeforeErrorParsing() async throws {
        let (directory, url) = try fixture(
            """
            printf '** unable to get tty! (using stdin), password will echo **\nPassword: '
            IFS= read -r answer
            printf '%s\nSecond Password: ' "$answer"
            IFS= read -r answer
            # Split the echo to exercise buffering, including a secret resembling an error.
            printf '%s' 'Authentication '
            /bin/sleep 0.05
            printf '%s\n >> state: Connected\n' 'failed?'
            """)
        defer { try? FileManager.default.removeItem(at: directory) }
        var p = VPNProfile()
        p.server = "https://vpn.example.com"
        p.username = "alice"
        let vault = VaultEntry(
            password: "Authentication failed?",
            token: try TOTPToken.parse("otpauth://totp/test?secret=JBSWY3DPEHPK3PXP"))
        let result = await CLIProcess(executable: url, request: .connect(p, vault)).run()
        checkEqual(result, .state(.connected))
    }

    @Test func testCancellationCompletesPromptly() async throws {
        let (directory, url) = try fixture("exec /bin/sleep 30")
        defer { try? FileManager.default.removeItem(at: directory) }
        let operation = CLIProcess(executable: url, request: .state)
        let task = Task { await operation.run() }
        try await Task.sleep(nanoseconds: 100_000_000)
        operation.cancel()
        let result = await task.value
        checkEqual(result, .failed(.cancelled))
    }
}
