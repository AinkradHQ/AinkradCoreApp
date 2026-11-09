import CoreKit
import Foundation
import Observation

struct FieldIssue: Equatable {
    let code: String
    let message: String
}

enum HistoryLoad: Equatable {
    case loading
    case ready([SettingChangeItem])
    case failed(String)
}

/// Settings, Core settings and Feature switches: one registry from the Core (`GET /api/v1/settings`), shown as limits with
/// history and as the few switches that gate features. Writes go through Touch ID and say what changed, with Undo.
@MainActor @Observable
final class RegistryModel {
    /// Settings that gate a feature, in the order the screen shows them.
    nonisolated static let switchKeys = [
        "secrets.mode", "secrets.provider_accounts", "secrets.connections", "auth.passkey_admin",
    ]

    private(set) var items: [SettingItem] = []
    var state: SectionState = .loading
    var editing: String?
    var draft = ""
    private(set) var issue: FieldIssue?
    /// A refusal from the Core for the row or switch being written, in words.
    private(set) var writeError: [String: String] = [:]
    private(set) var busy: String?
    var openHistory: String?
    /// The row the keyboard is on in Core settings.
    var cursor: String?
    private(set) var history: [String: HistoryLoad] = [:]
    private(set) var runners: [RunnerChoice] = []
    @ObservationIgnored private weak var hub: AdminModel?

    init(hub: AdminModel) { self.hub = hub }

    var switches: [SettingItem] { Self.switchKeys.compactMap { k in items.first { $0.key == k } } }
    var limits: [SettingItem] { items.filter { !Self.switchKeys.contains($0.key) } }
    /// Core settings by their first word, in the Core's order.
    var groups: [(name: String, items: [SettingItem])] {
        var order: [String] = []
        var by: [String: [SettingItem]] = [:]
        for s in limits {
            if by[s.group] == nil { order.append(s.group) }
            by[s.group, default: []].append(s)
        }
        return order.map { ($0, by[$0] ?? []) }
    }
    func item(_ key: String) -> SettingItem? { items.first { $0.key == key } }
    /// Why the connection-tokens switch can't be touched yet, in words; nil when it can.
    nonisolated static func connectionsNeeds(mode: Int) -> String? {
        mode < 1 ? "Set Keys and secrets to Test keys first." : nil
    }
    var secretsMode: Int { Int(item("secrets.mode")?.value ?? 0) }

    func reset() {
        items = []
        state = .loading
        editing = nil
        openHistory = nil
        history = [:]
        runners = []
    }

    /// Back to a closed row: no edit, no history (the demo and a section change start here).
    func clearUI() {
        editing = nil
        issue = nil
        openHistory = nil
        history = [:]
        writeError = [:]
    }

    func reload() async {
        guard let hub, let service = hub.service else { return }
        if items.isEmpty { state = .loading }
        do {
            items = try await service.settings()
            state = items.isEmpty ? .empty : .ready
        } catch { state = hub.state(for: error) }
        runners = (try? await service.runners()) ?? runners
    }

    // MARK: editing

    func beginEdit(_ s: SettingItem) {
        cursor = s.key
        editing = s.key
        draft = String(s.value)
        issue = nil
        hub?.host.clearElevationNotice()
    }

    func cancelEdit() {
        editing = nil
        issue = nil
        hub?.host.clearElevationNotice()
    }

    /// The Core refuses a value outside the limits and never clamps it; so does this screen, before asking.
    static func check(_ s: SettingItem, _ raw: String) -> FieldIssue? {
        let t = raw.trimmingCharacters(in: .whitespaces)
        guard let n = Int64(t) else {
            return FieldIssue(code: "not_integer", message: "\(t.isEmpty ? "Nothing" : t) is not a whole number.")
        }
        if n < s.min {
            return FieldIssue(
                code: "out_of_bounds",
                message:
                    "\(SettingWords.value(s, n)) is below the lowest allowed, \(SettingWords.value(s, s.min)). Nothing was saved."
            )
        }
        if n > s.max {
            return FieldIssue(
                code: "out_of_bounds",
                message:
                    "\(SettingWords.value(s, n)) is above the highest allowed, \(SettingWords.value(s, s.max)). Nothing was saved."
            )
        }
        return nil
    }

