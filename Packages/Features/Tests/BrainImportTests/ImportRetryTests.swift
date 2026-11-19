import Foundation
import Testing

@testable import BrainImport

/// A Core answer: `transient` is what a 5xx is and a 4xx is not.
private struct Answer: TransientFailure { let isTransient: Bool }

/// Fails `failures` times with `error`, then works; counts the calls.
private final class Flaky: ImportTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    let failures: Int
    let error: any Error
    init(failures: Int, error: any Error) {
        self.failures = failures
        self.error = error
    }
    var count: Int { lock.withLock { calls } }
    func post(path: String, body: Data) async throws -> Data {
        let n = lock.withLock { () -> Int in
            calls += 1
            return calls
        }
        if n <= failures { throw error }
        return Data()
    }
}

private func one() -> [ImportItem] {
    [
        ImportItem(
            item_id: ItemFormat.itemID(seed: "a"), source_kind: "claude_code", content_hash: ItemFormat.hash("a"),
            origin: .init(device: "d", path: "/p", range: nil), project_hint: nil,
            author: .init(kind: "person", name: "me"), title: "t", text: "a", links: [],
            started_at: "2026-11-01T09:00:00Z", ended_at: nil)
    ]
}

@Suite struct ImportRetryTests {
    @Test func transportErrorsAnd5xxRetryAnd4xxAndCancelStop() {
        #expect(ImportRetry.isTransient(URLError(.timedOut)))
        #expect(ImportRetry.isTransient(Answer(isTransient: true)))  // 5xx, 503
        #expect(!ImportRetry.isTransient(Answer(isTransient: false)))  // 4xx
        #expect(!ImportRetry.isTransient(CancellationError()))
        #expect(!ImportRetry.isTransient(Uploader.Failure(afterRetries: 3)))
    }

    @Test func thePauseGrowsFromOneSecondAndStopsAtThirty() {
        let s = (1...9).map { ImportRetry.seconds(attempt: $0) }
        #expect(s == [1, 2, 4, 8, 16, 30, 30, 30, 30])
    }

    @Test func uploadsRetryForeverOnATransientFailureAndSayWaiting() async throws {
        let t = Flaky(failures: 7, error: Answer(isTransient: true))  // more than the old 3 tries
        let said = Said()
        let up = Uploader(transport: t, pause: { _ in }, onWaiting: { await said.add($0) })
        #expect(try await up.upload(one(), run: "r", progress: .init()) == 1)
        #expect(t.count == 8)
        let log = await said.all
        #expect(log.first == true && log.last == false)
    }

    @Test func aClientErrorStopsAtOnceAndKeepsTheError() async throws {
        let t = Flaky(failures: 100, error: Answer(isTransient: false))
        let up = Uploader(transport: t, pause: { _ in })
        await #expect(throws: Answer.self) { try await up.upload(one(), run: "r", progress: .init()) }
        #expect(t.count == 1)
    }

    @Test func batchesAreSmallSoTheCoreHoldsItsLockBriefly() throws {
        let many = (0..<250).flatMap { _ in one() }
        #expect(try Uploader.batches(many).map(\.count) == [100, 100, 50])
    }
}

private actor Said {
    var all: [Bool] = []
    func add(_ b: Bool) { all.append(b) }
}
