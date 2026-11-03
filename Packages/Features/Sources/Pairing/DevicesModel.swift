import CoreKit
import Foundation
import Observation

enum LoadState: Equatable {
    case idle, loading, ready
    case failed(String)
}

/// Settings, Devices: who may reach this Core. Real data from the Core, live through its events.
@MainActor @Observable
final class DevicesModel {
    private(set) var items: [DeviceInfo] = []
    private(set) var load: LoadState = .idle
    /// A device whose dialog is open reports its failure here, so the dialog can say it in place.
    var dialogError: String?
    private(set) var busy = false
    private weak var host: AppModel?

    init(host: AppModel) { self.host = host }

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
            items = try await service.devices().sorted(by: Self.order)
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
            let updated = try await host.elevated("Rename \(d.name) to \(clean).") {
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
            let updated = try await host.elevated("Change what \(d.name) may do.") {
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
            let updated = try await host.elevated("Revoke \(d.name). It loses access at once.") {
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
    private(set) var load: LoadState = .idle
    private(set) var clearing: String?
    private weak var host: AppModel?

    init(host: AppModel) { self.host = host }

    func reload() async {
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
            try await host.elevated("Clear the lock on \(Self.describe(l.key)).") {
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
