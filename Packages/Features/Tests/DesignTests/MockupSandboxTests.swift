import Foundation
import Network
import ObjectiveC
import Testing
import WebKit

@testable import Design

/// A package served from the `Fixtures/hostile-mockup` folder; `__PORT__` becomes the canary's port.
struct FixtureSource: MockupSource {
    let port: UInt16
    static let names = ["index.html", "style.css", "probe.js", "next.html", "local.json", "worker.js"]

    func package(_ doc: String) async throws -> MockupPackage {
        MockupPackage(doc: doc, screens: [.init(name: "index", path: "index.html", states: [])], files: Self.names)
    }

    func file(_ doc: String, path: String) async throws -> Data {
        guard Self.names.contains(path),
            let url = Bundle.module.url(forResource: "Fixtures/hostile-mockup/\(path)", withExtension: nil),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { throw MockupFailure.core("missing") }
        return Data(text.replacingOccurrences(of: "__PORT__", with: String(port)).utf8)
    }
}

/// A local listener standing in for "the network": every connection to it is a request that got out.
final class Canary: @unchecked Sendable {
    private let listener: NWListener
    private let lock = NSLock()
    private var count = 0
    private(set) var port: UInt16 = 0

    init() async throws {
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [weak self] c in
            self?.lock.withLock { self?.count += 1 }
            c.cancel()
        }
        let ready = AsyncStream<UInt16> { k in
            listener.stateUpdateHandler = { [listener] s in
                if case .ready = s { k.yield(listener.port?.rawValue ?? 0) }
            }
        }
        listener.start(queue: .global())
        for await p in ready {
            port = p
            break
        }
    }
    var connections: Int { lock.withLock { count } }
    func stop() { listener.cancel() }
}

@MainActor
struct MockupSandboxTests {
    @Test func pathsAreCleanedLikeTheCore() {
        #expect(MockupSandbox.clean("/index.html") == "index.html")
        #expect(MockupSandbox.clean("/a/b.css") == "a/b.css")
        for bad in [
            "", "/", "index.html", "/../x", "/a/../x", "/./x", "//x", "/a//b", "/.hidden", "/a/.git/x", "/a\\b",
            "/a\0b", "/a\nb",
        ] {
            #expect(MockupSandbox.clean(bad) == nil, "\(bad.debugDescription)")
        }
        #expect(MockupSandbox.clean("/" + String(repeating: "a", count: 201)) == nil)
    }

    @Test func onlyTheOwnHtmlPagesMayBeNavigatedTo() {
        let index = ["index.html": "index.html", "app.js": "app.js", "ui/next.html": "ui/Next.html"]
        func ok(_ s: String) -> Bool { MockupSandbox.allowsNavigation(URL(string: s), index: index) }
        #expect(ok("mockup://package/index.html"))
        #expect(ok("mockup://package/index.html#night"))
        #expect(ok("mockup://package/ui/NEXT.html"), "the Core compares paths case-insensitively")
        #expect(!ok("mockup://package/app.js"), "a script is not a page")
        #expect(!ok("mockup://package/missing.html"))
        #expect(!ok("mockup://other/index.html"))
        #expect(!ok("mockup://package:8080/index.html"))
        #expect(!ok("mockup://user@package/index.html"))
        #expect(!ok("mockup://package/../index.html"))
        for s in [
            "http://127.0.0.1/index.html", "https://example.com/", "file:///etc/hosts", "data:text/html,x",
            "about:blank", "javascript:1", "ws://x/",
        ] {
            #expect(!ok(s), "\(s)")
        }
        #expect(!MockupSandbox.allowsNavigation(nil, index: index))
    }

    @Test func onlyAllowListedTypesAreServed() {
        #expect(MockupSandbox.contentType("a.HTML") == "text/html; charset=utf-8")
        #expect(MockupSandbox.contentType("a.exe") == nil)
        #expect(MockupSandbox.contentType("a") == nil)
        #expect(MockupSandbox.csp.contains("connect-src 'none'"))
        #expect(!MockupSandbox.csp.contains("http"))
    }

