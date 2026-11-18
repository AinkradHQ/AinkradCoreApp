import Foundation
import WebKit

// SECURITY MODEL (V3-07, T10; security-flagged, needs an independent review).
//
// A mockup package is UNTRUSTED HTML + JS (a builder or an AI session wrote it). Its own JS runs, so click-through
// works, but it must never reach the network, the app, the disk or another page. Layers, outermost first:
//
//  1. Content rule list (`rules`): blocks EVERY load (http, https, ws, wss, file, data, blob, ftp, about…) except
//     `mockup://package/…`. Compiled by WebKit, so it also covers fetch, XHR, img, css url(), WebSocket, EventSource
//     and beacons. If it fails to compile the web view is NOT built (fail closed).
//  2. Scheme handler (`MockupSchemeHandler`): `mockup://package/<path>` is served ONLY from the package's own file list
//     (the Core's manifest), by validated path, case-insensitive like the Core. The type comes from the extension and
//     the same allow-list the Core enforces, never from the bytes; anything else is 404. Nothing is read from disk.
//  3. CSP (sent as a header on every response): `default-src 'none'`, `connect-src 'none'` (no fetch/XHR/WebSocket even
//     to the package), `frame-src 'none'`, `object-src 'none'`, `base-uri 'none'`, `form-action 'none'`; scripts,
//     styles, images and fonts only from `mockup:`. Inline script/style stay allowed (the mockups are single files).
//  4. NO script message handler is ever added, so `window.webkit` is absent: the page cannot call into the app. The one
//     user script (`hardening`, document start, every frame) only REMOVES things: the WebRTC constructors and the
//     `preconnect|dns-prefetch|prefetch|preload` link hints. WebRTC is also switched off in the preferences
//     (private `_peerConnectionEnabled`, set only if this SDK has it) because ICE/TURN opens sockets the content rules
//     never see.
//  5. Navigation (`MockupNavigation`): only `mockup://package/<html file of the package>` may load; every other
//     navigation, download and new window is cancelled. Clicking a link to the outside does nothing.
//  6. Non-persistent data store (no cookies, storage or cache on disk), no popups, no link preview, no inspector.
//
// ACCEPTED LIMITS. (a) A page can write to the clipboard on a user click (a normal gesture-gated web API); it cannot
// read it. (b) The test canary is a loopback TCP listener: it cannot observe DNS lookups or UDP, so the link-hint
// stripping and the WebRTC removal are belt and braces that the canary alone cannot prove. (c) Camera/microphone
// requests are denied by the UI delegate.
//
// The Core serves package files as inert attachments from its own origin; this viewer is the only place they render.

/// The files of one sealed package, from the Core's `PackageView`.
struct MockupPackage: Equatable, Sendable {
    struct Screen: Equatable, Sendable, Identifiable {
        var id: String { path }
        let name: String
        let path: String
        let states: [String]
    }
    let doc: String
    let screens: [Screen]
    /// Every file path of the package (as the Core stores it).
    let files: [String]

    /// Lower-cased path to the Core's spelling; the Core compares paths case-insensitively.
    var index: [String: String] { Dictionary(files.map { ($0.lowercased(), $0) }, uniquingKeysWith: { a, _ in a }) }
}

/// Where a package's bytes come from: the Core (live) or a folder in a test.
protocol MockupSource: Sendable {
    func package(_ doc: String) async throws -> MockupPackage
    func file(_ doc: String, path: String) async throws -> Data
}

enum MockupSandbox {
    static let scheme = "mockup"
    static let host = "package"
    /// The same cap the Core enforces on one file.
    static let maxFileBytes = 25 * 1024 * 1024

    static let csp = [
        "default-src 'none'", "script-src mockup: 'unsafe-inline'", "style-src mockup: 'unsafe-inline'",
        "img-src mockup:", "font-src mockup:", "media-src mockup:", "connect-src 'none'", "frame-src 'none'",
        "object-src 'none'", "base-uri 'none'", "form-action 'none'",
    ].joined(separator: "; ")

    /// Block everything, then lift the block for the package's own URLs. Order matters: a later
    /// `ignore-previous-rules` wins over the earlier `block`.
    static let rules = """
        [{"trigger":{"url-filter":".*"},"action":{"type":"block"}},
         {"trigger":{"url-filter":"^mockup://package/"},"action":{"type":"ignore-previous-rules"}}]
        """

