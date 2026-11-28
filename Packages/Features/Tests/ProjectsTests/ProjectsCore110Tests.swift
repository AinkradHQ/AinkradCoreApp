import AinkradClient
import CoreKit
import Foundation
import Testing

@testable import Projects

// Core API minor 110 (AinkradCore #530): the private preview, colour, steps, metrics, branch change and crash alerts, on the
// Core's real JSON shapes (api/openapi.json of feat/projects-core).

struct PreviewProxyTests {
    @Test func onlyTheCoresSandboxIsDroppedFromThePolicy() {
        let core = PreviewProxy.coreSandbox
        #expect(PreviewProxy.withoutCoreSandbox(core) == nil)
        #expect(PreviewProxy.withoutCoreSandbox("default-src 'self', \(core)") == "default-src 'self'")
        #expect(PreviewProxy.withoutCoreSandbox("\(core), img-src *") == "img-src *")
        #expect(PreviewProxy.withoutCoreSandbox("sandbox allow-scripts") == "sandbox allow-scripts")
        #expect(PreviewProxy.withoutCoreSandbox(nil) == nil)
    }

    @Test func theTargetIsTheProjectsPreviewPathSignedAsSent() throws {
        func t(_ s: String) -> String? { PreviewProxy.target(project: 7, for: URL(string: s)!) }
        #expect(t("ainkrad-preview://project/") == "/api/v1/projects/7/preview/")
        #expect(t("ainkrad-preview://project") == "/api/v1/projects/7/preview/")
        #expect(
            t("ainkrad-preview://project/assets/app.js?v=3&x=a%2fb")
                == "/api/v1/projects/7/preview/assets/app.js?v=3&x=a%2Fb")
        // Percent escapes are upper-case in path and query.
        #expect(t("ainkrad-preview://project/a%c3%a9/b%20c") == "/api/v1/projects/7/preview/a%C3%A9/b%20c")
        // Another scheme or host is not the preview.
        #expect(t("https://project/") == nil)
        #expect(t("ainkrad-preview://evil/") == nil)
    }

    @Test func aPathCannotClimbOutOfTheProjectsPreview() {
        func t(_ s: String) -> String? { PreviewProxy.target(project: 7, for: URL(string: s)!) }
        #expect(t("ainkrad-preview://project/../8/preview/x") == nil)
        #expect(t("ainkrad-preview://project/%2e%2e/%2e%2e/projects/8") == nil)
        #expect(t("ainkrad-preview://project/a%2Fb") == nil)
        #expect(t("ainkrad-preview://project/a%5Cb") == nil)
        #expect(t("ainkrad-preview://project/a%00b") == nil)
    }

    // (a) Authorization and Origin are never sent; neither are cookies or the referrer of the web view.
    @Test func onlyPlainHeadersGoToTheCore() {
        let sent = PreviewProxy.headers(from: [
            "Authorization": "Bearer x", "Origin": "ainkrad-preview://project", "Cookie": "a=b",
            "Referer": "ainkrad-preview://project/", "Accept": "text/html", "Accept-Language": "en",
            "Content-Type": "application/json", "Range": "bytes=0-9", "X-Whatever": "1", "Ainkrad-Signature": "forged",
        ])
        #expect(Set(sent.keys) == ["accept", "accept-language", "content-type", "range"])
    }

    // (b) A redirect is followed only inside this project's preview of the same Core.
    @Test func redirectsStayInsideTheProjectsPreview() {
        let here = URL(string: "ainkrad-preview://project/login")!
        func r(_ loc: String, core: String? = "core.example:8443") -> PreviewProxy.Redirect {
            PreviewProxy.redirect(location: loc, from: here, project: 7, coreHost: core)
        }
        func go(_ s: String) -> PreviewProxy.Redirect { .follow(URL(string: s)!) }
        #expect(r("/home?x=1") == go("ainkrad-preview://project/home?x=1"))
        #expect(r("dashboard") == go("ainkrad-preview://project/dashboard"))
        #expect(r("ainkrad-preview://project/a") == go("ainkrad-preview://project/a"))
        #expect(r("https://core.example:8443/api/v1/projects/7/preview/in") == go("ainkrad-preview://project/in"))
        #expect(r("https://core.example:8443/api/v1/projects/7/preview") == go("ainkrad-preview://project/"))
        // Outside: another site, another project's route on the Core, another Core, a protocol-relative address, other schemes.
        #expect(r("https://evil.example/x") == .outside)
        #expect(r("http://localhost:3000/x") == .outside)
        #expect(r("https://core.example:8443/api/v1/projects/8/preview/x") == .outside)
        #expect(r("https://core.example:8443/api/v1/devices") == .outside)
        #expect(r("https://other.example:8443/api/v1/projects/7/preview/x") == .outside)
        #expect(r("//evil.example/x") == .outside)
        #expect(r("javascript:alert(1)") == .outside)
        #expect(r("file:///etc/passwd") == .outside)
        #expect(r("https://core.example:8443/api/v1/projects/7/preview/%2e%2e/x") == .outside)
        // Without a known Core nothing absolute is followed.
        #expect(r("https://core.example:8443/api/v1/projects/7/preview/in", core: nil) == .outside)
        // A path that looks like another project's route is the app's own path, mapped under this project.
        #expect(r("/api/v1/projects/8/preview/x") == go("ainkrad-preview://project/api/v1/projects/8/preview/x"))
        #expect(
            PreviewProxy.target(project: 7, for: URL(string: "ainkrad-preview://project/api/v1/projects/8/preview/x")!)
                == "/api/v1/projects/7/preview/api/v1/projects/8/preview/x")
    }

    // (c) Cookies are per project: one jar per web view, nothing shared.
    @Test func cookiesLiveInTheProjectsOwnJar() {
        var a = PreviewCookieJar()
        var b = PreviewCookieJar()
        a.store(setCookie: "sid=abc; Path=/; HttpOnly")
        #expect(a.header == "sid=abc" && b.header == nil)
        a.store(setCookie: "theme=dark; Max-Age=60, lang=en; Path=/")
        #expect(a.header == "lang=en; sid=abc; theme=dark")
        // A date inside Expires is not a second cookie.
        b.store(setCookie: "t=1; Expires=Wed, 21 Oct 2037 07:28:00 GMT; Path=/")
        #expect(b.header == "t=1" && b.cookies.count == 1)
        a.store(setCookie: "sid=; Max-Age=0")
        a.store(setCookie: "lang=; Expires=Thu, 01 Jan 1970 00:00:00 GMT")
        #expect(a.header == "theme=dark")
        #expect(b.header == "t=1")
    }

    @MainActor @Test func everyHandlerStartsWithItsOwnEmptyJar() {
        let f: PreviewFetch = { _, _, _, _ in PreviewReply(status: 200, headers: [:], body: Data()) }
        let one = PreviewSchemeHandler(project: 1, coreHost: nil, fetch: f)
        let two = PreviewSchemeHandler(project: 2, coreHost: nil, fetch: f)
        #expect(one.jar.header == nil && two.jar.header == nil && one !== two)
    }

    @Test func theCoresWordsForWhatItCannotShow() {
        func r(_ status: Int, _ body: String) -> PreviewReply {
            PreviewReply(status: status, headers: [:], body: Data(body.utf8))
        }
        #expect(
            PreviewProxy.problem(r(409, #"{"code":"not_running","message":"tidepool is stopped"}"#))
                == "tidepool is stopped")
        #expect(
            PreviewProxy.problem(r(409, #"{"code":"not_running"}"#))
                == "The project is not running. Start it to see it here.")
        #expect(PreviewProxy.problem(r(409, #"{"code":"no_preview"}"#))?.contains("web port") == true)
        #expect(PreviewProxy.problem(r(503, #"{"code":"busy"}"#))?.contains("busy") == true)
        #expect(PreviewProxy.problem(r(502, #"{"code":"bad_gateway"}"#))?.contains("did not answer") == true)
        #expect(PreviewProxy.problem(r(504, #"{"code":"gateway_timeout"}"#)) == "The app did not answer in 25 seconds.")
        // The running app's own answers are shown as they are.
        #expect(PreviewProxy.problem(r(404, "<h1>Not found</h1>")) == nil)
        #expect(PreviewProxy.problem(r(500, "oops")) == nil)
        #expect(PreviewProxy.problem(r(409, "conflict in the app")) == nil)
        #expect(PreviewProxy.problem(r(200, "ok")) == nil)
    }

    @MainActor @Test func busyIsAskedAgainAfterItsRetryAfterThenGivenUp() async throws {
        final class Count: @unchecked Sendable { var n = 0 }
        let c = Count()
        let busy = PreviewReply(status: 503, headers: ["retry-after": "0"], body: Data(#"{"code":"busy"}"#.utf8))
        let ok = PreviewReply(status: 200, headers: [:], body: Data("hi".utf8))
        let recovers: PreviewFetch = { _, _, _, _ in
            c.n += 1
            return c.n < 3 ? busy : ok
        }
        let r = try await PreviewSchemeHandler.send(recovers, "GET", "/x", [:], Data())
        #expect(r.status == 200 && c.n == 3)
        c.n = 0
        let stuck: PreviewFetch = { _, _, _, _ in
            c.n += 1
            return busy
        }
        let g = try await PreviewSchemeHandler.send(stuck, "GET", "/x", [:], Data())
        #expect(g.status == 503 && c.n == 3)
    }

    // (e) The body and the page's own headers (CSP, CORP) go through; only the transport's framing headers do not.
    @MainActor @Test func theAnswerPassesThroughWithoutItsFraming() throws {
        let reply = PreviewReply(
            status: 200,
            headers: [
                "content-type": "text/html", "content-security-policy": "sandbox allow-scripts",
                "cross-origin-resource-policy": "same-origin", "content-encoding": "gzip", "content-length": "999",
                "set-cookie": "sid=1", "transfer-encoding": "chunked",
            ], body: Data("<p>hi</p>".utf8))
        let res = try #require(
            PreviewSchemeHandler.response(reply, url: URL(string: "ainkrad-preview://project/")!) as? HTTPURLResponse)
        #expect(res.statusCode == 200 && res.value(forHTTPHeaderField: "Content-Type") == "text/html")
        #expect(res.value(forHTTPHeaderField: "Content-Security-Policy") == "sandbox allow-scripts")
        #expect(res.value(forHTTPHeaderField: "Cross-Origin-Resource-Policy") == "same-origin")
        #expect(res.value(forHTTPHeaderField: "Content-Length") == "9")
        #expect(
            res.value(forHTTPHeaderField: "Content-Encoding") == nil
                && res.value(forHTTPHeaderField: "Set-Cookie") == nil)
        #expect(res.value(forHTTPHeaderField: "Transfer-Encoding") == nil)
    }
}

struct Core110WireTests {
    private let project = """
        {"id":7,"slug":"tidepool","name":"Tidepool","description":"","state":"active","expose":false,"color":"teal",
         "cpu_limit":2.0,"mem_limit_mb":2048,"idle_minutes":30,"fetch_interval_minutes":15,"runner":"auto",
         "source":"manual","created_at":"2026-11-20T10:00:00.000Z","updated_at":"2026-11-27T10:00:00.000Z","repos":[]}
        """

    @Test func aProjectCarriesItsColour() throws {
        let one = try LiveProjectsService.decode(Data(project.utf8))
        #expect(one.count == 1 && one[0].colourName == "teal" && one[0].slug == "tidepool")
        let list = try LiveProjectsService.decode(
            Data(
                "[\(project),\(project.replacingOccurrences(of: ",\"color\":\"teal\"", with: "").replacingOccurrences(of: "\"id\":7", with: "\"id\":8"))]"
                    .utf8))
        #expect(list.map(\.colourName) == ["teal", nil])
    }

    @Test func aRunCarriesItsSteps() throws {
        let json = """
            {"id":"r_1","state":"starting","runner":"d_mac","spec_version":2,"started_at":"2026-11-27T10:00:00.000Z",
             "started_by":"d","last_activity_at":"2026-11-27T10:00:00.000Z",
             "steps":[{"name":"pull","state":"done"},{"name":"build","state":"done"},
                      {"name":"start","state":"active","detail":"2 of 3 services up"},
                      {"name":"health","state":"pending"},{"name":"odd","state":"weird"}]}
            """
        let r = try LiveProjectsService.runState(Data(json.utf8))
        #expect(r.summary.state == .starting)
        #expect(r.steps.map(\.name) == ["pull", "build", "start", "health"])
        #expect(r.steps[2].state == .active && r.steps[2].detail == "2 of 3 services up" && r.steps[0].detail == nil)
        #expect(r.steps[2].title == "Starting the services")
        let failed = try LiveProjectsService.runState(
            Data(
                #"{"id":"r_2","state":"failed","runner":"d","spec_version":1,"started_at":"2026-11-27T10:00:00.000Z","started_by":"d","last_activity_at":"2026-11-27T10:00:00.000Z","error":"x","steps":[{"name":"build","state":"failed","detail":"npm ci exited 1"}]}"#
                    .utf8))
        #expect(failed.steps.first?.state == .failed && failed.steps.first?.detail == "npm ci exited 1")
        // An older Core says no steps.
        let old = try LiveProjectsService.runState(
            Data(json.replacingOccurrences(of: "\"steps\"", with: "\"nothing\"").utf8))
        #expect(old.steps.isEmpty)
    }

    @Test func metricsReadPerServiceHistory() throws {
        let json = """
            {"run":"r_1","samples_max":60,"every_secs":60,"services":[
              {"name":"web","samples":[{"at":"2026-11-27T10:00:00.000Z","cpu_percent":12.5,"memory_bytes":1000},
                                        {"at":"2026-11-27T10:01:00.000Z","cpu_percent":null,"memory_bytes":2000}]},
              {"name":"api","samples":[]}]}
            """
        let m = try RunWire.metrics(Data(json.utf8))
        #expect(m["web"]?.cpu == [12.5, 0] && m["web"]?.memory == [1000, 2000] && m["api"]?.cpu == [])
        #expect(try RunWire.metrics(Data(#"{"run":null,"samples_max":60,"every_secs":60,"services":[]}"#.utf8)).isEmpty)
        #expect(Sparkline.normalized([5, 10], floor: 25) == [0.2, 0.4])
        #expect(Sparkline.normalized([0, 0], floor: 0) == [0, 0])
    }

    @Test func aPatchSendsTheCoresNames() throws {
        let body = try LiveProjectsService.patchBody(ProjectPatch(name: "N", expose: false, colour: "rose"))
        let o = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(o["color"] as? String == "rose" && o["name"] as? String == "N" && o["expose"] as? Bool == false)
        #expect(o["description"] == nil)
        let clear = try LiveProjectsService.patchBody(ProjectPatch(colour: ""))
        #expect((try JSONSerialization.jsonObject(with: clear) as? [String: Any])?["color"] as? String == "")
    }

    @Test func sessionsOfAProjectAreTakenAsTheCoreFiltered() throws {
        // `GET /agent-sessions?project=7` answers only that project's rows: none is filtered out again on this side.
        let json = """
            [{"id":"s_1","harness":"claude","state":"running","runner":"d_mac","project_id":7,"title":"Fix it","last_seq":4,"created_by":"d_mac",
              "created_at":"2026-11-27T09:00:00.000Z","updated_at":"2026-11-27T10:00:00.000Z"}]
            """
        let list = try LiveProjectsService.decoder().decode(
            [Components.Schemas.AgentSession].self, from: Data(json.utf8))
        let rows = LiveProjectsService.rows(list, now: Date())
        #expect(rows.count == 1 && rows[0].title == "Fix it" && rows[0].state == .running)
    }
}

