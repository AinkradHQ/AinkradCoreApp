import CoreKit
import Foundation
import Observation

enum LoadState: Equatable {
    case idle, loading, ready
    case failed(String)
}

enum DeviceFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case devices = "Devices"
    case runners = "Runners"
    case passkeys = "Passkeys"
    var id: String { rawValue }
    /// By the Core's `kind` word. A kind this app does not know shows only under All, as its own word.
    func matches(_ kind: String) -> Bool {
        switch self {
        case .all: true
        case .devices: kind == "device"
        case .runners: kind == "runner"
        case .passkeys: kind == "passkey"
        }
    }
}

/// Settings, Devices: who may reach this Core. Real data from the Core, live through its events.
@MainActor @Observable
final class DevicesModel {
    private(set) var items: [DeviceInfo] = []
    private(set) var load: LoadState = .idle
    /// A device whose dialog is open reports its failure here, so the dialog can say it in place.
    var dialogError: String?
    private(set) var busy = false
    var filter: DeviceFilter = .all
    /// The device whose page is open (nil: the list).
    var detailID: String? { didSet { renaming = false } }
    /// The name field on the device page is open (rename is inline, as in the prototype).
    var renaming = false
    private weak var host: AppModel?

    init(host: AppModel) { self.host = host }

    var shown: [DeviceInfo] { items.filter { filter.matches($0.kind) } }
    var detail: DeviceInfo? { detailID.flatMap { id in items.first { $0.id == id } } }

    /// The one active device that can manage the Core, when there is exactly one: losing it means SSH to the host.
    var onlyAdmin: DeviceInfo? {
        let admins = active.filter { $0.scopes.contains("admin") && $0.stepup != false }
        return admins.count == 1 ? admins[0] : nil
    }

    var myID: String? { host?.service?.deviceID }
    var active: [DeviceInfo] { items.filter { !$0.revoked } }
    var revoked: [DeviceInfo] { items.filter(\.revoked) }
    func isMe(_ d: DeviceInfo) -> Bool { d.id == myID }

    func reload() async {
        guard let service = host?.service else {
            load = .idle
            return
        }
        if items.isEmpty { load = .loading }
        do {
            // A pending device is a pairing still waiting for approval: the bell and Add device handle it, not this list.
            items = try await service.devices().filter { $0.status != "pending" }.sorted(by: Self.order)
            load = .ready
        } catch { load = .failed(CoreError.unwrapping(error)?.localizedDescription ?? error.localizedDescription) }
    }

    /// Newest activity first.
    private static func order(_ a: DeviceInfo, _ b: DeviceInfo) -> Bool {
        (a.lastUsed ?? a.createdAt) > (b.lastUsed ?? b.createdAt)
    }

