import CoreKit
import Foundation

/// The guided sign-in on the model (E7-5, E7-5b): read the runner's redacted screen while the sign-in waits, type one line,
/// and know which runner each bound account is pinned to. The screen and the typed line live in memory only.
extension AccountsModel {
    func providerMethods(_ id: String) -> [String] { providers.first { $0.id == id }?.loginMethods ?? [] }

    var signInStyle: SignInStyle {
        let id = signIn?.provider ?? ""
        return SignInStyle.of(id, methods: providerMethods(id))
    }

    /// True while the sign-in is one the person should keep reading the screen of.
    var guidedOpen: Bool {
        if case .guided? = signIn?.stage { return true }
        return false
    }

    /// One look at the screen. Stops by itself with the sign-in: an ended or replaced sign-in is not read again, and a
    /// `login_state` answer means the sign-in moved on, so the login poll takes over.
    func pollScreen(_ id: String) async {
        guard guidedOpen, signIn?.login == id, let service else { return }
        do {
            let s = try await service.loginScreen(id)
            guard guidedOpen, signIn?.login == id else { return }
            let changed = s.lines != signIn?.screen
            signIn?.screen = s.lines
            if let c = s.code { signIn?.deviceCode = c }
            if signIn?.opened == false, let u = s.url.flatMap(URL.init(string:)) {
                signIn?.opened = true
                signIn?.stage = .guided(u)
                opener(u)
            }
            pollBackoff.note(changed: changed)
        } catch {
            pollBackoff.note(changed: false)
        }
    }

    /// Types one line into the runner's sign-in. The line is checked, sent once and dropped: it is never kept, never put on
    /// the screen here, and the error words never repeat it.
    @discardableResult
    func sendGuidedInput(_ raw: String) async -> Bool {
        guard let service, let id = signIn?.login, guidedOpen, signIn?.sending != true else { return false }
        guard case .send(let line) = GuidedInput.check(raw) else {
            signIn?.inputError = GuidedInput.words(GuidedInput.check(raw))
            return false
        }
        signIn?.inputError = nil
        signIn?.sending = true
        defer { signIn?.sending = false }
        do {
            try await service.sendLoginInput(id, line: line)
            pollBackoff.reset()
            await pollScreen(id)
            return true
        } catch {
            signIn?.inputError = Self.signInWords(error, provider: "the sign-in")
            return false
        }
    }

    /// The runner each bound account is pinned to: what the Core says, else where the app saw the sign-in finish.
    func reloadBindings(_ service: any AccountsService) async {
        let said = await service.boundRunners()
        let names = Dictionary(
            ((try? await service.runners()) ?? []).map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        accounts = accounts.map { a in
            var n = a
            let bound = SignInStyle.of(a.provider, methods: providerMethods(a.provider)).runnerBound
            let runner = said[a.id] ?? boundSeen[a.id]
            n.runnerBinding = (bound || runner != nil) ? RunnerBinding(name: runner.flatMap { names[$0] }) : nil
            return n
        }
    }
}