@MainActor
final class MinService: ProjectsService, @unchecked Sendable {
    var list: [ProjectItem]
    var patches: [ProjectPatch] = []
    var branches: [String] = []
    var branchError: (any Error)?
    init(_ list: [ProjectItem]) { self.list = list }
    nonisolated func projects() async throws -> [ProjectItem] { await MainActor.run { list } }
    func create(slug: String, name: String) async throws -> ProjectItem { fatalError() }
    func addRepo(project: Int64, name: String, url: String, primary: Bool) async throws {}
    func setExpose(project: Int64, _ on: Bool) async throws {}
    func update(project: Int64, patch: ProjectPatch) async throws {
        patches.append(patch)
        if let c = patch.colour, let i = list.firstIndex(where: { $0.id == project }) { list[i].colourName = c }
    }
    func setBranch(project: Int64, repo: Int64, branch: String) async throws {
        if let branchError { throw branchError }
        branches.append(branch)
    }
}

@MainActor
private func make(_ projects: [ProjectItem], core110: Bool) async -> (ProjectsModel, MinService, FakeHost) {
    let host = FakeHost()
    let m = ProjectsModel(host: host, defaults: UserDefaults(suiteName: "p110-\(UUID())")!)
    let s = MinService(projects)
    m.core110 = core110
    m.use(s)
    _ = await until { m.load == .ready }
    return (m, s, host)
}

