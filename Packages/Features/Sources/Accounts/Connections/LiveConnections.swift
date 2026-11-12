import AinkradClient
import CoreKit
import Foundation
import OpenAPIRuntime

/// The Core's connection routes for the Connections screens. A credential only ever goes in (`addToken`, once) and is never
/// read back or logged: no request body is kept anywhere here. Step-up (Touch ID) is the model's job, around each write.
struct LiveConnectionsService: ConnectionsService {
    let client: Client

    init(client: Client) { self.client = client }
    init(connection: CoreConnection) { client = connection.client }

    // MARK: reading

    func kinds() async throws -> [ConnKind] {
        try await run { try await client.listConnectionKinds().ok.body.json.map(Self.kind) }
    }

    func connections() async throws -> [ConnItem] {
        try await run {
            let list = try await client.listConnections().ok.body.json
            let kinds = try await client.listConnectionKinds().ok.body.json
            let titles = Dictionary(kinds.map { ($0.kind, $0.title) }, uniquingKeysWith: { a, _ in a })
            var out: [ConnItem] = []
            // ponytail: one grants call per connection; a batch route would do it in one if lists get long.
            for c in list { out.append(Self.item(c, service: titles[c.kind], grants: await grants(of: c))) }
            return out
        }
    }

    /// Admin only; nil for anyone else, who then sees `my_capabilities`.
    private func grants(of c: Components.Schemas.Connection) async -> [Components.Schemas.ConnectionGrant]? {
        guard c.grantCount != nil else { return nil }
        return try? await client.listConnectionGrants(path: .init(id: String(c.id))).ok.body.json
    }

    func activity(connection: Int64?) async throws -> [ConnActivity] {
        try await run {
            let ids: [Int64]
            if let connection {
                ids = [connection]
            } else {
                ids = try await client.listConnections().ok.body.json.map(\.id)
            }
            var rows: [ConnActivity] = []
            for id in ids {
                // Activity is admin only: a connection that refuses just has no rows here.
                guard let uses = try? await client.listConnectionActivity(path: .init(id: String(id))).ok.body.json
                else { continue }
                rows += uses.map { Self.use($0, connection: id) }
            }
            return rows.sorted { $0.at > $1.at }
        }
    }

    /// The Core has no route that lists a service's repositories or projects, so the picker shows the ones already chosen.
    func resources(_ id: Int64) async throws -> [String] {
        try await run {
            let all = try await client.listConnectionGrants(path: .init(id: String(id))).ok.body.json
            return Self.item(Self.stub, service: nil, grants: all).only ?? []
        }
    }

    // MARK: signing in

    func start(kind: String, again: Int64?) async throws -> ConnFlow {
        try await run {
            let f = try await client.startConnectionFlow(body: .json(.init(connection: again, kind: kind))).ok.body.json
            return try await flow(f)
        }
    }

    func flow(_ id: String) async throws -> ConnFlow {
        try await run { try await flow(try await client.getConnectionFlow(path: .init(id: id)).ok.body.json) }
    }

    /// GitHub: skipping the repository step just finishes (the sign-in already made the connection). Jira: the site.
    func choose(_ id: String, site: String?) async throws -> ConnFlow {
        try await run {
            let f = try await client.getConnectionFlow(path: .init(id: id)).ok.body.json
            guard f.step == "choose_site", let site else {
                guard let c = f.connection else { return try await flow(f) }
                var done = Self.flow(f, install: nil)
                done.step = .connected(c)
                return done
            }
            // The sheet shows names; the Core wants the site's id.
            let pick = f.sites.first { $0.name == site || $0.id == site }?.id ?? site
            let next = try await client.chooseConnectionSite(path: .init(id: id), body: .json(.init(site: pick))).ok
                .body
                .json
            return try await flow(next)
        }
    }

    func deliver(_ id: String, code: String, state: String) async throws -> ConnFlow {
        try await run {
            try await flow(
                try await client.connectionFlowCallback(
                    path: .init(id: id), body: .json(.init(code: code, state: state))
                )
                .ok.body.json)
        }
    }