    /// The draft as the rail shows it while typing: nil when it is not a number.
    func draftValue() -> Int64? { Int64(draft.trimmingCharacters(in: .whitespaces)) }

    func saveEdit(_ s: SettingItem) async {
        if let found = Self.check(s, draft) {
            issue = found
            return
        }
        guard let n = draftValue() else { return }
        if await set(
            s, to: n,
            reason: "Change \(SettingWords.title(s)) to \(SettingWords.value(s, n)).",
            keepsEdit: true)
        {
            editing = nil
            issue = nil
        }
    }

    /// Sets one value (an edit or a switch). True when the Core took it.
    @discardableResult
    func set(_ s: SettingItem, to n: Int64, reason: String, keepsEdit: Bool = false) async -> Bool {
        guard let hub, let service = hub.service, hub.mayWrite() else { return false }
        busy = s.key
        writeError[s.key] = nil
        defer { busy = nil }
        do {
            let updated = try await hub.host.elevated(reason, done: "changed", keepsEdit: keepsEdit) {
                try await service.setSetting(s.key, n)
            }
            replace(updated)
            await refreshHistory(s.key)
            hub.host.shell.showToast("\(SettingWords.title(s)): \(SettingWords.value(s, n))") {
                [weak self] in
                Task { @MainActor in
                    if s.isOverride {
                        await self?.set(
                            updated, to: s.value,
                            reason: "Put \(SettingWords.title(s)) back to \(SettingWords.value(s, s.value)).")
                    } else {
                        await self?.reset(
                            updated,
                            reason:
                                "Put \(SettingWords.title(s)) back to its default, \(SettingWords.value(s, s.defaultValue))."
                        )
                    }
                }
            }
            return true
        } catch is AdminDeclined {
            return false
        } catch {
            if let c = hub.code(error), c == "out_of_bounds" || c == "not_integer" || c == "bad_request" {
                issue = FieldIssue(code: c, message: hub.words(error))
            } else {
                writeError[s.key] = hub.words(error)
            }
            return false
        }
    }

    func reset(_ s: SettingItem, reason: String? = nil) async {
        guard let hub, let service = hub.service, hub.mayWrite() else { return }
        busy = s.key
        writeError[s.key] = nil
        defer { busy = nil }
        do {
            let updated = try await hub.host.elevated(
                reason ?? "Put \(SettingWords.title(s)) back to its default, \(SettingWords.value(s, s.defaultValue)).",
                done: "reset", keepsEdit: false
            ) { try await service.resetSetting(s.key) }
            replace(updated)
            await refreshHistory(s.key)
            hub.host.shell.showToast("\(SettingWords.title(s)) is back to \(SettingWords.value(s, s.defaultValue))") {
                [weak self] in
                Task { @MainActor in
                    await self?.set(
                        updated, to: s.value,
                        reason: "Put \(SettingWords.title(s)) back to \(SettingWords.value(s, s.value)).")
                }
            }
        } catch is AdminDeclined {
        } catch { writeError[s.key] = hub.words(error) }
    }

    private func replace(_ s: SettingItem) {
        if let i = items.firstIndex(where: { $0.key == s.key }) { items[i] = s } else { items.append(s) }
    }

    // MARK: history

    func toggleHistory(_ key: String) async {
        if openHistory == key {
            openHistory = nil
            return
        }
        openHistory = key
        cursor = key
        await refreshHistory(key, showLoading: true)
    }

    private func refreshHistory(_ key: String, showLoading: Bool = false) async {
        guard let hub, let service = hub.service else { return }
        if openHistory != key && history[key] == nil { return }
        if showLoading { history[key] = .loading }
        do { history[key] = .ready(try await service.history(key).sorted { $0.seq > $1.seq }) } catch {
            history[key] = .failed(hub.words(error))
        }
    }
}