private func item(_ id: Int64 = 1, slug: String = "tidepool", expose: Bool = false, running: Bool = true) -> ProjectItem
{
    var p = ProjectItem(
        id: id, slug: slug, name: slug.capitalized, description: "", expose: expose,
        repos: [
            RepoItem(
                id: 5, name: "\(slug)-api", remoteURL: "https://github.com/o/\(slug)-api", branch: "main",
                primary: true,
                fetchedAt: Date(), fetchError: nil)
        ], updatedAt: Date())
    if running { p.run = RunSummary(state: .running) }
    return p
}

@MainActor
struct Core110ModelTests {
    @Test func theLivePreviewIsPrivateOnANewCoreAndOtherwiseThePublicLink() async {
        let (m, _, _) = await make([item(expose: false), item(2, slug: "quill", expose: true)], core110: true)
        let fetch: PreviewFetch = { _, _, _, _ in PreviewReply(status: 200, headers: [:], body: Data()) }
        m.previewFetch = fetch
        let off = m.project(1)!
        #expect(m.previewURL(for: off)?.scheme == PreviewProxy.scheme)
        // An older Core, or no way to send: exactly as before. A private project shows nothing there; a public one its link.
        m.core110 = false
        #expect(m.previewURL(for: off) == nil)
        #expect(m.previewURL(for: m.project(2)!)?.absoluteString == "https://quill.ainkrad.io")
        m.core110 = true
        m.previewFetch = nil
        #expect(m.previewURL(for: off) == nil)
        // Not running: nothing to show.
        var stopped = off
        stopped.run = RunSummary(state: .stopped)
        m.previewFetch = fetch
        #expect(m.previewURL(for: stopped) == nil)
    }

