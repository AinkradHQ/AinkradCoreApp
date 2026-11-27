import Foundation
import Testing

@testable import DesignCanvas

/// The Core's end of one socket: tests push frames in and read what the client sent.
final class FakeWire: DesignSocket, @unchecked Sendable {
    private let lock = NSLock()
    private var sentFrames: [DesignSocketFrame] = []
    private let incoming: AsyncThrowingStream<DesignSocketFrame, any Error>
    private let feed: AsyncThrowingStream<DesignSocketFrame, any Error>.Continuation
    private var iterator: AsyncThrowingStream<DesignSocketFrame, any Error>.AsyncIterator
    var closeCode = 0
    private(set) var cancelled = false

    init() {
        (incoming, feed) = AsyncThrowingStream.makeStream()
        iterator = incoming.makeAsyncIterator()
    }
    func push(_ f: DesignSocketFrame) { feed.yield(f) }
    func close(_ code: Int) {
        closeCode = code
        feed.finish(throwing: URLError(.networkConnectionLost))
    }
    func receive() async throws -> DesignSocketFrame {
        guard let f = try await iterator.next() else { throw URLError(.networkConnectionLost) }
        return f
    }
    func send(_ frame: DesignSocketFrame) async throws { lock.withLock { sentFrames.append(frame) } }
    func cancel() {
        cancelled = true
        feed.finish()
    }
    var sent: [DesignSocketFrame] { lock.withLock { sentFrames } }
}

private func frame(_ tag: UInt8, _ seq: UInt64, _ body: [UInt8] = []) -> DesignSocketFrame {
    .binary(Data([tag]) + withUnsafeBytes(of: seq.bigEndian) { Data($0) } + Data(body))
}

private final class Opens: @unchecked Sendable {
    private let lock = NSLock()
    var seqs: [UInt64?] = []
    var wires: [FakeWire] = []
    func make(_ seq: UInt64?) -> FakeWire {
        lock.withLock {
            seqs.append(seq)
            let w = FakeWire()
            wires.append(w)
            return w
        }
    }
}

@Suite struct CoreDesignSyncChannelTests {
    @Test func decodesEveryFrameKind() {
        #expect(DesignSyncWire.decode(Data([1, 0, 0, 0, 0, 0, 0, 1, 2, 9, 8])) == .update(seq: 258, Data([9, 8])))
        #expect(DesignSyncWire.decode(Data([2, 0, 0, 0, 0, 0, 0, 0, 7, 5])) == .snapshot(seq: 7, Data([5])))
        #expect(DesignSyncWire.decode(Data([3, 0, 0, 0, 0, 0, 0, 0, 4])) == .ack(seq: 4))
        #expect(DesignSyncWire.decode(Data([3, 0, 0, 0, 0, 0, 0, 0, 4, 1])) == nil)  // an ack has no body
        #expect(DesignSyncWire.decode(Data([9, 0, 0, 0, 0, 0, 0, 0, 1])) == nil)  // unknown tag
        #expect(DesignSyncWire.decode(Data([1, 0, 0])) == nil)  // short
        #expect(DesignSyncWire.encode(update: Data([4, 5])) == Data([1, 4, 5]))
    }

    @Test func deliversUpdatesAndResumesFromTheHighestSeq() async throws {
        let opens = Opens()
        let channel = CoreDesignSyncChannel { _, seq in opens.make(seq) }
        let stream = try await channel.open(doc: "dd_a")
        #expect(opens.seqs == [nil])
        let wire = opens.wires[0]
        wire.push(frame(2, 5, [1]))
        wire.push(frame(1, 9, [2]))
        wire.push(frame(1, 7, [3]))  // an older one never moves the cursor back
        var got: [Data] = []
        for try await m in stream {
            if case .update(let d) = m { got.append(d) }
            if got.count == 3 { break }
        }
        #expect(got == [Data([1]), Data([2]), Data([3])])
        #expect(await channel.lastSeq("dd_a") == 9)
        wire.close(1013)
        _ = try await channel.open(doc: "dd_a")
        #expect(opens.seqs == [nil, 9])
    }

    @Test func resendsWhatTheCoreNeverAcknowledged() async throws {
        let opens = Opens()
        let channel = CoreDesignSyncChannel { _, seq in opens.make(seq) }
        let stream = try await channel.open(doc: "dd_a")
        try await channel.send(.update(Data([1])), doc: "dd_a")
        try await channel.send(.update(Data([2])), doc: "dd_a")
        #expect(opens.wires[0].sent == [.binary(Data([1, 1])), .binary(Data([1, 2]))])
        opens.wires[0].push(frame(3, 1))  // the first is stored
        opens.wires[0].push(frame(1, 4, [7]))
        for try await _ in stream { break }  // the ack came before this update
        opens.wires[0].close(1013)
        _ = try await channel.open(doc: "dd_a")
        #expect(opens.wires[1].sent == [.binary(Data([1, 2]))])
    }

    @Test func aResyncCloseDropsTheCursor() async throws {
        let opens = Opens()
        let channel = CoreDesignSyncChannel { _, seq in opens.make(seq) }
        let stream = try await channel.open(doc: "dd_a")
        opens.wires[0].push(frame(1, 3, [1]))
        for try await _ in stream { break }
        opens.wires[0].close(4412)
        do { for try await _ in stream {} } catch {}
        _ = try await channel.open(doc: "dd_a")
        #expect(opens.seqs == [nil, nil])
    }

    @Test func aSecondStateVectorAsksForEverythingAgain() async throws {
        let opens = Opens()
        let channel = CoreDesignSyncChannel { _, seq in opens.make(seq) }
        let stream = try await channel.open(doc: "dd_a")
        try await channel.send(.stateVector(Data([0])), doc: "dd_a")  // the connect handshake: dropped
        #expect(!opens.wires[0].cancelled)
        try await channel.send(.stateVector(Data([0])), doc: "dd_a")  // "again": close, resume without a cursor
        #expect(opens.wires[0].cancelled)
        #expect(await channel.lastSeq("dd_a") == nil)
        withExtendedLifetime(stream) {}
    }

    @Test func aBadFrameEndsTheStream() async throws {
        let opens = Opens()
        let channel = CoreDesignSyncChannel { _, seq in opens.make(seq) }
        let stream = try await channel.open(doc: "dd_a")
        opens.wires[0].push(.binary(Data([9])))
        await #expect(throws: DesignSyncFailure.badFrame) { for try await _ in stream {} }
    }

    @Test func presenceTextFramesAreLabelledAndMineGoOutAsText() async throws {
        let opens = Opens()
        let channel = CoreDesignSyncChannel { _, seq in opens.make(seq) }
        let stream = try await channel.open(doc: "dd_a")
        opens.wires[0].push(.text(#"{"peer":"session:as_1","conn":2,"selection":[]}"#))
        opens.wires[0].push(.text("not json"))  // hostile text is dropped, the socket stays up
        opens.wires[0].push(.text(#"{"conn":2,"gone":true}"#))
        var got: [String] = []
        for try await m in stream {
            if case .awareness(let a) = m { got.append(String(decoding: a, as: UTF8.self)) }
            if got.count == 2 { break }
        }
        #expect(got[0].contains("An AI session") && !got[1].contains("label"))
        try await channel.send(.awareness(Data(#"{"selection":[]}"#.utf8)), doc: "dd_a")
        #expect(opens.wires[0].sent == [.text(#"{"selection":[]}"#)])
    }
}
