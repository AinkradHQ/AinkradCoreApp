import Admin
import AppKit
import CoreKit
import Foundation
import Observation

/// Adding an account key, or replacing one, inside the app (admin + step-up). The key lives only in `key`: it is sent to
/// the Core once, then cleared, and it is never logged, stored or shown back. Held as `@State` by the dialog.
@MainActor @Observable
final class KeyEntryFlow {
    enum Stage: Equatable {
        case form
        case working(String)
        case done(account: Int64, latencyMs: Int64, note: String)
        /// `account` is set when the key reached the Core but did not pass its test: it can be removed or replaced.
        case failed(String, account: Int64?)
    }

    var key = ""
    var label = "work"
    var runner: String?
    var stage = Stage.form
    var gate: GateState?
    var runners: [AccountRunner] = []
    var enabling = false
    var gateNote: String?
    /// The account a key goes to: the one being rotated, or the one just made whose test failed.
    var target: AccountItem?

    init(target: AccountItem? = nil) { self.target = target }

    /// Keys are refused until `secrets.mode` and `secrets.provider_accounts` are both on.
    var needsGate: Bool { gate.map { $0.mode == 0 || $0.providerAccounts == 0 } ?? false }
    /// What the Core takes as a name: `[a-z][a-z0-9._-]{0,63}`. A typed name is lowercased, spaces become dashes and
    /// anything else outside the set is dropped.
    static func slug(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: " ", with: "-")
        let ok = Set("abcdefghijklmnopqrstuvwxyz0123456789._-")
        return String(t.filter { ok.contains($0) })
    }
    var slugged: String { Self.slug(label) }
    var labelOK: Bool {
        let t = slugged
        return t.count <= 64 && t.first.map { "a"..."z" ~= $0 } == true
    }
    func ready(rotating: Bool) -> Bool {
        !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !needsGate
            && (rotating || (labelOK && runner != nil))
    }

    func wipe() { key = "" }

    func paste() {
        if let s = NSPasteboard.general.string(forType: .string) {
            key = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Reads the switches and the runners when the dialog opens.
    func load(_ m: AccountsModel) async {
        guard let svc = m.service else { return }
        gate = try? await svc.gate()
        runners = (try? await svc.runners()) ?? []
        if runner == nil, target == nil { runner = runners.first { $0.online }?.id }
    }

    /// One Touch ID: Keys and secrets to Test keys (if it was Off), then Real provider keys on.
    func enableKeys(_ m: AccountsModel) async {
        guard let svc = m.service, m.mayWrite() else { return }
        enabling = true
        gateNote = nil
        defer { enabling = false }
        let mode = gate?.mode ?? 0
        do {
            try await m.host.elevated("Turn on keys for accounts in your Core.", done: "changed", keepsEdit: true) {
                if mode == 0 { try await svc.setSecretsSwitch("secrets.mode", 1) }
                try await svc.setSecretsSwitch("secrets.provider_accounts", 1)
            }
            gate = GateState(mode: max(mode, 1), providerAccounts: 1)
            await m.reload()
        } catch is AdminDeclined {
        } catch {
            gateNote = Self.keyWords(error)
        }
    }

    /// Sends the key (a new account, or a replacement), then tests it.
    func connect(_ m: AccountsModel, provider: String) async {
        guard let svc = m.service, m.mayWrite(), ready(rotating: target != nil) else { return }
        let name = m.providerName(provider)
        let who = target?.label ?? slugged
        stage = .working("Saving the key…")
        let id: Int64
        do {
            let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if let target {
                id = target.id
                let reason = "Use a new key for \(who). It is stored in your Core."
                try await m.host.elevated(reason, done: "changed", keepsEdit: true) {
                    try await svc.replaceSecret(account: id, key: value, runners: nil)
                }
            } else {
                let rs = runner.map { [$0] } ?? []
                let reason = "Add \(who) to \(name). Its key is stored in your Core."
                let made = try await m.host.elevated(reason, done: "changed", keepsEdit: true) {
                    try await svc.createAccount(provider: provider, label: who, key: value, runners: rs)
                }
                id = made.id
                target = made
            }
        } catch is AdminDeclined {
            stage = .form
            return
        } catch {
            stage = .failed(Self.keyWords(error), account: nil)
            return
        }
        wipe()
        await m.reload()
        stage = .working("Checking the key…")
        do {
            let t = try await svc.test(account: id)
            await m.reload()
            if let ok = Self.passNote(t.result) {
                stage = .done(account: id, latencyMs: t.latencyMs, note: ok)
            } else {
                let w = TestWords.of(t.result)
                stage = .failed("\(w.title). \(w.line)", account: id)
            }
        } catch {
            stage = .failed(Self.testWords(error), account: id)
        }
    }

    /// Removes the account whose key failed its test.
    func remove(_ m: AccountsModel) async {
        guard let t = target else { return }
        if await m.delete(t) {
            target = nil
            stage = .form
        }
    }

    /// Back to the form to try another key on the same account.
    func tryAnother() {
        wipe()
        stage = .form
    }

    static func passNote(_ r: String) -> String? {
        switch r {
        case "ok": "The provider took the key."
        case "rate_limited": "The key is fine; the provider asked to slow down."
        case "inconclusive": "This provider has no way to test a key, so it was saved without one."
        default: nil
        }
    }

    static func testWords(_ error: any Error) -> String {
        switch CoreError.unwrapping(error).map(AccountsModel.code) {
        case "no_runner": "The key is saved. \(AccountsModel.noRunnerWords)"
        case "runner_failed": "The key is saved, but the runner didn't answer the check."
        case "rate_limited": "The key is saved. It was checked a moment ago; test it again in a minute."
        default: "The key is saved, but the check failed. \(keyWords(error))"
        }
    }

    static let labelRule = "Names use lowercase letters, digits, dot, dash and underscore, and start with a letter."

    /// A refusal at add or replace time, in plain words with what to do.
    static func keyWords(_ error: any Error) -> String {
        guard let e = CoreError.unwrapping(error) else { return error.localizedDescription }
        switch AccountsModel.code(e) {
        case "secrets_disabled": return "Keys are turned off on your Core. Turn them on above, then try again."
        case "real_secret_refused":
            return "Your Core doesn't take real keys yet. Turn them on above, then try again."
        case "login_required": return "This provider signs in with your plan, not a key. Use its sign-in instead."
        case "conflict": return "You already have an account with that name. Pick another name."
        case "limit_reached": return "Your Core has as many accounts as it allows. Remove one, then try again."
        case "secrets_unavailable": return "Your Core can't store keys right now. Try again in a moment."
        case "forbidden_scope": return "This device can't add keys. It needs admin access."
        case "rate_limited": return "Too many tries just now. Wait a minute, then try again."
        case "no_runner": return AccountsModel.noRunnerWords
        case "credential_rejected": return AccountsModel.credentialWords
        case "bad_request":
            if e.localizedDescription.contains("label") { return labelRule }
            return "Your Core didn't accept that. Check the name and the key, then try again."
        default:
            if case .http(400, _, _) = e {
                return "Your Core didn't accept that. Check the name and the key, then try again."
            }
            return e.localizedDescription
        }
    }
}