    @Test func theColourOfTheCoreWinsOverThisMacsAndAnOlderCoreKeepsItLocal() async {
        var p = item()
        p.colourName = "rose"
        let (m, s, _) = await make([p], core110: true)
        #expect(m.colour(m.project(1)!) == .rose)
        // Picking one saves it on the Core.
        m.setColour(.teal, for: m.project(1)!)
        #expect(await until { s.patches.contains { $0.colour == "teal" } })
        #expect(await until { m.colour(m.project(1)!) == .teal })
        // An older Core: a choice of this Mac, no call.
        let (old, os, _) = await make([item()], core110: false)
        old.setColour(.violet, for: old.project(1)!)
        #expect(old.colour(old.project(1)!) == .violet && os.patches.isEmpty)
    }

    @Test func coloursPickedOnThisMacGoUpOnceWhereTheCoreHasNone() async {
        let (m, s, host) = await make([item(1, slug: "tidepool"), item(2, slug: "quill")], core110: false)
        m.colours.set(.copper, for: "tidepool")
        var withColour = item(2, slug: "quill")
        withColour.colourName = "green"
        s.list[1] = withColour
        m.colours.set(.violet, for: "quill")
        m.core110 = true
        await m.reload()
        // A plain reload never asks for Touch ID; the migration rides a write the person gave it for.
        try? await Task.sleep(for: .milliseconds(100))
        #expect(!m.colours.migrated && s.patches.isEmpty)
        await m.migrateColours()
        #expect(await until { m.colours.migrated })
        #expect(s.patches.map(\.colour) == ["copper"])
        #expect(host.reasons.last?.contains("colours you picked") == true)
        // Done: a later start asks nothing.
        let before = s.patches.count
        await m.migrateColours()
        #expect(s.patches.count == before)
    }

