import Admin
import CoreKit
import Foundation

/// Where a subscription sign-in has got to (KAN-441, plan `2026-11-05-claude-subscription-sign-in-plan`). Core holds
/// the state; this is the app's view of it. Never a token: the token goes from the runner straight into Core.
struct LoginItem: Equatable, Sendable {
    let id: String
    let provider: String
    let label: String
    let runner: String
    /// `starting | open_url | waiting_code | storing | done | failed | expired | cancelled`.
    let state: String
    let url: String?
    let reason: String?
    let accountID: Int64?
    /// A device code to type on the provider's page (E7-4); nil for a sign-in that has none.
    var code: String? = nil
}

/// The sign-in sheet's stages.
struct SignInFlow: Equatable {
    enum Stage: Equatable {
        case starting
        case open(URL)
        /// A guided sign-in (OpenCode, Antigravity): the runner's screen and a line to type. The page is optional.
        case guided(URL?)
        case working
        case done(account: Int64?)
        case failed(String)
    }
    var stage: Stage
    var login: String?
    var runner: String?
    var label: String
    var opened = false
    var codeError: String?
    /// The provider the sign-in is for, and the device code the Core gave it, if any.
    var provider = ""
    var deviceCode: String?
    /// A guided sign-in's redacted screen. In memory only: never saved, logged or kept once the sign-in ends.
    var screen: [String] = []
    /// What went wrong with the last typed line, in words. Never the line.
    var inputError: String?
    var sending = false
    /// Where the Core says the sign-in stands (`starting|open_url|enter_code|finishing|done|failed`) and its own line for
    /// it; nil from a Core that does not say, when the app infers the stage (`SignInStep.of`).
    var coreStage: String?
    var message: String?
    /// The CLI menu the person answered in this dialog: it is not offered again unless a different one appears.
    var pickedMenu: [MenuOption]?
}

extension AccountsModel {
    /// Starts a sign-in behind Touch ID, then follows it until it ends.
    func startSignIn(provider: String, label: String, displayName: String? = nil, runner: String? = nil) async {
        guard let service, mayWrite() else { return }
        signIn = SignInFlow(stage: .starting, label: label)
        pollBackoff = PollBackoff()
        signIn?.provider = provider
        do {
            let l = try await host.elevated(
                "Sign in to \(providerName(provider)) as \(label).", done: "started", keepsEdit: true
            ) {
                try await service.startLogin(provider: provider, label: label, displayName: displayName, runner: runner)
            }
            apply(l)
            await follow(l.id)
        } catch is AdminDeclined {
            signIn = nil
        } catch {
            signIn?.stage = .failed(Self.signInWords(error, provider: providerName(provider)))
        }
    }

    /// Hands the approval code to Core (which types it on the runner). It is a one-time code, never a token.
    func sendSignInCode(_ code: String) async {
        guard let service, let id = signIn?.login else { return }
        let c = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard c.count >= 8 else {
            signIn?.codeError = "That doesn't look like the whole code. Copy it again and paste it here."
            return
        }
        signIn?.codeError = nil
        signIn?.stage = .working
        do {
            // No Touch ID here: the one that started the sign-in covers it.
            apply(try await service.sendLoginCode(id, code: c))
        } catch {
            signIn?.stage = .failed(Self.signInWords(error, provider: "Claude"))
        }
    }

    /// Stops a sign-in that is still going (no Touch ID: stopping never changes anything).
    func cancelSignIn() async {
        let guidedAgy = signIn?.provider == "agy-sub" && !signInEnded
        if let id = signIn?.login, let service, !signInEnded { try? await service.cancelLogin(id) }
        signIn = nil
        // Antigravity may already have saved its login in the runner's keyring, which the Core cannot clear.
        if guidedAgy { host.shell.showToast(AccountNotes.keyringWords) }
    }

    /// Any way out of an Accounts dialog (Esc, the scrim, a button) stops a sign-in that is still going.
    func dialogClosed() {
        if signIn != nil { Task { await cancelSignIn() } }
    }

    var signInEnded: Bool {
        switch signIn?.stage {
        case .done?, .failed?, nil: true
        default: false
        }
    }

    func follow(_ id: String) async {
        // Cancellation ends it too: the sleep below swallows it, and the loop must not spin on.
        while let s = signIn, s.login == id, !signInEnded, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(signInTick * pollBackoff.seconds))
            guard let service, let l = try? await service.login(id) else { continue }
            apply(l)
            await pollScreen(id)
            // The device code and the plain stage are not in the generated client's answer: read them apart.
            if !signInEnded {
                let x = await service.loginExtra(id)
                guard signIn?.login == id else { continue }
                if let c = x.code { signIn?.deviceCode = c }
                signIn?.coreStage = x.stage
                signIn?.message = x.message
            }
        }
        if case .done = signIn?.stage { await reload() }
    }

    /// Reads the sign-in again now, because an `account.login.*` event said it changed.
    func refreshSignIn(_ id: String) async {
        guard let service, signIn?.login == id, let l = try? await service.login(id) else { return }
        apply(l)
        if case .done = signIn?.stage { await reload() }
    }

    func apply(_ l: LoginItem) {
        guard signIn != nil else { return }
        signIn?.login = l.id
        if let c = l.code { signIn?.deviceCode = c }
        signIn?.runner = l.runner
        switch l.state {
        case "open_url" where SignInStyle.of(l.provider, methods: providerMethods(l.provider)) == .guided:
            let u = l.url.flatMap(URL.init(string:))
            signIn?.stage = .guided(u)
            if let u, signIn?.opened == false {
                signIn?.opened = true
                opener(u)
            }
        case "open_url":
            if let u = l.url.flatMap(URL.init(string:)) {
                if case .open = signIn?.stage {} else { signIn?.stage = .open(u) }
                if signIn?.opened == false {
                    signIn?.opened = true
                    opener(u)
                }
            }
        case "waiting_code", "storing": signIn?.stage = .working
        case "done":
            signIn?.screen = []
            signIn?.stage = .done(account: l.accountID)
            if let a = l.accountID { boundSeen[a] = l.runner }
        case "failed", "cancelled", "expired":
            signIn?.screen = []
            signIn?.stage = .failed(Self.reasonWords(l.reason ?? l.state))
        default: signIn?.stage = .starting
        }
    }

    /// A refusal at start, in plain words with what to do.
    static func signInWords(_ error: any Error, provider: String) -> String {
        guard let e = CoreError.unwrapping(error) else { return error.localizedDescription }
        switch code(e) {
        case "no_runner":
            return
                "No runner can sign in yet. A runner needs the newest ainkrad-runner, with \(provider)'s own app installed."
        case "real_secret_refused":
            return
                "Your Core doesn't take real sign-ins yet. Turn on Real provider keys in Settings → Feature switches."
        case "secrets_disabled":
            return "Keys and secrets is Off. Set it to Test keys in Settings → Feature switches."
        case "conflict": return "An account with that name exists, or is signing in now. Pick another name."
        case "runner_failed": return "The runner did not answer. Check that it is online, then try again."
        case "limit_reached": return "Four sign-ins are already open. Finish or stop one, then try again."
        case "login_state": return "This sign-in has moved on. Start again."
        case "rate_limited": return "Too many tries just now. Wait a minute, then try again."
        default: return e.localizedDescription
        }
    }

    static func reasonWords(_ r: String) -> String {
        switch r {
        case "expired": "Nothing happened for 10 minutes, so the sign-in stopped. Start again when you're ready."
        case "cancelled": "The sign-in was stopped."
        default: r.prefix(1).uppercased() + r.dropFirst()
        }
    }
}
