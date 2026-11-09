import AinkradClient
import CoreKit
import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing

@testable import Accounts

/// Answers each operation with canned JSON and remembers what was asked, without a network.
final class StubCore: ClientTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [String: String]
    private var asked: [(op: String, body: String)] = []
    init(_ answers: [String: String]) { self.answers = answers }
    func answer(_ op: String, _ json: String) { lock.withLock { answers[op] = json } }
    func bodies(_ op: String) -> [String] { lock.withLock { asked.filter { $0.op == op }.map(\.body) } }

    func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String) async throws -> (
        HTTPResponse, HTTPBody?
    ) {
        var sent = ""
        if let body { sent = String(decoding: try await Data(collecting: body, upTo: 1 << 20), as: UTF8.self) }
        let json = lock.withLock {
            asked.append((operationID, sent))
            return answers[operationID] ?? "{}"
        }
        var res = HTTPResponse(status: .ok)
        res.headerFields[.contentType] = "application/json"
        return (res, HTTPBody(json))
    }
}

private let t = "2026-11-06T10:00:00.000Z"

private func conn(
    _ id: Int, kind: String = "github", status: String = "active", reason: String? = nil, disabled: Bool = false,
    grants: Int? = 2
) -> String {
    """
    {"id":\(id),"kind":"\(kind)","name":"Name \(id)","label":"@dev","auth_method":"oauth","identity":"@dev",
     "status":"\(status)","state_reason":\(reason.map { "\"\($0)\"" } ?? "null"),"disabled":\(disabled),
     "is_default":\(id == 1),"created_at":"\(t)","updated_at":"\(t)","last_tested_at":"\(t)",
     "grant_count":\(grants.map(String.init) ?? "null"),"my_capabilities":["read_repo"]}
    """
}

private let kindsJSON = """
    [{"kind":"github","title":"GitHub","summary":"Code and issues","configured":true,"install_url":"https://github.com/apps/x/installations/new",
      "auth_methods":[{"id":"oauth","title":"Sign in","help":"h","steps":[],"advanced":false,"available":true},
                      {"id":"app_install","title":"Choose repositories","help":"h","steps":[],"advanced":false,"available":true},
                      {"id":"token","title":"Use a personal access token","help":"h","steps":["Open settings","Paste it"],"advanced":true,"available":true}],
      "capabilities":[{"name":"read_repo","title":"Read code and issues","class":"read","write":false},
                      {"name":"issues_write","title":"Create and change issues","class":"write","write":true}],
      "limits":[{"key":"repos","title":"Repositories","help":"owner/name"}]},
     {"kind":"slack","title":"Slack","summary":"Messages","configured":true,"install_url":null,
      "auth_methods":[{"id":"oauth","title":"Sign in","help":"h","steps":[],"advanced":false,"available":true}],
      "capabilities":[{"name":"post","title":"Post messages","class":"write","write":true}],
      "limits":[{"key":"channels","title":"Channels","help":"names"}]}]
    """

private func live(_ core: StubCore) -> LiveConnectionsService {
    LiveConnectionsService(
        client: Client(
            serverURL: URL(string: "http://core.test")!,
            configuration: .init(dateTranscoder: .iso8601WithFractionalSeconds), transport: core))
}

struct LiveConnectionsTests {
    @Test func aKindTheAppNeverHeardOfRendersLikeTheOthers() async throws {
        let ks = try await live(StubCore(["listConnectionKinds": kindsJSON])).kinds()
        #expect(ks.map(\.id) == ["github", "slack"])
        let gh = ks[0]
        #expect(gh.signIn == .deviceCode && gh.resource == "repositories" && gh.limitKey == "repos")
        #expect(gh.capabilities.map(\.writes) == [false, true])
        #expect(gh.tokenHelp == ["Open settings", "Paste it"] && gh.installURL != nil)
        let slack = ks[1]
        #expect(slack.signIn == .browser && slack.available && slack.resource == "channels")
        #expect(slack.tokenTitle.isEmpty)  // no token method, so no Advanced link
    }

