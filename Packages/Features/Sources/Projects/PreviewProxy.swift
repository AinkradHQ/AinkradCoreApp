import CoreKit
import Foundation
import WebKit

// The private live preview (API minor 110). The running app is shown through `GET /api/v1/projects/{id}/preview/{path}`, an
// ordinary signed route, from the app's own URL scheme: every request the page makes, sub-resources included, is signed by
// this Mac exactly like any other call (`CoreConnection.signedExchange`), so no token, cookie or signed link ever exists for the
// page to leak, and the project's HTML never runs under the Core's web origin.
//
// SECURITY RULES of the handler (the coordinator's review list):
//  a. Authorization, Origin, Cookie and Referer of the web view's request are never forwarded: only an allow-list of plain
//     headers is, and cookies come from the project's own jar.
//  b. Redirects are never followed by the transport. The handler follows one only when it stays inside this project's preview
//     of the same Core; anything else stops with "The app redirected outside Ainkrad."
//  c. Cookies live in one jar per web view (per project), in memory, and are sent on that project's preview requests only.
//  d. The Core session is ephemeral with no cache and no cookie storage (CoreKit `makeCoreSession`).
//  e. Bodies and headers (CSP, CORP) pass through untouched, apart from the hop-by-hop ones URLSession already resolved.

/// One answer of the preview route, any status.
struct PreviewReply: Sendable, Equatable {
    var status: Int
    /// Header names in lower case.
    var headers: [String: String]
    var body: Data
}

/// Sends one signed request to the preview route: method, target (path and raw query), plain headers, body.
typealias PreviewFetch = @Sendable (String, String, [String: String], Data) async throws -> PreviewReply

enum PreviewProxy {
    /// The sandbox the Core puts on every preview answer (`preview::SANDBOX`) so a browser rendering it under the Core's own
    /// host gets no origin. This app renders previews under its own scheme (its own origin), so it drops exactly this value
    /// and keeps any policy the project sent; otherwise the page would lose its storage and its own-site requests here.
    static let coreSandbox =
        "sandbox allow-scripts allow-forms allow-popups allow-modals allow-downloads; frame-ancestors 'none'"

    /// The CSP header without the Core's sandbox: several CSP headers arrive joined by ", ".
    static func withoutCoreSandbox(_ csp: String?) -> String? {
        guard let csp else { return nil }
        let rest = csp.components(separatedBy: ", ").filter {
            $0.trimmingCharacters(in: .whitespaces) != coreSandbox
        }
        let joined = rest.joined(separator: ", ")
        return joined.isEmpty ? nil : joined
    }

    static let scheme = "ainkrad-preview"
    static let host = "project"
    static let outsideWords = "The app redirected outside Ainkrad."

    /// The page's address in the web view: the root of the project's preview.
    static func url(path: String = "/") -> URL? { URL(string: "\(scheme)://\(host)\(path)") }

    static func base(_ project: Int64) -> String { "/api/v1/projects/\(project)/preview" }

    /// The signed target for a URL of the scheme: the project's preview path, the page's path with upper-case percent escapes,
    /// and the query as it is. nil for another scheme or host, or a path that could climb out of the preview.
    static func target(project: Int64, for url: URL) -> String? {
        guard url.scheme == scheme, url.host == host,
            let c = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        let path = c.percentEncodedPath.isEmpty ? "/" : c.percentEncodedPath
        guard path.hasPrefix("/"), safe(path) else { return nil }
        return base(project) + upperEscapes(path) + (c.percentEncodedQuery.map { "?" + upperEscapes($0) } ?? "")
    }

