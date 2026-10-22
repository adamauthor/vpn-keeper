import Foundation
import Security

enum CiscoTrust {
    /// Validate Cisco's own signature before launching a binary that could receive secrets.
    static func isValid(_ executable: URL) -> Bool {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let rule = "anchor apple generic and identifier vpn and certificate leaf[subject.OU] = DE8Y96K9QP"
        guard SecRequirementCreateWithString(rule as CFString, [], &requirement) == errSecSuccess,
            SecStaticCodeCreateWithPath(executable.resolvingSymlinksInPath() as CFURL, [], &code) == errSecSuccess,
            let code
        else { return false }
        return SecStaticCodeCheckValidity(
            code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures), requirement)
            == errSecSuccess
    }
}