    @Test func declinedMigrationIsNotAskedAgainThisSessionNorMarkedDone() async {
        let (m, s, host) = await make([item()], core110: false)
        m.colours.set(.copper, for: "tidepool")
        host.declines = true
        m.core110 = true
        await m.migrateColours()
        await m.migrateColours()
        #expect(!m.colours.migrated && s.patches.isEmpty && host.reasons.count == 1)
    }

    @Test func aRepoChangesBranchOrSaysWhyNot() async {
        let (m, s, host) = await make([item()], core110: true)
        let p = m.project(1)!
        let r = p.repos[0]
        #expect(await m.changeBranch(p, r, to: " development "))
        #expect(s.branches == ["development"] && host.shell.toast?.message == "tidepool-api follows development")
        s.branchError = CoreError.badRequest(message: "no such branch")
        #expect(!(await m.changeBranch(p, r, to: "nope")))
        #expect(
            m.writeError
                == "The Core’s copy of tidepool-api has no branch called “nope”. Check the name, or fetch the repo first."
        )
        s.branchError = CoreError.http(status: 409, code: "not_fetched", message: "x")
        #expect(!(await m.changeBranch(p, r, to: "next")))
        #expect(m.writeError?.contains("has not copied") == true)
        s.branchError = CoreError.http(status: 503, code: "busy", message: "x")
        #expect(!(await m.changeBranch(p, r, to: "next")))
        #expect(m.writeError == "The Core is busy right now. Try again in a moment.")
        // Nothing sent for a bad name, the same branch, or an older Core.
        s.branchError = nil
        let sent = s.branches.count
        #expect(!(await m.changeBranch(p, r, to: "a b")))
        #expect(await m.changeBranch(p, r, to: "main"))
        m.core110 = false
        #expect(!(await m.changeBranch(p, r, to: "other")))
        #expect(s.branches.count == sent)
        #expect(ProjectsModel.branchProblem("") != nil && ProjectsModel.branchProblem("feat/x-1") == nil)
    }

    @Test func aCrashIsAToastWithOpenLogsAndABadgeUntilItRunsAgain() async {
        let (m, _, host) = await make([item()], core110: true)
        let fields = [
            "id": "1", "run": "r_1", "service": "api", "exit_code": "137", "restarts": "3", "config": "web",
            "environment": "development",
        ]
        m.serviceCrashed(fields)
        let t = host.shell.toast
        #expect(t?.actionTitle == "Open logs" && t?.kind == .warn && t?.undo != nil)
        #expect(t?.message == "Tidepool: api crashed (exit code 137, restarted 3 times)")
        let p = m.project(1)!
        #expect(p.crash?.service == "api" && p.badge.label == "Crashed" && p.subtitle.hasPrefix("api crashed"))
        t?.undo?()
        #expect(m.section == .run)
        // It ran again after the crash: the badge goes.
        m.runStates[1] = ProjectRunState(summary: RunSummary(state: .running), startedAt: Date().addingTimeInterval(60))
        m.reapply(1)
        #expect(m.project(1)?.crash == nil && m.project(1)?.badge.label == "Running")
        // Older Core, or a payload without a service: nothing.
        m.crashes = [:]
        m.core110 = false
        m.serviceCrashed(fields)
        #expect(m.crashes.isEmpty)
        m.core110 = true
        m.serviceCrashed(["id": "1"])
        #expect(m.crashes.isEmpty)
    }

    @Test func startStepsAreTheCoresOwnAndNothingIsGuessed() async {
        let (m, _, _) = await make([item(running: false)], core110: true)
        m.runStates[1] = ProjectRunState(
            summary: RunSummary(state: .starting), startedAt: Date(), runner: nil,
            steps: [
                RunStep(name: "pull", state: .done, detail: nil),
                RunStep(name: "start", state: .active, detail: "2 of 3 services up"),
            ])
        m.reapply(1)
        let live = m.project(1)?.live
        #expect(live?.steps.map(\.state) == [.done, .active] && live?.steps[1].detail == "2 of 3 services up")
        #expect(live?.progressLine.hasSuffix("2 of 3 services up") == true)
        m.runStates[1] = ProjectRunState(summary: RunSummary(state: .starting), startedAt: Date())
        m.reapply(1)
        #expect(m.project(1)?.live?.steps.isEmpty == true)
    }
}
