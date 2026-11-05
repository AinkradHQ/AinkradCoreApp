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
    /// `starting | open_url | waiting_code | storing | done | failed | cancelled`.
    let state: String
    let url: String?
    let reason: String?
    let accountID: Int64?
}

/// The sign-in sheet's stages.
struct SignInFlow: Equatable {
    enum Stage: Equatable {
        case starting
        case open(URL)
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
}

extension AccountsModel {
    /// Starts a sign-in behind Touch ID, then follows it until it ends.
    func startSignIn(provider: String, label: String) async {
        guard let service, mayWrite() else { return }
        signIn = SignInFlow(stage: .starting, label: label)
        do {
            let l = try await host.elevated(
                "Sign in to \(providerName(provider)) as \(label).", done: "started", keepsEdit: true
            ) { try await service.startLogin(provider: provider, label: label, runner: nil) }
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
            let l = try await host.elevated("Connect your Claude plan.", done: "sent", keepsEdit: true) {
                try await service.sendLoginCode(id, code: c)
            }
            apply(l)
        } catch is AdminDeclined {
            if let url = signIn.flatMap({ f -> URL? in if case .open(let u) = f.stage { u } else { nil } }) {
                signIn?.stage = .open(url)
            }
        } catch {
            signIn?.stage = .failed(Self.signInWords(error, provider: "Claude"))
        }
    }

    /// Stops a sign-in that is still going (no Touch ID: stopping never changes anything).
    func cancelSignIn() async {
        if let id = signIn?.login, let service, !signInEnded { try? await service.cancelLogin(id) }
        signIn = nil
    }

    var signInEnded: Bool {
        switch signIn?.stage {
        case .done?, .failed?, nil: true
        default: false
        }
    }

    private func follow(_ id: String) async {
        while let s = signIn, s.login == id, !signInEnded {
            try? await Task.sleep(for: .seconds(1))
            guard let service, let l = try? await service.login(id) else { continue }
            apply(l)
        }
        if case .done = signIn?.stage { await reload() }
    }

    private func apply(_ l: LoginItem) {
        guard signIn != nil else { return }
        signIn?.login = l.id
        signIn?.runner = l.runner
        switch l.state {
        case "open_url":
            if let u = l.url.flatMap(URL.init(string:)) {
                if case .open = signIn?.stage {} else { signIn?.stage = .open(u) }
                if signIn?.opened == false {
                    signIn?.opened = true
                    opener(u)
                }
            }
        case "waiting_code", "storing": signIn?.stage = .working
        case "done": signIn?.stage = .done(account: l.accountID)
        case "failed", "cancelled": signIn?.stage = .failed(Self.reasonWords(l.reason ?? l.state))
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
        case "conflict": return "An account with that name exists. Pick another name."
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