    @Test func connectionsSayWhatIsWrongInWordsAndWhoMayUseThem() async throws {
        let core = StubCore([
            "listConnectionKinds": kindsJSON,
            "listConnections":
                "[\(conn(1)),\(conn(2, status: "unhealthy", reason: "auth_suspected")),\(conn(3, status: "disabled", disabled: true))]",
            "listConnectionGrants":
                #"[{"grantee_kind":"role","grantee":"member","capabilities":["read_repo"],"limits":{"repos":["a/b"]},"created_at":"\#(t)","updated_at":"\#(t)"}]"#,
        ])
        let items = try await live(core).connections()
        #expect(items.map(\.status) == [.connected, .needsLook, .disabled])
        #expect(items[1].reason == "GitHub says this sign-in expired.")
        #expect(items[0].reason == nil && items[0].isDefault && items[0].users == 2)
        #expect(items[0].allowed == ["read_repo"] && items[0].only == ["a/b"])
        #expect(items[0].lastChecked != nil)
    }

    @Test func aMemberSeesOnlyWhatTheyMayDoAndNoGrantCalls() async throws {
        let core = StubCore([
            "listConnectionKinds": kindsJSON, "listConnections": "[\(conn(1, grants: nil))]",
        ])
        let items = try await live(core).connections()
        #expect(items[0].allowed == ["read_repo"])
        #expect(core.bodies("listConnectionGrants").isEmpty)
    }

    @Test func atlassianKeepsItsOwnStateNotTheFlowId() async throws {
        let core = StubCore([
            "listConnectionKinds": kindsJSON,
            "startConnectionFlow":
                #"{"id":"cf_1","kind":"jira","step":"waiting","expires_in_secs":600,"sites":[],"authorize_url":"https://auth.atlassian.com/authorize?x=1","state":"st_9"}"#,
            "connectionFlowCallback":
                #"{"id":"cf_1","kind":"jira","step":"choose_site","expires_in_secs":500,"state":"st_9","sites":[{"id":"cloud-1","name":"Acme","url":"https://acme.atlassian.net"}]}"#,
            "getConnectionFlow":
                #"{"id":"cf_1","kind":"jira","step":"choose_site","expires_in_secs":500,"sites":[{"id":"cloud-1","name":"Acme","url":"https://acme.atlassian.net"}]}"#,
            "chooseConnectionSite":
                #"{"id":"cf_1","kind":"jira","step":"connected","expires_in_secs":500,"sites":[],"connection":7,"identity":"acme.atlassian.net"}"#,
        ])
        let svc = live(core)
        let f = try await svc.start(kind: "jira", again: nil)
        #expect(f.id == "cf_1" && f.callbackState == "st_9" && f.url.host == "auth.atlassian.com")
        let next = try await svc.deliver(f.id, code: "the-code", state: "st_9")
        #expect(next.step == .pickSite(["Acme"]))
        #expect(core.bodies("connectionFlowCallback").first?.contains("st_9") == true)
        let done = try await svc.choose("cf_1", site: "Acme")  // the sheet shows names, the Core wants the id
        #expect(done.step == .connected(7))
        #expect(core.bodies("chooseConnectionSite").first?.contains("cloud-1") == true)
    }

    @Test func gitHubAppInstallIsAConnectionNotAFlowStep() async throws {
        let core = StubCore([
            "listConnectionKinds": kindsJSON,
            "getConnectionFlow":
                #"{"id":"cf_2","kind":"github","step":"connected","expires_in_secs":0,"sites":[],"connection":4,"identity":"@dev","user_code":"WDJB-MJHT","verification_uri":"https://github.com/login/device"}"#,
            "createConnection": conn(5),
        ])
        let svc = live(core)
        let f = try await svc.flow("cf_2")
        guard case .chooseResources(let login, let install) = f.step else {
            Issue.record("no repository step")
            return
        }
        #expect(login == "@dev" && install.host == "github.com" && f.userCode == "WDJB-MJHT")
        // Skipping finishes with the connection the sign-in already made.
        #expect(try await svc.choose("cf_2", site: nil).step == .connected(4))
        _ = try await svc.install(kind: "github", installation: 4242)
        let sent = try #require(core.bodies("createConnection").first)
        #expect(sent.contains("app_install") && sent.contains("4242"))
    }

