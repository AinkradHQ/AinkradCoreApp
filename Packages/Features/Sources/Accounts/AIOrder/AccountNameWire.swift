import AinkradClient
import CoreKit
import Foundation

/// The first API minor whose Core keeps an account's free-text name (`display_name`, `PUT /accounts/{id}/name`).
let coreMinorNames: Int32 = 96

/// An account's free-text name: what a person calls it ("Work Claude"), beside the slug label the Core keys it by.
enum AccountNames {
    /// The most characters the Core keeps.
    static let max = 64

    /// The name as the Core stores it: trimmed; nil when blank (the provider's name shows instead).
    static func clean(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// Why the Core would refuse it, in words; nil when it is fine. Capitals, spaces and any script are fine.
    static func problem(_ s: String) -> String? {
        guard let t = clean(s) else { return nil }
        if t.count > max { return "Use at most \(max) characters." }
        if t.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            return "Use letters, numbers, spaces and punctuation only."
        }
        return nil
    }

    /// What an account is called: its own name, else its provider's.
    static func title(_ displayName: String?, provider: String) -> String {
        displayName.flatMap(clean) ?? provider
    }
}

extension AccountsModel {
    /// What an account is called everywhere it is named: the name its person gave it, else its provider's.
    /// Two unnamed accounts of one provider keep their label beside it, so they stay apart.
    func title(_ a: AccountItem) -> String {
        let p = ProviderCatalog.name(a.provider, fallback: providerName(a.provider))
        let twin =
            a.displayName == nil
            && accounts.contains { $0.id != a.id && $0.provider == a.provider && $0.displayName == nil }
        return AccountNames.title(a.displayName, provider: twin ? "\(p) · \(a.label)" : p)
    }

    /// Names the account (blank clears the name). True when the Core took it.
    func rename(_ a: AccountItem, to name: String) async -> Bool {
        let clean = AccountNames.clean(name)
        // Unchanged, or the provider's own name kept on an unnamed account: nothing to write.
        guard clean != a.displayName, !(a.displayName == nil && clean == title(a)) else { return true }
        let shown = clean ?? ProviderCatalog.name(a.provider, fallback: providerName(a.provider))
        return await write(
            "name-\(a.id)", reason: "Rename \(title(a)) to \(shown).", done: "Renamed to \(shown)", keepsEdit: true
        ) { _ = try await $0.setAccountName(account: a.id, name: clean) }
    }
}

extension AccountsService {
    func namesSupported() async -> Bool { false }
    func setAccountName(account: Int64, name: String?) async throws -> AccountItem {
        throw CoreError.invalidInput("Naming an account needs a newer Core.")
    }
    func startLogin(provider: String, label: String, displayName: String?, runner: String?) async throws -> LoginItem {
        try await startLogin(provider: provider, label: label, runner: runner)
    }
}

extension LiveAccountsService {
    /// Whatever the generated client threw, as the `CoreError` inside it.
    private static func wire(_ e: any Error) -> any Error {
        if let c = CoreFailure.of(e) { return c }
        return e
    }

    func namesSupported() async -> Bool { await connection.serverSupports(minor: coreMinorNames) }

    func setAccountName(account: Int64, name: String?) async throws -> AccountItem {
        do {
            return Self.account(
                try await connection.client.setAccountName(
                    path: .init(id: String(account)), body: .json(.init(displayName: name))
                ).ok.body.json)
        } catch { throw Self.wire(error) }
    }

    func startLogin(provider: String, label: String, displayName: String?, runner: String?) async throws -> LoginItem {
        do {
            return Self.login(
                try await connection.client.startAccountLogin(
                    body: .json(.init(displayName: displayName, label: label, provider: provider, runner: runner))
                ).ok.body.json)
        } catch { throw Self.wire(error) }
    }
}
