import CoreKit
import Darwin
import Foundation
import Testing

@testable import Terminals

/// The decisions behind "use the runner's own socket, else the Core": each way the local path is not available falls back (nil),
/// and a decision of the Core's about this person is not hidden by a fallback.
@MainActor
@Suite(.serialized) struct LocalAttacherTests {
    private final class Calls: @unchecked Sendable {
        let lock = NSLock()
        var grants = 0
        var releases = 0
        var grantError: CoreError?
        func bump(_ f: (Calls) -> Void) { lock.withLock { f(self) } }
        var counts: (Int, Int) { lock.withLock { (grants, releases) } }
    }

    private func dir() throws -> String {
        let d = "/tmp/la-\(UUID().uuidString.prefix(8))"
        try FileManager.default.createDirectory(
            atPath: d, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return d
    }

    private func attacher(
        _ calls: Calls, runner: LocalRunner?, supported: Bool = true
    ) -> LocalAttacher {
        LocalAttacher(
            localRunner: { runner }, supported: { supported },
            source: { id in
                LocalGrantSource(
                    grant: {
                        calls.bump { $0.grants += 1 }
                        if let e = calls.lock.withLock({ calls.grantError }) { throw e }
                        return LocalTerminalGrant(
                            terminal: id, runner: "d_r", grant: "g", leaseSecs: 45, socket: "\(id).local.sock")
                    }, sign: { _ in Data(repeating: 1, count: 64) }, release: { calls.bump { $0.releases += 1 } })
            })
    }

    private func socket(in dir: String, id: String) {
        // A listening socket nobody serves: enough to exist; the connect succeeds and the handshake then times out or is refused.
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: Array("\(dir)/\(id).local.sock".utf8)) }
        _ = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        listen(fd, 1)
    }

    @Test func noLocalRunnerAnotherRunnerNoSocketOrAnOlderCoreAllFallBackWithoutAskingTheCore() async throws {
        let d = try dir()
        let local = LocalRunner(id: "d_r", terminals: URL(fileURLWithPath: d))
        let calls = Calls()
        // No runner on this Mac.
        #expect(try await attacher(calls, runner: nil).attach("t_1", runner: "d_r", after: 0) == nil)
        // The terminal is on another runner.
        #expect(try await attacher(calls, runner: local).attach("t_1", runner: "d_other", after: 0) == nil)
        // No socket: a host from an older build.
        #expect(try await attacher(calls, runner: local).attach("t_1", runner: "d_r", after: 0) == nil)
        // A Core without the routes.
        socket(in: d, id: "t_1")
        #expect(
            try await attacher(calls, runner: local, supported: false).attach("t_1", runner: "d_r", after: 0) == nil)
        #expect(calls.counts.0 == 0)
    }

    @Test func aCoreThatCannotGrantNowFallsBackButAnswersAboutThePersonAreNotHidden() async throws {
        let d = try dir()
        socket(in: d, id: "t_1")
        let local = LocalRunner(id: "d_r", terminals: URL(fileURLWithPath: d))
        for status in [404, 405, 409, 501] {
            let calls = Calls()
            calls.grantError = .http(status: status, code: "x", message: "")
            #expect(try await attacher(calls, runner: local).attach("t_1", runner: "d_r", after: 0) == nil, "\(status)")
        }
        for error in [
            CoreError.http(status: 403, code: "step_up_required", message: ""), .stepUpRequired, .forbiddenScope,
            .revoked,
        ] {
            let calls = Calls()
            calls.grantError = error
            await #expect(throws: CoreError.self) {
                try await attacher(calls, runner: local).attach("t_1", runner: "d_r", after: 0)
            }
        }
    }

    @Test func aHostThatDoesNotTakeTheGrantHandsTheLeaseBackAndFallsBack() async throws {
        let d = try dir()
        socket(in: d, id: "t_1")
        let local = LocalRunner(id: "d_r", terminals: URL(fileURLWithPath: d))
        let calls = Calls()
        // The socket exists but nobody speaks on it: the handshake times out, the lease is released, the Core path takes over.
        #expect(try await attacher(calls, runner: local).attach("t_1", runner: "d_r", after: 0) == nil)
        #expect(calls.counts == (1, 1))
    }

    @Test func aSessionAsksForTheLocalPathByTheTerminalsRunner() async {
        let svc = FakeService()
        svc.attachResults = [.success(FakeLink())]
        let host = FakeHost()
        let t = item("t_1", runner: "d_r")
        let s = TerminalSession(item: t, runner: runner("d_r"), service: svc, host: host)
        await s.attach()
        #expect(svc.attachRunners == ["d_r"])
    }
}
