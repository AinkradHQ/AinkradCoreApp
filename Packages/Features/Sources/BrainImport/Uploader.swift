import Foundation

/// A signed POST to the Core's brain module (the app's CoreConnection provides the real one).
public protocol ImportTransport: Sendable {
    func post(path: String, body: Data) async throws -> Data
}

/// Sends items in batches under the Core's signed-body cap, retrying a dropped connection (forever, when `retries` is
/// nil: only transient failures, see `ImportRetry`) and
/// remembering which batches were confirmed so a second call (or a restart that keeps `Progress`)
/// does not send them again. The Core dedupes by hash anyway; this just saves the bytes.
public struct Uploader: Sendable {
    public static let maxBatchBytes = 900_000
    /// Small, so the Core holds its write lock only briefly for each.
    public static let maxBatchItems = 100

    public actor Progress {
        var confirmed: Set<String> = []
        public init() {}
        func has(_ id: String) -> Bool { confirmed.contains(id) }
        func add(_ ids: [String]) { confirmed.formUnion(ids) }
        public var count: Int { confirmed.count }
    }

    public struct Failure: Error, Equatable { public let afterRetries: Int }

    let transport: any ImportTransport
    /// Nil: retry transient failures forever and stop on anything else.
    let retries: Int?
    let pause: @Sendable (Int) async -> Void
    /// True while a batch waits to be sent again, false once it went through.
    let onWaiting: @Sendable (Bool) async -> Void

    public init(
        transport: any ImportTransport, retries: Int? = nil,
        pause: @escaping @Sendable (Int) async -> Void = ImportRetry.pause,
        onWaiting: @escaping @Sendable (Bool) async -> Void = { _ in }
    ) {
        self.transport = transport
        self.retries = retries
        self.pause = pause
        self.onWaiting = onWaiting
    }

    /// Items grouped into batches whose JSON stays under the cap.
    public static func batches(_ items: [ImportItem]) throws -> [[ImportItem]] {
        let enc = JSONEncoder()
        var out: [[ImportItem]] = []
        var cur: [ImportItem] = []
        var size = 0
        for original in items {
            let (item, n) = try fitting(original, enc)
            if !cur.isEmpty, size + n > maxBatchBytes || cur.count >= maxBatchItems {
                out.append(cur)
                cur = []
                size = 0
            }
            cur.append(item)
            size += n
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    /// One item whose JSON alone passes the cap (terminal text full of control characters, each escaped to 6 bytes,
    /// 2026-11-23: the Core refused it with 413 on every retry) is cut until it fits, keeping its start and its end.
    static func fitting(_ item: ImportItem, _ enc: JSONEncoder) throws -> (ImportItem, Int) {
        var it = item
        var n = try enc.encode(it).count + 1
        while n > maxBatchBytes, it.text.count > 64 {
            let keep = max(Int(Double(it.text.count) * Double(maxBatchBytes) / Double(n) * 0.9), 32)
            it.text = String(it.text.prefix(keep / 2)) + "\n[…]\n" + String(it.text.suffix(keep / 2))
            it.content_hash = ItemFormat.hash(it.text)  // the Core checks the hash against the text
            n = try enc.encode(it).count + 1
        }
        return (it, n)
    }

    /// Uploads `items` to run `run`; returns how many were sent in this call.
    @discardableResult
    public func upload(_ items: [ImportItem], run: String, progress: Progress) async throws -> Int {
        var pending: [ImportItem] = []
        for i in items where await !progress.has(i.item_id) { pending.append(i) }
        var sent = 0
        for batch in try Self.batches(pending) {
            let body = try JSONEncoder().encode(["items": batch])
            if let retries {
                var attempt = 0
                while true {
                    do {
                        _ = try await transport.post(path: "/imports/\(run)/items", body: body)
                        break
                    } catch {
                        attempt += 1
                        if attempt > retries { throw Failure(afterRetries: retries) }
                        await pause(attempt)
                    }
                }
            } else {
                _ = try await ImportRetry.run(pause: pause, waiting: onWaiting) {
                    try await transport.post(path: "/imports/\(run)/items", body: body)
                }
            }
            await progress.add(batch.map(\.item_id))
            sent += batch.count
        }
        return sent
    }
}
