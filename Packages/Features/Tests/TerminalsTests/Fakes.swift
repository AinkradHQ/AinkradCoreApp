import CoreKit
import Foundation
import Shell

@testable import Terminals

@MainActor
final class FakeHost: TerminalHost {
    let shell = ShellModel()
    var isElevated = true
    var elevationNotice: ElevationNotice?
    var declines = false
    private(set) var reasons: [String] = []
    func clearElevationNotice() { elevationNotice = nil }
    func elevated<T>(_ reason: String, done: String, keepsEdit: Bool, _ op: () async throws -> T) async throws -> T {
        reasons.append(reason)
        if declines { throw ElevationDeclined() }
        isElevated = true
        return try await op()
    }
}

final class FakeLink: TerminalLink, @unchecked Sendable {
    let opened: TerminalOpened
    let updates: AsyncStream<TerminalUpdate>
    private let feed: AsyncStream<TerminalUpdate>.Continuation
    private let lock = NSLock()
    private var state = (cursor: UInt64(0), detached: false, inputs: [Data](), sizes: [[Int]](), drawn: 0)
    init(cols: Int = 80, rows: Int = 24, seq: UInt64 = 0, state: String = "running") {
        opened = TerminalOpened(state: state, rows: rows, cols: cols, seq: seq)
        var c: AsyncStream<TerminalUpdate>.Continuation!
        updates = AsyncStream { c = $0 }
        feed = c
    }
    var cursor: UInt64 { lock.withLock { state.cursor } }
    var repainted: Bool { false }
    var detached: Bool { lock.withLock { state.detached } }
    var inputs: [Data] { lock.withLock { state.inputs } }
    var sizes: [[Int]] { lock.withLock { state.sizes } }
    var drawnBytes: Int { lock.withLock { state.drawn } }
    func input(_ bytes: Data) { lock.withLock { state.inputs.append(bytes) } }
    func resize(rows: Int, cols: Int) { lock.withLock { state.sizes.append([cols, rows]) } }
    func drawn(_ bytes: Int) { lock.withLock { state.drawn += bytes } }
    func detach() {
        lock.withLock { state.detached = true }
        feed.yield(.closed(.detached))
        feed.finish()
    }
    func push(_ u: TerminalUpdate, cursor: UInt64? = nil) {
        if let cursor { lock.withLock { state.cursor = cursor } }
        feed.yield(u)
    }
}

final class FakeService: TerminalService, @unchecked Sendable {
    private let lock = NSLock()
    var terminalList: [TerminalItem] = []
    var runnerList: [RunnerItem] = []
    var attachResults: [Result<FakeLink, CoreError>] = []
    var createResult: Result<TerminalItem, CoreError> = .failure(.offline("x"))
    private(set) var attachAfters: [UInt64] = []
    private(set) var signals: [String] = []
    private(set) var closed: [String] = []
    private(set) var created: [(runner: String, program: String?)] = []

    func terminals() async throws -> [TerminalItem] { lock.withLock { terminalList } }
    func terminal(_ id: String) async throws -> TerminalItem {
        guard let t = lock.withLock({ terminalList.first { $0.id == id } }) else {
            throw CoreError.http(status: 404, code: "not_found", message: "no")
        }
        return t
    }
    func runners() async throws -> [RunnerItem] { lock.withLock { runnerList } }
    func create(runner: String, program: String?, rows: Int, cols: Int) async throws -> TerminalItem {
        lock.withLock { created.append((runner, program)) }
        return try lock.withLock { createResult }.get()
    }
    func close(_ id: String) async throws -> TerminalItem {
        lock.withLock { closed.append(id) }
        var t = try await terminal(id)
        t.status = "exited"
        return t
    }
    func signal(_ id: String, _ name: String) async throws { lock.withLock { signals.append(name) } }
    func noop(_ runner: String) async throws -> Int { 31 }
    func attach(_ id: String, after: UInt64) async throws -> any TerminalLink {
        let r = lock.withLock { () -> Result<FakeLink, CoreError> in
            attachAfters.append(after)
            return attachResults.isEmpty ? .failure(.offline("none")) : attachResults.removeFirst()
        }
        return try r.get()
    }
}

func item(
    _ id: String = "t_1", runner: String = "r1", status: String = "running", attached: Int = 0, orphaned: Bool = false,
    code: Int32? = nil, signal: String? = nil
) -> TerminalItem {
    TerminalItem(
        id: id, runner: runner, status: status, rows: 24, cols: 80, seq: 0, attached: attached, orphaned: orphaned,
        exitCode: code, exitSignal: signal, createdAt: Date(timeIntervalSince1970: 1_800_000_000))
}

func runner(_ id: String = "r1", online: Bool = true, degraded: Bool = false, avg1: Double = 1, pty: Bool = true)
    -> RunnerItem
{
    RunnerItem(
        id: id, name: "mac-studio", online: online, degraded: degraded, load: 1, capacity: 4, avg1: avg1, cores: 4,
        version: "0.24.0", arch: "aarch64", lastSeen: nil,
        drivers: pty ? [DriverItem(name: "pty", commands: ["noop"], capacity: 16)] : [], isolationTiers: nil)
}

/// Waits for a condition on the main actor (the session reacts to updates asynchronously).
@MainActor func until(_ what: String = "", _ ok: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<200 where !ok() { try? await Task.sleep(for: .milliseconds(10)) }
    return ok()
}
