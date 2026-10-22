import Foundation
import Testing

@testable import VPNCore

struct ConversationTests {
    private func profile(_ mode: AuthMode = .otpThenPassword) -> VPNProfile {
        var p = VPNProfile()
        p.username = "alice"
        p.group = "Staff VPN"
        p.authMode = mode
        return p
    }

    @Test func testUserSpecificOTPFirstFlowAndGroupResolution() {
        var c = LoginConversation(profile: profile())
        checkNil(c.receive("  1) Guests\n  2) Staff VPN\nGro"))
        checkEqual(c.receive("up: [1] "), .send(.group("2")))
        checkEqual(c.receive("Username: [old-user] "), .send(.username))
        checkNil(c.receive("Pass"))
        checkEqual(c.receive("word: "), .send(.otp))
        checkEqual(c.receive("Second Password: "), .send(.password))
        checkEqual(c.receive("\n>> state: Connected\n"), .connected)
    }

    @Test func testOtherModes() {
        for (mode, expected) in [
            (AuthMode.passwordThenOTP, LoginConversation.Field.password), (.passwordPlusOTP, .passwordPlusOTP),
            (.otpOnly, .otp),
        ] {
            var c = LoginConversation(profile: profile(mode))
            checkEqual(c.receive("Password:"), .send(expected))
            if mode == .passwordThenOTP { checkEqual(c.receive("Response:"), .send(.otp)) }
        }
    }

    @Test func testRejectsRetriesAndUnknownPromptsWithoutSendingSecrets() {
        var c = LoginConversation(profile: profile())
        checkEqual(c.receive("Password:"), .send(.otp))
        checkEqual(c.receive("Password:"), .fail(.authentication))
        var unknown = LoginConversation(profile: profile())
        checkEqual(unknown.receive("Security answer:"), .fail(.unsupported))
        var wrongOrder = LoginConversation(profile: profile())
        checkEqual(wrongOrder.receive("Second Password:"), .fail(.unsupported))
    }

    @Test func testCertificatesAreNeverAcceptedAsBanners() {
        var p = profile()
        p.acceptBanner = true
        var c = LoginConversation(profile: p)
        checkEqual(c.receive("Untrusted server certificate\naccept? [y/n]"), .fail(.certificate))
        var noConsent = LoginConversation(profile: profile())
        checkEqual(noConsent.receive("accept? [y/n]"), .fail(.banner))
        var consent = LoginConversation(profile: p)
        checkEqual(consent.receive("accept? [y/n]"), .send(.acceptBanner))
    }

    @Test func testUnknownGroupFailsClosed() {
        var c = LoginConversation(profile: profile())
        checkEqual(c.receive("1) Guests\n2) Admins\nGroup: [1]"), .fail(.group))
    }

    @Test func testPreselectedGroupIsVerifiedBeforeCredentials() {
        var mismatch = LoginConversation(profile: profile())
        checkEqual(mismatch.receive("Group: Guests\nUsername:"), .fail(.group))
        var match = LoginConversation(profile: profile())
        checkEqual(match.receive("Group: Staff VPN\nUsername:"), .send(.username))
    }

    @Test func testRealCLIErrorAndStateParsing() {
        checkEqual(CLIText.failure("\r >> error: Application did not meet code signing requirements."), .signing)
        checkEqual(CLIText.state(" >> state: Disconnected\n"), .disconnected)
        checkEqual(CLIText.state(" >> state: Disconnected\n >> state: Connected\n"), .connected)
        checkEqual(CLIText.state("not connected"), .unknown)
    }

    @Test func testCiscoGUIConflictIsNotRetriedAsNetworkFailure() {
        let message =
            "Connect capability is unavailable. Another Cisco Secure Client application acquired it. Terminating the other application and restarting this application may resolve this issue."
        checkEqual(CLIText.failure(message), .clientBusy)
        checkFalse(VPNFailure.clientBusy.retryable)
    }

    @Test func testZeroBasedGroupAndTTYWarning() {
        var p = profile()
        p.group = "Employees"
        var c = LoginConversation(profile: p)
        checkEqual(c.receive("0) Employees\n1) Contractors\nGroup: [Employees] "), .send(.group("0")))
        checkEqual(c.receive("Username: [alice] "), .send(.username))
        checkEqual(
            c.receive("alice\n** unable to get tty! (using stdin), password will echo **\nPassword: "), .send(.otp))
        checkEqual(c.receive("Second Password: "), .send(.password))
    }

    @Test func testOlderProfilesKeepFieldsWhenRecoveryOptionIsAdded() throws {
        let json = Data(
            #"{"server":"https://vpn.example.com","group":"Staff","username":"alice","authMode":"otpThenPassword","acceptBanner":true}"#
                .utf8)
        let p = try JSONDecoder().decode(VPNProfile.self, from: json)
        checkEqual(p.username, "alice")
        checkEqual(p.group, "Staff")
        checkTrue(p.acceptBanner)
        checkTrue(p.releaseCiscoGUI)
        checkEqual(try JSONDecoder().decode(VPNProfile.self, from: JSONEncoder().encode(p)), p)
    }

    @Test func testBoundedNetworkRetrySchedule() {
        var r = RetryPolicy()
        checkEqual(r.nextDelay(), 30)
        checkEqual(r.nextDelay(), 60)
        checkEqual(r.nextDelay(), 120)
        checkNil(r.nextDelay())
        r.reset()
        checkEqual(r.nextDelay(), 30)
        checkFalse(VPNFailure.authentication.retryable)
        checkFalse(VPNFailure.signing.retryable)
    }
}