    /// Renames, with Undo to the old name. False when it did not happen (the reason is in `dialogError`).
    func rename(_ d: DeviceInfo, to name: String) async -> Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let host, let service = host.service else { return false }
        guard !clean.isEmpty, clean.count <= 64 else {
            dialogError = "A name is 1 to 64 characters."
            return false
        }
        return await run {
            let updated = try await host.elevated("Rename \(d.name) to \(clean).", done: "renamed") {
                try await service.rename(d.id, to: clean)
            }
            self.replace(updated)
            host.shell.showToast("Renamed to \(clean)") { [weak self] in
                Task { @MainActor in _ = await self?.rename(updated, to: d.name) }
            }
        }
    }

    /// Narrows what a device may do, with Undo to what it held.
    func setScopes(_ d: DeviceInfo, _ scopes: [String]) async -> Bool {
        guard let host, let service = host.service else { return false }
        guard !scopes.isEmpty else {
            dialogError = "A device needs at least one scope. Revoke it to remove all access."
            return false
        }
        return await run {
            let updated = try await host.elevated("Change what \(d.name) may do.", done: "changed") {
                try await service.setScopes(d.id, scopes)
            }
            self.replace(updated)
            host.shell.showToast("\(d.name) may now: \(updated.scopes.joined(separator: ", "))") { [weak self] in
                Task { @MainActor in _ = await self?.setScopes(updated, d.scopes) }
            }
        }
    }

    /// Revokes at once. Not undoable: the Core keeps the row, marked revoked, and the device must pair again.
    func revoke(_ d: DeviceInfo) async -> Bool {
        guard let host, let service = host.service else { return false }
        let me = isMe(d)
        return await run {
            let updated = try await host.elevated("Revoke \(d.name). It loses access at once.", done: "revoked") {
                try await service.revoke(d.id)
            }
            self.replace(updated)
            if me {
                await host.forgetCore()
            } else {
                host.shell.showToast("\(d.name) was revoked")
            }
        }
    }

    private func replace(_ d: DeviceInfo) {
        if let i = items.firstIndex(where: { $0.id == d.id }) { items[i] = d } else { items.append(d) }
        items.sort(by: Self.order)
    }

    private func run(_ work: () async throws -> Void) async -> Bool {
        dialogError = nil
        busy = true
        defer { busy = false }
        do {
            try await work()
            return true
        } catch is StepUpDeclined {
            return false
        } catch {
            dialogError = CoreError.unwrapping(error)?.localizedDescription ?? error.localizedDescription
            return false
        }
    }
}

/// Settings, Security, Lockouts: keys the Core has locked for failed attempts.
@MainActor @Observable
final class LockoutsModel {
    private(set) var items: [LockoutInfo] = []
    private var sampled = false
    #if DEBUG
    /// Snapshots only: two locks with time left, when the throwaway Core did not lock anything.
    func debugSample() {
        sampled = true
        items = [
            LockoutInfo(key: "ip:203.0.113.77", lockedUntil: Date().addingTimeInterval(252), strikes: 2),
            LockoutInfo(key: "ipdev:198.51.100.4:dev_9c41", lockedUntil: Date().addingTimeInterval(41), strikes: 1),
        ]
        load = .ready
    }
    #endif
    private(set) var load: LoadState = .idle
    private(set) var clearing: String?
    private weak var host: AppModel?

    init(host: AppModel) { self.host = host }

    func reload() async {
        guard !sampled else { return }
        guard let service = host?.service else {
            load = .idle
            return
        }
        if items.isEmpty { load = .loading }
        do {
            items = try await service.lockouts().filter { $0.lockedUntil > Date() }
            load = .ready
        } catch { load = .failed(CoreError.unwrapping(error)?.localizedDescription ?? error.localizedDescription) }
    }

    func clear(_ l: LockoutInfo) async {
        guard let host, let service = host.service else { return }
        clearing = l.key
        defer { clearing = nil }
        do {
            try await host.elevated("Clear the lock on \(Self.describe(l.key)).", done: "cleared", keepsEdit: false) {
                try await service.clearLockout(l.key)
            }
            items.removeAll { $0.key == l.key }
            host.shell.showToast("Cleared the lock on \(Self.describe(l.key))")
        } catch { host.say(error) }
    }

    /// `ip:<address>`, `ipdev:<address>:<device>`, `stepup:<device>` in words.
    static func describe(_ key: String) -> String {
        let parts = key.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        switch (parts.first, parts.count) {
        case ("ipdev", 3): return "address \(parts[1]) with device \(parts[2])"
        case ("ip", 2...): return "address \(parts.dropFirst().joined(separator: ":"))"
        case ("stepup", 2...): return "Touch ID for device \(parts.dropFirst().joined(separator: ":"))"
        default: return key
        }
    }

    static func strikes(_ n: Int) -> String {
        switch n {
        case ...1: "First strike. The next lock is twice as long."
        case 2: "Second strike. The next lock is twice as long."
        default: "Strike \(n). Each lock doubles the one before."
        }
    }
}
