import AppKit
import Foundation
import Observation

/// Add account, as one flow: pick a provider, paste its key or sign in, done. The key goes through `KeyEntryFlow` (the same
/// gate, runner, Touch ID and key test as before); a sign-in through the model's `startSignIn`. Nothing here keeps a key
/// beyond `keyFlow.key`, which is wiped once the Core has it.
@MainActor @Observable
final class AddAccountFlow {
    var stepper = AddStepper()
    var providerID: String?
    private(set) var keyFlow = KeyEntryFlow()
    /// The line under the key field when the Core refused it or could not check it.
    var error: String?
    var addedAccount: Int64?
    var modelsFound: Int?
    /// The models were counted: the third line of the check is done.
    var modelsSettled = false

    var key: String {
        get { keyFlow.key }
        set { keyFlow.key = newValue }
    }

    func provider(_ m: AccountsModel) -> ProviderItem? { providerID.flatMap { m.provider($0) } }
    func name(_ m: AccountsModel) -> String {
        providerID.map { ProviderCatalog.name($0, fallback: m.providerName($0)) } ?? "your account"
    }

    /// The check's progress, 0...3: reached the provider, the key works, found its models, all done.
    var progress: Int {
        guard stepper.step == .checking else { return 0 }
        switch keyFlow.stage {
        case .working(let w): return w.hasPrefix("Checking") ? 1 : 0
        case .done: return modelsSettled ? 3 : 2
        default: return 0
        }
    }

    // MARK: pick

    func choose(_ p: ProviderItem, _ m: AccountsModel) async {
        providerID = p.id
        error = nil
        let label = ProviderCatalog.label(
            for: ProviderCatalog.name(p.id, fallback: p.name), taken: Set(m.accounts.map(\.label)))
        stepper.choose(ProviderCatalog.kind(p))
        keyFlow.label = label
        if ProviderCatalog.kind(p) == .subscription {
            await m.startSignIn(provider: p.id, label: label)
        } else {
            await keyFlow.load(m)
        }
    }

    func back(_ m: AccountsModel) {
        if stepper.step == .signIn { Task { await m.cancelSignIn() } }
        keyFlow.wipe()
        error = nil
        stepper.back()
    }

    func again(_ m: AccountsModel) {
        m.signIn = nil
        keyFlow = KeyEntryFlow()
        providerID = nil
        addedAccount = nil
        modelsFound = nil
        error = nil
        stepper.again()
    }

    // MARK: key

    func live(_ m: AccountsModel) -> KeyShape.Live { KeyShape.live(key, prefix: provider(m)?.keyPrefix) }

    func submitKey(_ m: AccountsModel, settle: Bool) async {
        guard let id = providerID, stepper.step == .key else { return }
        error = nil
        if keyFlow.needsGate { await keyFlow.enableKeys(m) }
        if keyFlow.needsGate {
            error = keyFlow.gateNote ?? "Keys are turned off on your Core. Turn them on in Settings, then try again."
            return
        }
        if keyFlow.runner == nil {
            error = AccountsModel.noRunnerWords
            return
        }
        stepper.submitKey()
        modelsSettled = false
        await keyFlow.connect(m, provider: id)
        switch keyFlow.stage {
        case .done(let account, _, _):
            addedAccount = account
            let counted = await m.service?.modelCount(account: account)
            modelsFound = counted ?? provider(m).map(\.models.count).flatMap { $0 > 0 ? $0 : nil }
            modelsSettled = true
            if settle { try? await Task.sleep(for: .milliseconds(650)) }
            stepper.checked(ok: true)
        case .failed(let why, _):
            error = why
            keyFlow.tryAnother()
            stepper.checked(ok: false)
        default:
            // Touch ID was declined: back to the field with the key still in it.
            stepper.checked(ok: false)
        }
    }

    // MARK: sign-in

    func signedIn(_ account: Int64?) {
        addedAccount = account
        stepper.signedIn()
    }

    func retrySignIn(_ m: AccountsModel) async {
        guard let id = providerID, let p = m.provider(id) else { return }
        m.signIn = nil
        await choose(p, m)
    }

    /// "It is number N in your AI order."
    func number(_ m: AccountsModel) -> Int {
        let rows = m.orderRows
        return addedAccount.flatMap { id in rows.firstIndex { $0.id == id } }.map { $0 + 1 } ?? rows.count
    }

    func copy(_ code: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
    }
}