    func cancel(_ id: String) async throws {
        try await run { _ = try await client.cancelConnectionFlow(path: .init(id: id)).ok }
    }

    /// A flow as the sheet shows it. Only a finished GitHub sign-in needs the kind (for its app install page).
    private func flow(_ f: Components.Schemas.ConnectionFlow) async throws -> ConnFlow {
        var install: URL?
        if f.step == "connected", f.connection != nil {
            let k = try? await client.listConnectionKinds().ok.body.json.first { $0.kind == f.kind }
            if k?.authMethods.contains(where: { $0.id == "app_install" && $0.available }) == true {
                install = k?.installUrl.flatMap(URL.init(string:))
            }
        }
        return Self.flow(f, install: install)
    }

    func addToken(kind: String, name: String, fields: [String: String], token: String) async throws -> ConnItem {
        try await run {
            let body = Components.Schemas.NewConnection(
                authMethod: "token", email: fields[Self.emailField], kind: kind, name: name,
                site: fields[Self.siteField],
                token: token)
            return Self.item(
                try await client.createConnection(body: .json(body)).ok.body.json, service: nil, grants: nil)
        }
    }

    func install(kind: String, installation: Int64) async throws -> ConnItem {
        try await run {
            let body = Components.Schemas.NewConnection(
                authMethod: "app_install", installationId: installation, kind: kind)
            return Self.item(
                try await client.createConnection(body: .json(body)).ok.body.json, service: nil, grants: nil)
        }
    }

    // MARK: acting on a connection

    func test(_ id: Int64) async throws -> String {
        try await run {
            let c = try await client.testConnection(path: .init(id: String(id))).ok.body.json
            let title = try? await client.listConnectionKinds().ok.body.json.first { $0.kind == c.kind }?.title
            let shown = Self.item(c, service: title, grants: nil)
            return shown.status == .connected
                ? "Works. \(Self.name(of: c.kind, title)) answered."
                : shown.reason ?? "It didn't answer. Sign in again."
        }
    }

    func rename(_ id: Int64, to name: String) async throws {
        try await run {
            _ = try await client.updateConnection(path: .init(id: String(id)), body: .json(.init(name: name))).ok
        }
    }

    func setDefault(_ id: Int64) async throws {
        try await run {
            let kind = try await client.getConnection(path: .init(id: String(id))).ok.body.json.kind
            _ = try await client.setConnectionDefault(path: .init(kind: kind), body: .json(.init(connection: id))).ok
        }
    }

    /// "Who can use it" is the role `member`, which is who the agent sessions run as. No allowed capability means no grant.
    func setAccess(_ id: Int64, allowed: Set<String>, only: [String]?) async throws {
        try await run {
            let path = Operations.RevokeConnectionGrant.Input.Path(
                id: String(id), granteeKind: "role", grantee: "member")
            if allowed.isEmpty {
                _ = try await client.revokeConnectionGrant(path: path).ok
                return
            }
            let kind = try await client.getConnection(path: .init(id: String(id))).ok.body.json.kind
            let key = try await client.listConnectionKinds().ok.body.json.first { $0.kind == kind }?.limits.first?.key
            var limits: [String: [String]] = [:]
            if let key, let only, !only.isEmpty { limits[key] = only }
            _ = try await client.setConnectionGrant(
                path: .init(id: String(id)),
                body: .json(
                    .init(
                        capabilities: allowed.sorted(), grantee: "member", granteeKind: "role",
                        limits: .init(additionalProperties: limits)))
            ).ok
        }
    }

    func delete(_ id: Int64) async throws {
        try await run { _ = try await client.deleteConnection(path: .init(id: String(id))).ok }
    }

    func defaults() async throws -> [String: Int64] {
        try await run {
            Dictionary(
                try await client.listConnectionDefaults().ok.body.json.map { ($0.kind, $0.connection) },
                uniquingKeysWith: { a, _ in a })
        }
    }

    func clearDefault(kind: String) async throws {
        try await run { _ = try await client.clearConnectionDefault(path: .init(kind: kind)).ok }
    }

