import AppKit

@MainActor
enum CiscoGUI {
    /// Request a normal Quit only. Never terminate vpnagent, kill other CLIs, or force-quit.
    static func releaseConnectionControl() async -> Bool {
        let clients = NSRunningApplication.runningApplications(withBundleIdentifier: "com.cisco.secureclient.gui")
        if clients.isEmpty { return false }
        for client in clients where !client.isTerminated {
            guard client.terminate() else { return false }
        }
        for _ in 0..<20 {
            if clients.allSatisfy(\.isTerminated) { return true }
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return false }
        }
        return false
    }
}