    @Test func aFailedSignInIsASentenceWithAFix() {
        func step(_ code: String) -> ConnFlow.Step {
            let f = try! JSONDecoder().decode(
                Components.Schemas.ConnectionFlow.self,
                from: Data(
                    #"{"id":"cf","kind":"github","step":"failed","expires_in_secs":0,"sites":[],"error_code":"\#(code)"}"#
                        .utf8)
            )
            return LiveConnectionsService.flow(f, install: nil).step
        }
        for code in ["different_account", "identity_unavailable", "real_secret_refused", "whatever"] {
            guard case .failed(let title, let fix) = step(code) else {
                Issue.record("\(code) did not fail")
                continue
            }
            #expect(!title.contains("_") && !fix.contains("_") && !fix.isEmpty)
        }
    }

    @Test func savingAccessGrantsTheMemberRoleOrRevokesIt() async throws {
        let core = StubCore([
            "getConnection": conn(1), "listConnectionKinds": kindsJSON, "revokeConnectionGrant": #"{"deleted":true}"#,
            "setConnectionGrant":
                #"{"grantee_kind":"role","grantee":"member","capabilities":[],"limits":{},"created_at":"\#(t)","updated_at":"\#(t)"}"#,
        ])
        let svc = live(core)
        try await svc.setAccess(1, allowed: ["read_repo", "issues_write"], only: ["a/b", "a/*"])
        let sent = try #require(core.bodies("setConnectionGrant").first)
        #expect(
            sent.contains("\"member\"") && sent.contains("\"role\"") && sent.contains(#"a\/b"#)
                && sent.contains("repos"))
        try await svc.setAccess(1, allowed: [], only: nil)
        #expect(core.bodies("revokeConnectionGrant").count == 1)
    }

    @Test func theTestSaysWorksOrWhyNot() async throws {
        let core = StubCore(["testConnection": conn(1), "listConnectionKinds": kindsJSON])
        #expect(try await live(core).test(1) == "Works. GitHub answered.")
        core.answer("testConnection", conn(1, status: "cooling", reason: "rate_limited"))
        #expect(try await live(core).test(1).contains("slow down"))
    }

    @Test func errorsNeverShowCodes() {
        let all: [CoreError] = [
            .offline("x"), .forbiddenScope, .stepUpRequired, .sessionExpired, .rateLimited(retryAfter: 7),
            .http(status: 409, code: "default_in_use", message: "m"),
            .http(status: 400, code: "real_secret_refused", message: "m"),
            .http(status: 500, code: "internal_error", message: "m"),
        ]
        for e in all {
            let say = ConnSay.plain(e)
            #expect(!say.contains("_") && say.hasSuffix("."))
        }
        #expect(ConnSay.plain(CoreError.rateLimited(retryAfter: 7)).contains("7 seconds"))
    }

    @Test func theLoopbackCatchesGitHubsSetupRedirectAndNothingElse() {
        #expect(
            LoopbackCatcher.code(in: "GET /callback?installation_id=42&setup_action=install HTTP/1.1\r\n", state: nil)
                == "42")
        #expect(LoopbackCatcher.code(in: "GET /callback?installation_id=x HTTP/1.1\r\n", state: nil) == nil)
        #expect(LoopbackCatcher.code(in: "GET /callback?code=c&state=s HTTP/1.1\r\n", state: nil) == nil)
        #expect(LoopbackCatcher.code(in: "GET /callback?code=c&state=s HTTP/1.1\r\n", state: "s") == "c")
        #expect(LoopbackCatcher.code(in: "GET /callback?code=c&state=other HTTP/1.1\r\n", state: "s") == nil)
    }
}