    func app(kind: String) async throws -> ConnApp {
        try await run { Self.app(try await client.getConnectionApp(path: .init(kind: kind)).ok.body.json) }
    }

    func setApp(kind: String, fields: [String: String]) async throws -> ConnApp {
        try await run {
            let body = Components.Schemas.SetConnectionApp(
                fields: .init(additionalProperties: fields.mapValues { $0 as String? }))
            return Self.app(try await client.setConnectionApp(path: .init(kind: kind), body: .json(body)).ok.body.json)
        }
    }

    func replaceCredential(_ id: Int64, token: String, fields: [String: String]) async throws {
        try await run {
            let body = Components.Schemas.NewConnectionCredential(
                email: fields[Self.emailField], site: fields[Self.siteField], token: token)
            _ = try await client.replaceConnectionCredential(path: .init(id: String(id)), body: .json(body)).ok
        }
    }

    func coreSetting(_ key: String) async throws -> Int64 {
        try await run { try await client.listServerSettings().ok.body.json.first { $0.key == key }?.value ?? 0 }
    }

    func setCoreSetting(_ key: String, _ value: Int64) async throws {
        try await run {
            _ = try await client.setSetting(path: .init(scope: "server", key: key), body: .json(.init(value: value))).ok
        }
    }

    static func app(_ a: Components.Schemas.ConnectionApp) -> ConnApp {
        ConnApp(
            kind: a.kind, configured: a.configured,
            fields: a.fields.map {
                ConnApp.Field(
                    id: $0.name, title: $0.title, secret: $0.secret, isSet: $0.set, value: $0.secret ? nil : $0.value)
            }, redirect: a.redirectUri)
    }

    // MARK: mapping

    static let siteField = "Site"
    static let emailField = "Your Atlassian email"

    /// The Core's transport already turns 401, 403 and 429 into a `CoreError`; the rest are read from the answer.
    private func run<T>(_ body: () async throws -> T) async throws -> T {
        do { return try await body() } catch { throw CoreFailure.of(error) ?? error }
    }

    /// The sheet is drawn from this: a kind the app has never heard of renders the same way.
    static func kind(_ k: Components.Schemas.ConnectionKind) -> ConnKind {
        let token = k.authMethods.first { $0.id == "token" && $0.available }
        let limit = k.limits.first
        return ConnKind(
            id: k.kind, name: k.title, say: k.summary, signIn: k.kind == "github" ? .deviceCode : .browser,
            resource: limit?.title.lowercased() ?? "places",
            capabilities: k.capabilities.map {
                ConnCapability(
                    id: $0.name, title: $0.title,
                    say: $0.write ? "Changes things on \(k.title)." : "Looks, never changes anything.", writes: $0.write
                )
            },
            tokenTitle: token?.title ?? "", tokenHelp: token?.steps ?? [],
            // The descriptor does not list the extra fields a token needs yet; Jira's two are known.
            tokenFields: token != nil && k.kind == "jira" ? [siteField, emailField] : [],
            available: k.authMethods.contains { $0.available }, limitKey: limit?.key,
            installURL: k.installUrl.flatMap(URL.init(string:)))
    }

    private static let stub = Components.Schemas.Connection(
        authMethod: "", createdAt: .distantPast, disabled: false, id: 0, isDefault: false, kind: "", label: "",
        name: "", status: "active", updatedAt: .distantPast)

    static func name(of kind: String, _ title: String?) -> String { title ?? kind.capitalized }

