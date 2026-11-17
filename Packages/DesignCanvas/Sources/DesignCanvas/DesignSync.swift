import Foundation

/// One message on a document's sync socket (y-sync v1 shape): a state vector (step 1), an update (step 2 or a live edit),
/// or presence (awareness). The bytes are opaque here; the engine and the Core decode them.
public enum DesignSyncMessage: Sendable, Equatable {
    case stateVector(Data)
    case update(Data)
    case awareness(Data)
}

/// The per-document socket. The live one is the CoreKit device-signed WebSocket
/// `GET /modules/design/v1/docs/{d}/sync` (T3), which the Core does not serve yet:
/// TODO(V1-03): implement `DesignSyncChannel` over `CoreConnection` once V1-03 lands the route and its framing.
public protocol DesignSyncChannel: Sendable {
    /// Opens the socket for `doc`. The stream ends (or throws) when the link drops.
    func open(doc: String) async throws -> AsyncThrowingStream<DesignSyncMessage, any Error>
    func send(_ message: DesignSyncMessage, doc: String) async throws
}

/// Relays bytes between a channel and the engine's local yrs doc. On every (re)connect it sends its state vector, so the
/// peer answers with exactly what this replica missed: a reconnect resyncs. A peer's state vector is answered with the
/// diff it lacks, which also carries edits made while the link was down. Read-only targets (the design system) never send.
@MainActor
public final class DesignSync {
    let engine: Engine
    let doc: String
    let target: Engine.Target
    let channel: any DesignSyncChannel
    /// Called after a remote update is applied (the canvas draws a frame).
    var onRemote: () -> Void = {}
    private var task: Task<Void, Never>?
    private(set) public var connected = false
    /// Reconnect backoff in seconds: 0.5, 1, 2 … 10.
    var backoff: (Int) -> Double = { min(10, 0.5 * pow(2, Double($0))) }

    public init(engine: Engine, doc: String, target: Engine.Target = .doc, channel: any DesignSyncChannel) {
        self.engine = engine
        self.doc = doc
        self.target = target
        self.channel = channel
    }

    public func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            var attempt = 0
            while !Task.isCancelled {
                guard let self else { return }
                if await self.session() { attempt = 0 } else { attempt += 1 }
                try? await Task.sleep(for: .seconds(self.backoff(attempt)))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        connected = false
    }

    /// One connection: true when it opened.
    private func session() async -> Bool {
        guard let stream = try? await channel.open(doc: doc) else { return false }
        connected = true
        defer { connected = false }
        if let sv = engine.stateVector() { try? await channel.send(.stateVector(sv), doc: doc) }
        flush()
        do {
            for try await m in stream {
                switch m {
                case .stateVector(let sv):
                    if target == .doc, let d = engine.diff(sv) { try await channel.send(.update(d), doc: doc) }
                case .update(let u):
                    switch engine.apply(u, to: target) {
                    case .applied: onRemote()
                    case .refused: break
                    case .reset:
                        // The engine reset the doc: ask for everything again (unsent local edits are kept).
                        onRemote()
                        if let sv = engine.stateVector() { try await channel.send(.stateVector(sv), doc: doc) }
                    case .halted:
                        // Remote updates no longer apply to this engine; reopening the design makes a new one.
                        task?.cancel()
                        task = nil
                        return true
                    }
                case .awareness(let a):
                    engine.presenceApply(a)
                    onRemote()
                }
            }
        } catch {}
        return true
    }

    /// Sends local edits (after a gesture, a key, undo), in as many updates as the engine splits them into. Nothing while
    /// offline: the next connect's diff carries them.
    public func flush() {
        guard target == .doc, connected else { return }
        var updates: [Data] = []
        while let u = engine.outbox(), !u.isEmpty { updates.append(u) }
        guard !updates.isEmpty else { return }
        let (channel, doc) = (channel, doc)
        Task { for u in updates { try? await channel.send(.update(u), doc: doc) } }
    }
}