    /// The private switches really read back as off after `lockDownNetworkPreferences`.
    @MainActor @Test func theNetworkSwitchesReadBackOff() throws {
        let prefs = WKPreferences()
        try MockupSandbox.lockDownNetworkPreferences(prefs)
        if prefs.responds(to: NSSelectorFromString("_peerConnectionEnabled")) {
            #expect(prefs.value(forKey: "_peerConnectionEnabled") as? Bool == false, "WebRTC switch")
        }
        let list = NSSelectorFromString("_features")
        let get = NSSelectorFromString("_isEnabledForFeature:")
        if (WKPreferences.self as AnyObject).responds(to: list), prefs.responds(to: get),
            let m = class_getInstanceMethod(WKPreferences.self, get),
            let all = (WKPreferences.self as AnyObject).perform(list)?.takeUnretainedValue() as? [NSObject],
            let feature = all.first(where: { ($0.value(forKey: "key") as? String) == "LinkPreconnect" })
        {
            typealias Fn = @convention(c) (AnyObject, Selector, AnyObject) -> Bool
            let on = unsafeBitCast(method_getImplementation(m), to: Fn.self)(prefs, get, feature)
            #expect(!on, "LinkPreconnect feature switch")
        }
    }

    @Test func theRuleListCompiles() async throws {
        _ = try await MockupSandbox.ruleList()
    }

    /// Loads the hostile package in the real sandbox. Every probe must fail, the canary must see nothing, the page
    /// must have no bridge and must stay inside the package, while an in-package link still clicks through.
    /// Pass 1 has the CSP; pass 2 has NO CSP header, so the content rules and the hardening script must hold alone.
    @Test(arguments: [true, false]) func theHostilePackageReachesNothing(csp: Bool) async throws {
        let canary = try await Canary()
        defer { canary.stop() }
        let source = FixtureSource(port: canary.port)
        let pkg = try await source.package("dd_test")
        let nav = MockupNavigation(package: pkg)
        var blocked = 0
        nav.onBlocked = { _ in blocked += 1 }
        let web = try await MockupSandbox.makeWebView(
            handler: MockupSchemeHandler(package: pkg, source: source, sendCSP: csp), navigation: nav)
        web.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        web.load(URLRequest(url: MockupSandbox.url("index.html")!))

        let json = try await poll(
            web, "document.body && document.body.dataset.done === '1' ? document.body.dataset.result : null")
        let r = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        for k in [
            "fetch", "fetchNoCors", "xhr", "ws", "img", "eventSource", "worker", "fileFetch", "otherFetch", "dotsFetch",
        ] {
            #expect(r[k] as? String == "blocked", "\(k) (csp \(csp))")
        }
        if csp { #expect(r["fetchPackage"] as? String == "blocked", "CSP connect-src 'none'") }
        #expect(r["beacon"] as? String != "reached")
        #expect(r["webkit"] as? String == "none", "no webkit.messageHandlers")
        #expect(r["handlers"] as? Int == 0)
        for k in ["rtc", "webkitRtc", "rtcData", "frameRtc", "frameWebkitRtc"] {
            #expect(r[k] as? String == "undefined", "\(k) must be removed")
        }
        #expect(r["openBlank"] as? String == "none")
        // Is the CSP really on (pass 1) or really off (pass 2)? Without this a header typo would pass silently.
        #expect(r["eval"] as? String == (csp ? "blocked" : "allowed"))

        try await Task.sleep(for: .milliseconds(800))
        #expect(canary.connections == 0, "a request reached the network (csp \(csp))")
        let body =
            try await web.evaluateJavaScript(
                "JSON.stringify([document.body.dataset.violations, document.body.dataset.fileImg || ''])"
            ) as? String
        let extra = try #require(
            try JSONSerialization.jsonObject(with: Data((body ?? "[]").utf8)) as? [String])
        if csp {
            #expect((Int(extra[0]) ?? 0) > 0, "securitypolicyviolation events fired")
        } else {
            #expect(extra[0] == "0")
        }
        #expect(extra[1] != "reached", "file:// image")
        #expect(web.url?.host == MockupSandbox.host && web.url?.scheme == MockupSandbox.scheme)
        #expect(web.url?.path == "/index.html", "still on the first page after every navigation attempt")
        #expect(blocked > 0, "the delegate saw and cancelled the attempts")

        // Click-through inside the package still works.
        _ = try await web.evaluateJavaScript("document.getElementById('in').click(); 1")
        _ = try await poll(web, "location.pathname === '/next.html' ? 'ok' : null")
        #expect(canary.connections == 0)
    }

    private func poll(_ web: WKWebView, _ js: String) async throws -> String {
        for _ in 0..<100 {
            if let v = try? await web.evaluateJavaScript(js) as? String { return v }
            try await Task.sleep(for: .milliseconds(100))
        }
        Issue.record("timed out waiting for: \(js)")
        throw MockupFailure.core("timeout")
    }
}