    static func item(
        _ c: Components.Schemas.Connection, service: String?, grants: [Components.Schemas.ConnectionGrant]?
    )
        -> ConnItem
    {
        let service = name(of: c.kind, service)
        let authLost = c.stateReason == "auth_suspected" || c.stateReason == "auth_failed"
        let status: ConnStatus =
            authLost
            ? .needsLook
            : (c.disabled || c.status == "disabled") ? .disabled : c.status == "active" ? .connected : .needsLook
        let member = grants?.first { $0.granteeKind == "role" && $0.grantee == "member" }
        let chosen = member?.limits.additionalProperties.values.first { !$0.isEmpty }
        return ConnItem(
            id: c.id, kind: c.kind, name: c.name, identity: c.identity ?? c.label, status: status,
            reason: status == .needsLook ? reason(c.stateReason, service: service) : nil, isDefault: c.isDefault,
            allowed: Set(grants == nil ? (c.myCapabilities ?? []) : (member?.capabilities ?? [])), only: chosen,
            lastUsed: nil, lastChecked: c.lastTestedAt, users: Int(c.grantCount ?? 1))
    }

    /// The Core's reasons are short codes; the screen says them in words.
    static func reason(_ code: String?, service: String) -> String {
        switch code {
        case "rate_limited": "\(service) asked Core to slow down. It tries again by itself."
        case "upstream_errors": "\(service) keeps answering with errors. Core tries again by itself."
        case "quota": "You used up what \(service) allows for now. It starts again by itself."
        case "auth_suspected": "\(service) says this sign-in expired."
        case "auth_failed": "\(service) refused this sign-in."
        default: "This sign-in stopped working."
        }
    }

    static func flow(_ f: Components.Schemas.ConnectionFlow, install: URL?) -> ConnFlow {
        let service = name(of: f.kind, nil)
        let url = (f.verificationUri ?? f.authorizeUrl).flatMap(URL.init(string:)) ?? URL(string: "about:blank")!
        let step: ConnFlow.Step =
            switch f.step {
            case "connected":
                if let c = f.connection {
                    install.map { .chooseResources(login: f.identity ?? "", install: $0) } ?? .connected(c)
                } else {
                    failed(f, service)
                }
            case "choose_site": .pickSite(f.sites.map(\.name))
            case "expired":
                .failed(
                    title: "The sign-in ran out of time.",
                    fix: "Try again for a new one, then finish it within a few minutes.")
            case "denied":
                .failed(title: "\(service) said no.", fix: "Nothing was connected. Try again if that was a mistake.")
            case "failed": failed(f, service)
            default: .waiting
            }
        return ConnFlow(
            id: f.id, kind: f.kind, userCode: f.userCode, url: url, step: step, callbackState: f.state,
            gated: ConnSay.isGate(code: f.errorCode))
    }

    private static func failed(_ f: Components.Schemas.ConnectionFlow, _ service: String) -> ConnFlow.Step {
        switch f.errorCode {
        case "different_account":
            .failed(
                title: "That is a different \(service) account.",
                fix:
                    "Sign in with the account this connection was made with, or disconnect it and connect the other one."
            )
        case "identity_unavailable":
            .failed(
                title: "You signed in, but \(service) wouldn't say who you are.", fix: "Wait a minute and try again.")
        case "signin_service":
            .failed(title: ConnSay.serviceDown, fix: "Nothing was connected.")
        case "installation_not_yours":
            .failed(title: ConnSay.notYours, fix: "Choose repositories with the GitHub account you signed in with.")
        case "github_sign_in_needed", "bad_user_token":
            .failed(title: ConnSay.signInAgain, fix: "Press Try again.")
        case "real_secret_refused", "secrets_disabled":
            .failed(title: "Connections are turned off on this Core.", fix: ConnSay.turnedOff)
        default:
            .failed(
                title: f.errorMessage.flatMap { $0.contains(" ") ? $0 : nil } ?? "The sign-in didn't finish.",
                fix: "Nothing was connected. Try again.")
        }
    }

    static func use(_ u: Components.Schemas.ConnectionUse, connection: Int64) -> ConnActivity {
        let action =
            u.action?.split(separator: ".").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? "Used it"
        let ok = u.result == nil || u.result == "ok"
        return ConnActivity(
            id: u.seq, connection: connection, who: u.agent ?? "Core",
            what: String(action.prefix(1).uppercased() + action.dropFirst()),
            ok: ok, result: ok ? "Done" : u.result == "refused" ? "Not allowed" : "Didn't work", at: u.at)
    }
}

