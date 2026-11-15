import BrainImport
import CryptoKit
import Foundation
import Testing

@testable import Admin
@testable import Brain
@testable import CoreKit
@testable import Pairing
@testable import Shell

// Against a real local Core, only when `BRAIN_IT=1`: `scripts/brain-it.sh` starts a throwaway Core with the Brain, pairs this
// test as a device, then the test seeds made-up sources into three rooms (no records: nothing is distilled) and calls what the
// Inbox and a room's Items tab call, through the app's own service and transport. Each call prints its status or its decode
// error; `BRAIN_IT_OUT` gets each route's JSON, for the decode tests.

private let env = ProcessInfo.processInfo.environment
private func need(_ name: String) throws -> String { try #require(env[name], "\(name) is not set") }

/// The memory store with a software step-up key, so this test can commit an import and open rooms without Touch ID (the
/// Core takes any registered step-up key; only a real device's is in the Secure Enclave).
private final class SoftwareStepUpStore: KeyStore, @unchecked Sendable {
    let inner = makeMemoryKeyStore()
    let lock = NSLock()
    var stepup: SoftwareKey?
    func key(_ role: KeyRole, reason: String) throws -> (any DeviceKey)? {
        role == .stepup ? lock.withLock { stepup } : try inner.key(role, reason: reason)
    }
    func generateKey(_ role: KeyRole) throws -> (any DeviceKey)? {
        guard role == .stepup else { return try inner.generateKey(role) }
        let k = SoftwareKey(key: P256.Signing.PrivateKey())
        lock.withLock { stepup = k }
        return k
    }
    func deleteKey(_ role: KeyRole) throws {
        if role == .stepup { lock.withLock { stepup = nil } } else { try inner.deleteKey(role) }
    }
    func loadIdentity() throws -> PairedIdentity? { try inner.loadIdentity() }
    func saveIdentity(_ identity: PairedIdentity) throws { try inner.saveIdentity(identity) }
    func loadPending() throws -> PendingPairing? { try inner.loadPending() }
    func savePending(_ pending: PendingPairing) throws { try inner.savePending(pending) }
    func clearPending() throws { try inner.clearPending() }
    func wipe() throws { try inner.wipe() }
}

@MainActor private final class LiveHost: AdminHost {
    let shell = ShellModel()
    var pausedReason: String?
    var elevationNotice: AdminNotice?
    func clearElevationNotice() { elevationNotice = nil }
    func elevated<T>(_ reason: String, done: String, keepsEdit: Bool, _ op: () async throws -> T) async throws -> T {
        try await op()
    }
    func rateLimited(retryAfter: TimeInterval?) {}
}

@Suite(.serialized) struct BrainLiveTests {
    @Test(.enabled(if: env["BRAIN_IT"] == "1"), .timeLimit(.minutes(10)))
    func inboxAndItemsAgainstARealCore() async throws {
        let url = try #require(URL(string: try need("CORE_IT_URL")))
        let store = SoftwareStepUpStore()
        let pairing = DevicePairing(keyStore: store)
        let claim = try await pairing.claim(try .parse(try need("CORE_IT_CODE")), endpoint: url)
        try claim.sas.write(toFile: try need("CORE_IT_SAS_FILE"), atomically: true, encoding: .utf8)
        try await pairing.confirmSAS()
        try await pairing.awaitApproval(timeout: .seconds(55))
        let conn = try CoreConnection.open(keyStore: store)
        _ = try await conn.connect()
        let transport = LiveBrainTransport(connection: conn)
        let service = CoreBrainService(transport: transport)
        let routes = service.routes
        print("IT paired")

        // Seed: about 2,000 made-up sources in three project folders, committed as three rooms.
        let run = try await routes.startRun(sources: ["claude_code"])
        let plan = [("Northwind", 1_700), ("Lantern", 250), ("Quill", 60)]
        var items: [ImportItem] = []
        for (project, n) in plan {
            for i in 0..<n {
                let text =
                    "Made-up session \(i) about \(project): the build step, a cache key and a retry rule \(i * 7)."
                let item: [String: Any] = [
                    "item_id": ItemFormat.itemID(seed: "\(project)-\(i)"), "source_kind": "claude_code",
                    "content_hash": ItemFormat.hash(text),
                    "origin": ["device": "mac-it", "path": "/synthetic/\(project)/s\(i).jsonl"],
                    "project_hint": "/h/Projects/\(project)/app", "author": ["kind": "person", "name": "dev"],
                    "title": "\(project) session \(i)", "text": text, "links": [String](),
                    "started_at": String(format: "2026-10-%02dT%02d:%02d:00Z", 1 + i % 28, i % 24, i % 60),
                ]
                items.append(
                    try JSONDecoder().decode(ImportItem.self, from: JSONSerialization.data(withJSONObject: item)))
            }
        }
        let sent = try await Uploader(transport: RoutesImportTransport(routes: routes))
            .upload(items, run: run, progress: .init())
        _ = try await routes.collected(run: run, source: "claude_code")
        var cards: [ProposalCard] = []
        for _ in 0..<600 {
            if try await routes.semantic(run: run).state != "pending" { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        cards = try await routes.proposals(run: run)
        for c in cards where c.kind != "unsorted" {
            _ = try await routes.patch(run: run, proposal: c.id, ProposalPatchBody(state: "accepted"))
        }
        try await conn.stepUp(reason: "it")
        let committed = try await routes.commit(run: run)
        print("IT seeded sent=\(sent) proposals=\(cards.map(\.name)) committed=\(committed.rooms.count)")

        // Exactly what the screens call, through the service: first with every room closed, then open (Touch ID).
        let rooms = try await service.rooms()
        print("IT rooms \(rooms.map { "\($0.name)=\($0.counts?.records ?? -1)" })")
        await probe("candidates, rooms closed (Inbox)") { try await service.candidates() }
        for r in rooms {
            await probe("policy \(r.name), closed (Inbox .task)") { try await service.policy(room: r.id) }
            await probe("latest \(r.name), closed (Items)") { try await service.latest(room: r.id) }
        }
        for r in rooms { _ = try await routes.openRoom(r.id) }
        await probe("candidates (Inbox)") { try await service.candidates() }
        for r in rooms {
            await probe("policy \(r.name) (Inbox .task)") { try await service.policy(room: r.id) }
            await probe("access \(r.name) (Room settings)") { try await service.roomAccess(room: r.id) }
            await probe("latest \(r.name) (Items)") { try await service.latest(room: r.id) }
            await probe("search \(r.name) (Items)") { try await service.search(room: r.id, query: "cache") }
        }
        await probe("runners (Sources)") { try await service.runners() }

        // The screens' own models: the Inbox loads, then its `.task` reads each room's policy. SwiftUI cancels that task when
        // the Inbox goes off screen (another tab) while it still runs; the cancelled call must leave no failure behind.
        await MainActor.run { () -> Task<Void, Never> in
            let model = BrainModel(host: LiveHost())
            model.use(service)
            return Task { @MainActor in
                await model.reload()
                guard let c = model.candidates else { return }
                await c.load()
                print("IT model inbox phase=\(c.phase) items=\(c.items.count) notice=\(c.notice ?? "-")")
                let inboxTask = Task { @MainActor in for r in model.rooms { await c.loadPolicy(r.id) } }
                inboxTask.cancel()
                await inboxTask.value
                print("IT model inbox after leaving the tab: notice=\(c.notice ?? "-")")
                if let sync = model.sync, let r = model.rooms.first {
                    print("IT model items \(r.name): \(await sync.latest(room: r.id))".prefix(300))
                }
            }
        }.value

        // Each route raw: status and the exact decode error, and the JSON for the decode tests.
        let out = env["BRAIN_IT_OUT"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        let first = try #require(rooms.first)
        let raw: [(String, String, any Decodable.Type)] = [
            ("rooms", "/rooms", [RoomViewWire].self),
            ("inbox", "/rooms/\(first.id)/inbox?status=candidate&limit=200", InboxPageWire.self),
            ("distils", "/rooms/\(first.id)/distils", [DistilWire].self),
            ("policy", "/rooms/\(first.id)/policy", PolicyWire.self),
            ("access", "/rooms/\(first.id)/access", RoomAccess.self),
            ("latest", "/rooms/\(first.id)/latest?limit=30", RoomLatest.self),
            ("search", "/rooms/\(first.id)/search?q=cache&limit=20", SearchWire.self),
            ("sources", "/sources", [SourceWire].self),
        ]
        for (name, path, type) in raw {
            let started = ContinuousClock.now
            do {
                let data = try await transport.send("GET", BrainRoutes.base + path, body: nil)
                let took = ContinuousClock.now - started
                if let out { try data.write(to: out.appendingPathComponent("\(name).json")) }
                do {
                    _ = try JSONDecoder().decode(type, from: data)
                    print("IT raw \(name) 200 decoded bytes=\(data.count) took=\(took)")
                } catch {
                    print("IT raw \(name) 200 DECODE \(BrainRoutes.describe(error))")
                }
            } catch {
                print("IT raw \(name) FAILED \(String(reflecting: error)) took=\(ContinuousClock.now - started)")
            }
        }
    }

    private func probe<T>(_ what: String, _ op: () async throws -> T) async {
        let started = ContinuousClock.now
        do {
            let v = try await op()
            let n = (v as? [Any])?.count ?? (v as? CandidateInbox).map { $0.items.count + $0.queued.count } ?? 1
            print("IT ok \(what) n=\(n) took=\(ContinuousClock.now - started)")
        } catch {
            print("IT FAIL \(what): \(String(reflecting: error)) -> \"\(BrainWords.failure(error))\"")
        }
    }
}