    /// The one content type per extension (the Core's allow-list). nil = never served.
    static func contentType(_ path: String) -> String? {
        switch (path as NSString).pathExtension.lowercased() {
        case "html": "text/html; charset=utf-8"
        case "css": "text/css; charset=utf-8"
        case "js": "text/javascript; charset=utf-8"
        case "json": "application/json; charset=utf-8"
        case "svg": "image/svg+xml"
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "webp": "image/webp"
        case "gif": "image/gif"
        default: nil
        }
    }

    /// A package path from a URL path, or nil: relative, at most 200 bytes, no `.`/`..`/empty/hidden segment, no
    /// backslash, NUL or control character. Mirrors the Core's `valid_path`.
    static func clean(_ urlPath: String) -> String? {
        guard urlPath.hasPrefix("/") else { return nil }
        let rel = String(urlPath.dropFirst())
        guard !rel.isEmpty, rel.utf8.count <= 200 else { return nil }
        for scalar in rel.unicodeScalars where scalar.value < 0x20 || scalar.value == 0x7F || scalar == "\\" {
            return nil
        }
        for part in rel.split(separator: "/", omittingEmptySubsequences: false) {
            if part.isEmpty || part.hasPrefix(".") { return nil }
        }
        return rel
    }

    /// The package path a `mockup://package/…` URL names, if it is one and is in `index`.
    static func resolve(_ url: URL?, index: [String: String]) -> String? {
        guard let url, url.scheme == scheme, url.host == host, url.port == nil, url.user == nil, url.password == nil,
            let path = clean(url.path)
        else { return nil }
        return index[path.lowercased()]
    }

    /// Whether the page may navigate to `url`: an HTML file of the package, nothing else.
    static func allowsNavigation(_ url: URL?, index: [String: String]) -> Bool {
        guard let path = resolve(url, index: index) else { return false }
        return (path as NSString).pathExtension.lowercased() == "html"
    }

    static func url(_ path: String, state: String? = nil) -> URL? {
        var c = URLComponents()
        c.scheme = scheme
        c.host = host
        c.percentEncodedPath =
            "/"
            + path.split(separator: "/").map {
                String($0).addingPercentEncoding(
                    withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/")))
                    ?? ""
            }.joined(separator: "/")
        c.fragment = state
        return c.url
    }

    /// Compiles the content rules. Throws when WebKit refuses them; the caller must then not show the page.
    @MainActor static func ruleList() async throws -> WKContentRuleList {
        guard
            let list = try await WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "ainkrad.mockup.v1", encodedContentRuleList: rules)
        else { throw MockupFailure.noRules }
        return list
    }

    /// Document-start script for every frame: removes WebRTC and the network-warming link hints.
    static let hardening = """
        (() => {
          for (const n of ["RTCPeerConnection", "webkitRTCPeerConnection", "RTCDataChannel"]) {
            try { delete window[n]; } catch (e) {}
            if (typeof window[n] !== "undefined") {
              try { Object.defineProperty(window, n, { value: undefined, configurable: false }); } catch (e) {}
            }
          }
          const bad = /^(preconnect|dns-prefetch|prefetch|preload|prerender|modulepreload)$/i;
          const strip = (l) => {
            if (!l.localName || l.localName !== "link") return;
            const was = l.getAttribute("rel") || "";
            const rel = was.split(/\\s+/).filter((x) => !bad.test(x)).join(" ");
            if (rel !== was) l.setAttribute("rel", rel || "x-blocked");
          };
          new MutationObserver((ms) => {
            for (const m of ms) {
              if (m.type === "attributes") strip(m.target);
              for (const a of m.addedNodes) if (a.querySelectorAll) { strip(a); a.querySelectorAll("link").forEach(strip); }
            }
          }).observe(document, { childList: true, subtree: true, attributes: true, attributeFilter: ["rel"] });
        })();
        """