/// Every failure in plain words with what to do, never a code.
enum ConnSay {
    static let notConfigured =
        "This service isn't set up on your Core. If it's self-hosted, use Your own app on this page."
    static let serviceDown = "Ainkrad's sign-in service can't be reached. Try again in a minute."
    static let notYours = "This GitHub install isn't yours."
    static let signInFirst = "Sign in to GitHub first."
    static let signInAgain = "Sign in to GitHub again."

    /// The Core says "sign in to GitHub first" with its own code (also when the token ran out).
    static func needsGitHubSignIn(_ error: any Error) -> Bool {
        guard case .http(_, let code, _)? = CoreError.unwrapping(error) ?? error as? CoreError else { return false }
        return code == "github_sign_in_needed"
    }

    /// Choosing repositories failed: the step the sheet shows. A person who just signed in has an expired token, so it is "again".
    static func installFailure(_ error: any Error, hasGitHub: Bool) -> ConnFlow.Step {
        if needsGitHubSignIn(error) {
            let say = hasGitHub ? signInAgain : signInFirst
            return .failed(title: say, fix: "Press Try again to sign in, then choose repositories.")
        }
        return .failed(title: "Couldn't use the repositories you chose.", fix: plain(error))
    }
    static let turnedOff = "Press Turn on connections. This Mac does it for you."

    /// The Core's two refusals that mean "connections are off": the broker is off, or a real token isn't admitted yet.
    static func isGate(code: String?) -> Bool { code == "real_secret_refused" || code == "secrets_disabled" }
    static func isGate(_ error: any Error) -> Bool {
        if case .http(_, let code, _)? = CoreError.unwrapping(error) ?? error as? CoreError {
            return isGate(code: code)
        }
        return false
    }

    /// Why "Turn on connections" itself didn't work, in words.
    static func turnOnRefusal(_ error: any Error) -> String {
        if case .forbiddenScope? = CoreError.unwrapping(error) ?? error as? CoreError {
            return
                "This Mac can only look. Turning connections on needs a Mac you allowed to manage the Core. Nothing was changed."
        }
        return plain(error)
    }

    static func plain(_ error: any Error) -> String {
        guard let e = error as? CoreError ?? CoreError.unwrapping(error) else {
            return "Your Core didn't take that. Nothing was changed; try again."
        }
        switch e {
        case .offline: return "This Mac can't reach your Core. Check the network, then try again."
        case .forbiddenScope:
            return "This Mac can only look. Changes need a Mac you allowed to manage the Core. Nothing was changed."
        case .stepUpRequired: return "Touch ID is needed for that. Try again and confirm it."
        case .authFailed, .sessionExpired, .revoked:
            return "This Mac needs to sign in to your Core again. Reopen Ainkrad and try again."
        case .rateLimited(let s):
            return "That was tried a moment ago. Try again in \(max(Int((s ?? 5).rounded(.up)), 1)) seconds."
        case .http(let status, let code, let message):
            if isGate(code: code) { return "Connections are turned off on this Core. \(turnedOff)" }
            if needsGitHubSignIn(error) { return signInFirst }
            switch code {
            case "signin_service": return serviceDown
            case "installation_not_yours": return notYours
            case "no_runner": return AccountsModel.noRunnerWords
            case "credential_rejected": return AccountsModel.credentialWords
            case "not_configured": return ConnSay.notConfigured
            case "upstream_failed": return "That service couldn't be reached from your Core. Try again in a moment."
            case "limit_reached": return "Your Core has as many connections as it allows. Remove one, then try again."
            default: break
            }
            if status == 409 {
                return
                    "This is still the default for its service. Make another one the default first, then disconnect it."
            }
            if status == 404 { return "That connection is gone already. Nothing was changed." }
            // The Core's own reason, so a refusal says what to fix.
            let why = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return why.isEmpty
                ? "Your Core didn't take that. Nothing was changed; try again."
                : "Your Core said: \(why.hasSuffix(".") ? why : why + "."). Nothing was changed. Your input is still here."
        default: return "Your Core didn't take that. Nothing was changed; try again."
        }
    }
}
