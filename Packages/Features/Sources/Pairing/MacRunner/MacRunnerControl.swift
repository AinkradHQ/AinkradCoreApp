import Foundation
import ServiceManagement

/// Where this Mac's runner stands with the system's own list of Login Items and background agents.
enum RunnerRegistration: Equatable, Sendable {
    case notRegistered, enabled
    /// Registered, but the person must allow it in System Settings, Login Items.
    case needsApproval
    /// The app has no agent plist (a build without the runner).
    case notFound
}

/// What a Mac runner remembers of its pairing (the runner's own `enrolment.json`).
struct MacEnrolment: Equatable, Sendable {
    let deviceID: String
    let url: String
}

struct MacRunnerFailure: Error, Equatable, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// The runner that ships inside the app, as the model needs it. The seam is here so tests never touch launchd or a process.
protocol MacRunnerControl: Sendable {
    /// The bundle holds `ainkrad-runner` (and the pty host).
    var isBundled: Bool { get }
    func registration(terminals: Bool) -> RunnerRegistration
    /// Registers the agent that starts at login (the plist that offers terminals when `terminals`), and removes the other one.
    func register(terminals: Bool) throws
    func unregister() throws
    func enrolment() -> MacEnrolment?
    /// `ainkrad-runner pair <core> --invite <token>`: waits for it to end. The token is spent by it.
    func pair(core: URL, token: String) async throws
    /// Deletes the runner's key and enrolment (the Core has revoked it or been forgotten).
    func forgetEnrolment()
    func openLoginItems()
}

/// The real thing: the runner and pty host in `Contents/Helpers`, two agent plists in `Contents/Library/LaunchAgents`
/// (they differ only in `--enable-pty`, because a plist cannot change after signing), registered with `SMAppService`.
struct LiveMacRunnerControl: MacRunnerControl {
    static let plain = "com.ainkrad.core.runner.plist"
    static let withTerminals = "com.ainkrad.core.runner.terminals.plist"

    private var helpers: URL { Bundle.main.bundleURL.appending(path: "Contents/Helpers", directoryHint: .isDirectory) }
    private var runner: URL { helpers.appending(path: "ainkrad-runner") }
    /// The runner's default state (`$HOME/.ainkrad-runner/core`, device key and enrolment, both 0600, the folder 0700): the agent
    /// plists name no `--state`, because a plist cannot know the home folder.
    private var state: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(
            path: ".ainkrad-runner/core", directoryHint: .isDirectory)
    }

    var isBundled: Bool { FileManager.default.isExecutableFile(atPath: runner.path) }

    private func service(_ terminals: Bool) -> SMAppService {
        .agent(plistName: terminals ? Self.withTerminals : Self.plain)
    }

    func registration(terminals: Bool) -> RunnerRegistration {
        for t in [terminals, !terminals] {
            switch service(t).status {
            case .enabled: return .enabled
            case .requiresApproval: return .needsApproval
            default: continue
            }
        }
        return service(terminals).status == .notFound ? .notFound : .notRegistered
    }

    func register(terminals: Bool) throws {
        try? service(!terminals).unregister()
        do { try service(terminals).register() } catch {
            // Already registered is fine; a pending approval is read back from `registration`.
            if service(terminals).status == .enabled || service(terminals).status == .requiresApproval { return }
            throw MacRunnerFailure(message: "macOS would not start the runner: \(error.localizedDescription)")
        }
    }

    func unregister() throws {
        for t in [true, false] {
            let s = service(t)
            if s.status == .enabled || s.status == .requiresApproval { try s.unregister() }
        }
    }

    func enrolment() -> MacEnrolment? {
        guard let data = try? Data(contentsOf: state.appending(path: "enrolment.json")) else { return nil }
        return Self.parseEnrolment(data)
    }

    static func parseEnrolment(_ data: Data) -> MacEnrolment? {
        guard let v = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let id = v["device_id"] as? String, let url = v["url"] as? String
        else { return nil }
        return MacEnrolment(deviceID: id, url: url)
    }

    func pair(core: URL, token: String) async throws {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, any Error>) in
            let p = Process()
            p.executableURL = runner
            p.arguments = ["pair", core.absoluteString, "--invite", token]
            // No inherited environment: nothing of the app's goes to the runner.
            p.environment = ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin"]
            let err = Pipe()
            p.standardError = err
            p.standardOutput = FileHandle.nullDevice
            p.terminationHandler = { p in
                let text = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if p.terminationStatus == 0 {
                    done.resume()
                } else {
                    done.resume(
                        throwing: MacRunnerFailure(
                            message: Self.pairMessage(text.replacingOccurrences(of: token, with: "…"))))
                }
            }
            do { try p.run() } catch {
                done.resume(
                    throwing: MacRunnerFailure(message: "The runner would not start: \(error.localizedDescription)"))
            }
        }
    }

    /// The runner's last line, so the person sees the reason (an expired invite, an unreachable Core) and not a code.
    static func pairMessage(_ stderr: String) -> String {
        let line =
            stderr.split(whereSeparator: \.isNewline).last.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        return line.isEmpty ? "The runner could not pair with the Core." : "The runner could not pair: \(line)"
    }

    func forgetEnrolment() {
        for f in ["enrolment.json", "device.p8"] { try? FileManager.default.removeItem(at: state.appending(path: f)) }
    }

    func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }
}

/// Demo mode and previews: no runner inside, nothing to register.
struct NoMacRunner: MacRunnerControl {
    var isBundled: Bool { false }
    func registration(terminals: Bool) -> RunnerRegistration { .notFound }
    func register(terminals: Bool) throws {}
    func unregister() throws {}
    func enrolment() -> MacEnrolment? { nil }
    func pair(core: URL, token: String) async throws {}
    func forgetEnrolment() {}
    func openLoginItems() {}
}