    /// No `.` or `..` segment (also when percent-escaped), no escaped slash or backslash, no control character.
    static func safe(_ path: String) -> Bool {
        for seg in path.split(separator: "/", omittingEmptySubsequences: false) {
            guard let d = String(seg).removingPercentEncoding else { return false }
            if d == "." || d == ".." || d.contains("/") || d.contains("\\") { return false }
            if d.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) { return false }
        }
        return true
    }

    /// `%2f` becomes `%2F`: the Core signs and compares the path as sent, and says upper-case.
    static func upperEscapes(_ s: String) -> String {
        var out = ""
        var chars = Array(s)[...]
        while let c = chars.first {
            chars = chars.dropFirst()
            if c == "%", chars.count >= 2, chars.prefix(2).allSatisfy(\.isHexDigit) {
                out += "%" + String(chars.prefix(2)).uppercased()
                chars = chars.dropFirst(2)
            } else {
                out.append(c)
            }
        }
        return out
    }

    /// The only request headers that go to the Core (lower-case). Never Authorization, Origin, Cookie or Referer.
    static let forwarded: Set<String> = ["accept", "accept-language", "content-type", "range"]

    static func headers(from request: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in request where forwarded.contains(k.lowercased()) { out[k.lowercased()] = v }
        return out
    }

    /// Answer headers the web view must not get again: the transport already decoded the body and framed it.
    static let dropped: Set<String> = [
        "set-cookie", "content-encoding", "content-length", "transfer-encoding", "connection", "keep-alive",
    ]

    // MARK: the Core's own words

    /// What the Core says when it cannot show the app (409 `not_running` / `no_preview`, 502, 503 `busy`, 504), in plain words;
    /// nil for the running app's own answer.
    static func problem(_ r: PreviewReply) -> String? {
        let body = (try? JSONSerialization.jsonObject(with: r.body)) as? [String: Any]
        let code = body?["code"] as? String
        let said = body?["message"] as? String
        switch (r.status, code) {
        case (409, "not_running"): return said ?? "The project is not running. Start it to see it here."
        case (409, "no_preview"):
            return said ?? "None of the project's services has a web port to show. Expose one in its setup."
        case (503, "busy"): return "The app is busy with other requests. Try again in a moment."
        case (502, _) where code != nil:
            return "The machine running the project did not answer. Try again in a moment."
        case (504, _) where code != nil: return "The app did not answer in 25 seconds."
        default: return nil
        }
    }

    static func retryAfter(_ r: PreviewReply) -> TimeInterval {
        min(3, max(0.2, TimeInterval(r.headers["retry-after"] ?? "") ?? 1))
    }

    // MARK: redirects

    enum Redirect: Equatable {
        case follow(URL)
        case outside
    }

    /// Where a 3xx `location` goes. Followed only inside this project's preview: a path (relative or absolute) is the app's own
    /// path, always under this project; an absolute address must be this scheme, or the same Core with this project's preview
    /// prefix. Anything else (another site, another project's route, `//host`) is outside.
    static func redirect(location: String, from current: URL, project: Int64, coreHost: String?) -> Redirect {
        guard let c = URLComponents(string: location) else { return .outside }
        if c.scheme == nil, c.host == nil {
            guard let u = URL(string: location, relativeTo: current),
                var r = URLComponents(url: u, resolvingAgainstBaseURL: true)
            else { return .outside }
            r.scheme = scheme
            r.host = host
            return finish(r, strip: base(project))
        }
        guard let h = c.host?.lowercased(), c.user == nil, c.password == nil else { return .outside }
        if c.scheme == scheme, h == host { return finish(c, strip: nil) }
        guard c.scheme == "https" || c.scheme == "http", let core = coreHost?.lowercased(),
            h == core || "\(h):\(c.port ?? 0)" == core
        else { return .outside }
        let prefix = base(project)
        guard c.percentEncodedPath == prefix || c.percentEncodedPath.hasPrefix(prefix + "/") else { return .outside }
        var r = c
        r.scheme = scheme
        r.host = host
        r.port = nil
        return finish(r, strip: prefix)
    }

    private static func finish(_ parts: URLComponents, strip prefix: String?) -> Redirect {
        var c = parts
        c.scheme = scheme
        c.host = host
        c.port = nil
        var path = c.percentEncodedPath
        if let prefix, path == prefix || path.hasPrefix(prefix + "/") { path = String(path.dropFirst(prefix.count)) }
        c.percentEncodedPath = path.isEmpty ? "/" : path
        c.fragment = nil
        guard let url = c.url, safe(c.percentEncodedPath) else { return .outside }
        return .follow(url)
    }
}

/// The cookies of one project's preview, in memory: `name=value` pairs of what the app set, sent back on that project's
/// preview requests only. Host-only, so no path or domain matching. (An app that sets several cookies in one answer arrives
/// joined with commas; the parts are told apart by their `name=`.)
struct PreviewCookieJar: Equatable {
    private(set) var cookies: [String: String] = [:]

    mutating func store(setCookie header: String?) {
        guard let header else { return }
        var pieces: [String] = []
        for part in header.components(separatedBy: ", ") {
            let name = part.prefix { $0 != ";" && $0 != "=" }
            if !pieces.isEmpty, !(part.contains("=") && !name.contains(" ")) {
                pieces[pieces.count - 1] += ", " + part  // a date inside Expires
            } else {
                pieces.append(part)
            }
        }
        for piece in pieces {
            let attrs = piece.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let first = attrs.first, let eq = first.firstIndex(of: "=") else { continue }
            let name = String(first[..<eq])
            let value = String(first[first.index(after: eq)...])
            let lower = attrs.map { $0.lowercased() }
            let gone =
                lower.contains("max-age=0") || lower.contains { $0.hasPrefix("max-age=-") }
                || lower.contains { $0.hasPrefix("expires=") && $0.contains("1970") }
            if gone { cookies[name] = nil } else if !name.isEmpty { cookies[name] = value }
        }
    }

    /// The `Cookie` header, nil when the jar is empty.
    var header: String? {
        cookies.isEmpty
            ? nil : cookies.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
    }
}

/// Serves `ainkrad-preview://project/<path>` from the project's preview route, signed.
@MainActor
final class PreviewSchemeHandler: NSObject, WKURLSchemeHandler {
    let project: Int64
    let fetch: PreviewFetch
    let coreHost: String?
    /// The page itself could not be shown: the Core's words (409, 502, 503 after retries, 504, the Core unreachable).
    var onProblem: (String) -> Void = { _ in }
    private(set) var jar = PreviewCookieJar()
    private var running: [ObjectIdentifier: Task<Void, Never>] = [:]
    static let maxHops = 5

