import Darwin
import Foundation

public enum CLIResult: Equatable {
    case state(VPNState)
    case failed(VPNFailure)
}

public enum CLIPhase: String, Codable {
    case startingState, startingConnection, startingDisconnect
    case sentGroup, sentUsername, sentOTP, sentPassword, sentPasswordAndOTP, acceptedBanner
    case connected, failed
}

/// Only the genuine Cisco executable receives credentials, through stdin.
/// Raw output stays in this short-lived object and is never persisted or returned to the UI.
public final class CLIProcess: @unchecked Sendable {
    public enum Request {
        case state
        case connect(VPNProfile, VaultEntry)
        case disconnect
    }
    private let queue = DispatchQueue(label: "kz.local.vpnkeeper.cli.\(UUID().uuidString)")
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let request: Request
    private let executable: URL
    private let onPhase: (@Sendable (CLIPhase) -> Void)?
    private var continuation: CheckedContinuation<CLIResult, Never>?
    private var finished = false
    private var cancelled = false
    private var transcript = ""
    private var conversation: LoginConversation?
    private var deadline: DispatchWorkItem?
    private var echoesPasswords = false
    private var pendingEcho: Data?
    private var echoBuffer = Data()

    public init(executable: URL, request: Request, onPhase: (@Sendable (CLIPhase) -> Void)? = nil) {
        self.executable = executable
        self.request = request
        self.onPhase = onPhase
        if case .connect(let profile, _) = request { conversation = LoginConversation(profile: profile) }
    }

    public func run() async -> CLIResult {
        await withTaskCancellationHandler(
            operation: {
                await withCheckedContinuation { continuation in
                    queue.async { self.start(continuation) }
                }
            }, onCancel: { self.cancel() })
    }

    public func cancel() {
        queue.async {
            self.cancelled = true
            self.finish(.failed(.cancelled))
        }
    }

    private func start(_ continuation: CheckedContinuation<CLIResult, Never>) {
        self.continuation = continuation
        if cancelled || finished {
            continuation.resume(returning: .failed(.cancelled))
            self.continuation = nil
            return
        }
        process.executableURL = executable
        switch request {
        case .state:
            process.arguments = ["state"]
            onPhase?(.startingState)
        case .disconnect:
            process.arguments = ["disconnect"]
            onPhase?(.startingDisconnect)
        case .connect(let profile, _):
            process.arguments = ["-s", "connect", profile.server]
            onPhase?(.startingConnection)
        }
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        // Do not copy user credentials into arguments, environment variables, or shell scripts.
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async { [weak self] in self?.receive(data) }
        }
        process.terminationHandler = { [weak self] _ in
            // Let already delivered pipe reads reach the serial queue first.
            self?.queue.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.exited() }
        }
        do { try process.run() } catch {
            finish(.failed(.service))
            return
        }
        let timeout: TimeInterval
        if case .connect = request { timeout = 120 } else { timeout = 12 }
        let deadline = DispatchWorkItem { [weak self] in self?.finish(.failed(.timeout)) }
        self.deadline = deadline
        queue.asyncAfter(deadline: .now() + timeout, execute: deadline)
    }

    private func receive(_ data: Data) {
        guard !finished else { return }
        let filtered = removeExpectedEcho(data)
        guard !filtered.isEmpty else { return }
        let text = String(decoding: filtered, as: UTF8.self)
        if (transcript + text).lowercased().contains("password will echo") { echoesPasswords = true }
        transcript += text
        guard transcript.utf8.count <= 65536 else {
            finish(.failed(.unsupported))
            return
        }
        if let failure = CLIText.failure(transcript) {
            finish(.failed(failure))
            return
        }
        guard conversation != nil, let action = conversation?.receive(text) else { return }
        switch action {
        case .connected: finish(.state(.connected))
        case .fail(let failure): finish(.failed(failure))
        case .send(let field):
            var delay: TimeInterval = 0
            if case .connect(_, let vault) = request {
                switch field {
                case .otp, .passwordPlusOTP:
                    let remaining = vault.token.secondsRemaining()
                    if remaining < 5 { delay = remaining + 0.3 }
                default: break
                }
            }
            queue.asyncAfter(deadline: .now() + delay) { [weak self] in self?.respond(field) }
        }
    }

    private func respond(_ field: LoginConversation.Field) {
        guard !finished, process.isRunning, case .connect(let profile, let vault) = request else { return }
        do {
            let value: String
            switch field {
            case .group(let group): value = group
            case .username: value = profile.username
            case .password: value = vault.password
            case .otp: value = try vault.token.code()
            case .passwordPlusOTP: value = vault.password + (try vault.token.code())
            case .acceptBanner: value = "y"
            }
            if echoesPasswords {
                switch field {
                case .otp, .password, .passwordPlusOTP:
                    pendingEcho = Data(value.utf8)
                    echoBuffer = Data()
                default: break
                }
            }
            try input.fileHandleForWriting.write(contentsOf: Data((value + "\n").utf8))
            switch field {
            case .group: onPhase?(.sentGroup)
            case .username: onPhase?(.sentUsername)
            case .otp: onPhase?(.sentOTP)
            case .password: onPhase?(.sentPassword)
            case .passwordPlusOTP: onPhase?(.sentPasswordAndOTP)
            case .acceptBanner: onPhase?(.acceptedBanner)
            }
        } catch { finish(.failed(.unsupported)) }
    }

    private func removeExpectedEcho(_ data: Data) -> Data {
        guard let expected = pendingEcho else { return data }
        echoBuffer.append(data)
        let candidate = Data(echoBuffer.drop(while: { $0 == 10 || $0 == 13 }))
        if expected.starts(with: candidate) { return Data() }
        if candidate.starts(with: expected) {
            let suffix = candidate.dropFirst(expected.count)
            if let first = suffix.first, first == 10 || first == 13 {
                pendingEcho = nil
                echoBuffer = Data()
                return Data(suffix.drop(while: { $0 == 10 || $0 == 13 }))
            }
        }
        let result = echoBuffer
        pendingEcho = nil
        echoBuffer = Data()
        return result
    }

    private func exited() {
        guard !finished else { return }
        if let failure = CLIText.failure(transcript) {
            finish(.failed(failure))
            return
        }
        let state = CLIText.state(transcript)
        switch request {
        case .connect:
            finish(state == .connected ? .state(.connected) : .failed(.network))
        case .state:
            finish(state != .unknown ? .state(state) : .failed(.service))
        case .disconnect:
            finish(process.terminationStatus == 0 ? .state(.disconnected) : .failed(.service))
        }
    }

    private func finish(_ result: CLIResult) {
        guard !finished else { return }
        finished = true
        if result == .state(.connected) { onPhase?(.connected) } else if case .failed = result { onPhase?(.failed) }
        deadline?.cancel()
        deadline = nil
        output.fileHandleForReading.readabilityHandler = nil
        process.terminationHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            let child = process
            queue.asyncAfter(deadline: .now() + 2) {
                if child.isRunning { _ = Darwin.kill(child.processIdentifier, SIGKILL) }
            }
        }
        // No raw transcript survives completion, including echoed responses.
        transcript = ""
        conversation = nil
        pendingEcho = nil
        echoBuffer = Data()
        continuation?.resume(returning: result)
        continuation = nil
    }
}