    /// The sandboxed web view of one package. Fails closed: no rules, no web view.
    @MainActor static func makeWebView(
        handler: MockupSchemeHandler, navigation: MockupNavigation
    ) async throws -> WKWebView {
        let rules = try await ruleList()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(handler, forURLScheme: scheme)
        config.userContentController.add(rules)
        // No `add(_:name:)` anywhere: the page has no way into the app. The user script only removes features.
        config.userContentController.addUserScript(
            WKUserScript(source: hardening, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        // Private key: guarded, because KVC on an unknown key raises an NSException.
        if config.preferences.responds(to: NSSelectorFromString("_setPeerConnectionEnabled:")) {
            config.preferences.setValue(false, forKey: "_peerConnectionEnabled")
        }
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.mediaTypesRequiringUserActionForPlayback = .all
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = navigation
        web.uiDelegate = navigation
        web.allowsBackForwardNavigationGestures = false
        web.allowsLinkPreview = false
        web.isInspectable = false
        return web
    }
}

enum MockupFailure: Error, Equatable, Sendable {
    case noRules
    case notSealed
    case noScreen
    case core(String)

    var sentence: String {
        switch self {
        case .noRules: "The mockup is not shown because its safety rules could not be loaded."
        case .notSealed: "This mockup package is still a draft. Seal it to review it."
        case .noScreen: "This mockup package has no page to show."
        case .core(let s): s
        }
    }
}

/// Serves `mockup://package/<path>` from the package and nothing else.
@MainActor
final class MockupSchemeHandler: NSObject, WKURLSchemeHandler {
    let doc: String
    let index: [String: String]
    let source: any MockupSource
    /// Test-only: false drops the CSP header so a test can prove the content rules alone hold. Always true in the app.
    let sendCSP: Bool
    private var running: [ObjectIdentifier: Task<Void, Never>] = [:]

    init(package: MockupPackage, source: any MockupSource, sendCSP: Bool = true) {
        self.sendCSP = sendCSP
        doc = package.doc
        index = package.index
        self.source = source
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        let key = ObjectIdentifier(task)
        let request = task.request
        guard request.httpMethod == "GET" || request.httpMethod == nil,
            let path = MockupSandbox.resolve(request.url, index: index),
            let type = MockupSandbox.contentType(path), let url = request.url
        else { return fail(task, status: 404, url: task.request.url) }
        running[key] = Task { @MainActor [doc, source] in
            defer { running[key] = nil }
            guard let data = try? await source.file(doc, path: path), data.count <= MockupSandbox.maxFileBytes,
                !Task.isCancelled
            else { return fail(task, status: 404, url: url, cancelled: Task.isCancelled) }
            guard !Task.isCancelled else { return }
            var head: [String: String] = [
                "Content-Type": type, "Content-Length": String(data.count),
                "X-Content-Type-Options": "nosniff", "Cache-Control": "no-store",
                "Cross-Origin-Resource-Policy": "same-origin",
            ]
            if sendCSP { head["Content-Security-Policy"] = MockupSandbox.csp }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: head)
            task.didReceive(
                response
                    ?? URLResponse(url: url, mimeType: type, expectedContentLength: data.count, textEncodingName: nil))
            task.didReceive(data)
            task.didFinish()
        }
    }

    /// WebKit calls this when it no longer wants the task; answering a stopped task would crash, so cancel and forget.
    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {
        let key = ObjectIdentifier(task)
        running[key]?.cancel()
        running[key] = nil
    }

    private func fail(_ task: any WKURLSchemeTask, status: Int, url: URL?, cancelled: Bool = false) {
        if cancelled { return }
        let u = url ?? URL(string: "\(MockupSandbox.scheme)://\(MockupSandbox.host)/")!
        let head = ["Content-Type": "text/plain", "Content-Security-Policy": MockupSandbox.csp]
        task.didReceive(HTTPURLResponse(url: u, statusCode: status, httpVersion: "HTTP/1.1", headerFields: head)!)
        task.didReceive(Data())
        task.didFinish()
    }
}

/// Keeps the page inside the package: cancels every navigation, download and new window that is not an HTML file of it.
@MainActor
final class MockupNavigation: NSObject, WKNavigationDelegate, WKUIDelegate {
    let index: [String: String]
    /// The package path of the page now shown (after a click-through).
    var onPage: (String) -> Void = { _ in }
    /// A navigation that was cancelled; for the viewer's quiet "Blocked a link" line.
    var onBlocked: (URL?) -> Void = { _ in }

    init(package: MockupPackage) { index = package.index }

    func webView(
        _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        if !action.shouldPerformDownload, MockupSandbox.allowsNavigation(action.request.url, index: index) {
            decisionHandler(.allow)
        } else {
            onBlocked(action.request.url)
            decisionHandler(.cancel)
        }
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
        decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(response.canShowMIMEType ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if let path = MockupSandbox.resolve(webView.url, index: index) { onPage(path) }
    }

    /// No new windows: a `target=_blank` link or `window.open` gets nothing.
    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for action: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        onBlocked(action.request.url)
        return nil
    }

    /// Camera and microphone are never available to a mockup.
    func webView(
        _ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void
    ) {
        decisionHandler(.deny)
    }
}