    init(project: Int64, coreHost: String?, fetch: @escaping PreviewFetch) {
        self.project = project
        self.coreHost = coreHost
        self.fetch = fetch
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        let key = ObjectIdentifier(task)
        let request = task.request
        guard let url = request.url, PreviewProxy.target(project: project, for: url) != nil else {
            return fail(task, status: 404, url: request.url, text: "Not found.")
        }
        let isPage =
            request.mainDocumentURL == url || (request.value(forHTTPHeaderField: "Accept") ?? "").contains("text/html")
        running[key] = Task { @MainActor [weak self] in
            await self?.serve(task, request, url, isPage: isPage)
            self?.running[key] = nil
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {
        let key = ObjectIdentifier(task)
        running[key]?.cancel()
        running[key] = nil
    }

    private func serve(_ task: any WKURLSchemeTask, _ request: URLRequest, _ start: URL, isPage: Bool) async {
        var current = start
        var method = request.httpMethod ?? "GET"
        var body = Self.body(of: request)
        let plain = PreviewProxy.headers(from: request.allHTTPHeaderFields ?? [:])
        var hops = 0
        while true {
            guard let target = PreviewProxy.target(project: project, for: current) else {
                return fail(task, status: 404, url: current, text: "Not found.")
            }
            var headers = plain
            if let c = jar.header { headers["cookie"] = c }
            let reply: PreviewReply
            do { reply = try await Self.send(fetch, method, target, headers, body) } catch {
                guard !Task.isCancelled else { return }
                let words = (error as? CoreError)?.errorDescription ?? "The Core did not answer."
                if isPage { onProblem(words) }
                return fail(task, status: 502, url: current, text: words)
            }
            guard !Task.isCancelled else { return }
            jar.store(setCookie: reply.headers["set-cookie"])
            if let words = PreviewProxy.problem(reply) {
                if isPage { onProblem(words) }
                return fail(task, status: reply.status, url: current, text: words)
            }
            if (300..<400).contains(reply.status), let location = reply.headers["location"] {
                switch PreviewProxy.redirect(location: location, from: current, project: project, coreHost: coreHost) {
                case .outside:
                    if isPage { onProblem(PreviewProxy.outsideWords) }
                    return fail(task, status: 502, url: current, text: PreviewProxy.outsideWords)
                case .follow(let next):
                    hops += 1
                    guard hops <= Self.maxHops else {
                        if isPage { onProblem("The app redirected too many times.") }
                        return fail(task, status: 502, url: current, text: "The app redirected too many times.")
                    }
                    // ponytail: WKURLSchemeTask has no redirect call, so the hop is followed here and the page keeps its first URL.
                    current = next
                    if reply.status != 307 && reply.status != 308 { (method, body) = ("GET", Data()) }
                    continue
                }
            }
            task.didReceive(Self.response(reply, url: current))
            task.didReceive(reply.body)
            task.didFinish()
            return
        }
    }

    /// One send; a 503 `busy` is asked again up to twice after its `Retry-After` (at most 3 s each).
    static func send(
        _ fetch: PreviewFetch, _ method: String, _ target: String, _ headers: [String: String], _ body: Data
    )
        async throws -> PreviewReply
    {
        var reply = try await fetch(method, target, headers, body)
        for _ in 0..<2 where reply.status == 503 && PreviewProxy.problem(reply) != nil {
            try await Task.sleep(for: .seconds(PreviewProxy.retryAfter(reply)))
            reply = try await fetch(method, target, headers, body)
        }
        return reply
    }

    static func response(_ r: PreviewReply, url: URL) -> URLResponse {
        var head = r.headers.filter { !PreviewProxy.dropped.contains($0.key) }
        head["content-security-policy"] = PreviewProxy.withoutCoreSandbox(head["content-security-policy"])
        head["content-length"] = String(r.body.count)
        return HTTPURLResponse(url: url, statusCode: r.status, httpVersion: "HTTP/1.1", headerFields: head)
            ?? URLResponse(url: url, mimeType: nil, expectedContentLength: r.body.count, textEncodingName: nil)
    }

    /// A request's body, at most 1 MiB (what a signed body may be).
    static func body(of request: URLRequest) -> Data {
        if let b = request.httpBody { return b }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 16 * 1024)
        while stream.hasBytesAvailable, data.count <= (1 << 20) {
            let n = stream.read(&buf, maxLength: buf.count)
            if n <= 0 { break }
            data.append(buf, count: n)
        }
        return data
    }

    private func fail(_ task: any WKURLSchemeTask, status: Int, url: URL?, text: String) {
        guard !Task.isCancelled else { return }
        let u = url ?? PreviewProxy.url()!
        let data = Data(text.utf8)
        let head = ["Content-Type": "text/plain; charset=utf-8", "Content-Length": String(data.count)]
        task.didReceive(HTTPURLResponse(url: u, statusCode: status, httpVersion: "HTTP/1.1", headerFields: head)!)
        task.didReceive(data)
        task.didFinish()
    }
}
