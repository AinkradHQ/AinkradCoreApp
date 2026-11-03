import Foundation

/// Time, injectable so session scheduling can be tested.
public protocol CoreClock: Sendable {
    func now() -> Date
    func sleep(for duration: Duration) async throws
}

public struct SystemCoreClock: CoreClock {
    public init() {}
    public func now() -> Date { Date() }
    public func sleep(for duration: Duration) async throws { try await Task.sleep(for: duration) }
}

/// Where the Core is: an origin, nothing else. Plain HTTP only to loopback (dev); everything else is HTTPS.
public struct CoreEndpoint: Sendable, Equatable {
    public let url: URL
    /// The `Host` the Core expects: the authority as URLSession sends it (the default port is dropped).
    public let host: String

    public init(_ url: URL) throws {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let scheme = parts.scheme?.lowercased(), let name = parts.host, !name.isEmpty
        else { throw CoreError.invalidInput("the Core endpoint needs a scheme and a host") }
        guard parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
            parts.path.isEmpty || parts.path == "/"
        else { throw CoreError.invalidInput("the Core endpoint is an origin: no path, query or credentials") }
        let loopback = ["127.0.0.1", "localhost", "::1"].contains(name.lowercased())
        switch scheme {
        case "https": break
        case "http" where loopback: break
        case "http": throw CoreError.invalidInput("plain http is only for loopback; use https")
        default: throw CoreError.invalidInput("the Core endpoint is http(s)")
        }
        let defaultPort = scheme == "https" ? 443 : 80
        let shown = name.contains(":") ? "[\(name)]" : name
        var origin = URLComponents()
        origin.scheme = scheme
        origin.host = name
        origin.port = parts.port
        guard let clean = origin.url else { throw CoreError.invalidInput("the Core endpoint is not a URL") }
        self.url = clean
        self.host = (parts.port == nil || parts.port == defaultPort) ? shown : "\(shown):\(parts.port!)"
    }

    /// `https://host[:port]` for a QR payload (§7.1: a QR always means HTTPS).
    public init(host: String, port: Int) throws {
        guard let url = URL(string: "https://\(host.contains(":") ? "[\(host)]" : host):\(port)") else {
            throw CoreError.invalidInput("the QR names no usable host")
        }
        try self.init(url)
    }
}

/// One request as it goes on the wire: `target` is the path and raw query exactly as signed.
struct RawRequest: Sendable {
    var method: String
    var target: String
    var headers: [String: String] = [:]
    var body = Data()
}

struct RawResponse: Sendable {
    var status: Int
    /// Header names in lower case.
    var headers: [String: String]
    var body: Data
}

/// The one place bytes leave for the Core.
protocol CoreHTTP: Sendable {
    func send(_ request: RawRequest) async throws -> RawResponse
}

/// A session that never follows a redirect (a redirect would carry signed headers to another host), keeps no cookies and
/// no cache.
func makeCoreSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.urlCache = nil
    config.httpCookieStorage = nil
    config.httpShouldSetCookies = false
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    config.timeoutIntervalForRequest = 20
    return URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) { completionHandler(nil) }
}

func transportError(_ error: any Error) -> any Error {
    if error is CancellationError || error is CoreError { return error }
    if let e = error as? URLError {
        if e.code == .cancelled { return CancellationError() }
        return CoreError.offline(e.localizedDescription)
    }
    return CoreError.offline(String(describing: type(of: error)))
}

struct URLSessionHTTP: CoreHTTP {
    let endpoint: CoreEndpoint
    let session: URLSession

    func send(_ r: RawRequest) async throws -> RawResponse {
        guard let url = URL(string: endpoint.url.absoluteString + r.target) else {
            throw CoreError.invalidInput("not a request target")
        }
        var req = URLRequest(url: url)
        req.httpMethod = r.method
        for (k, v) in r.headers { req.setValue(v, forHTTPHeaderField: k) }
        if !r.body.isEmpty { req.httpBody = r.body }
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw CoreError.protocolViolation("not an HTTP answer")
            }
            var headers: [String: String] = [:]
            for (k, v) in http.allHeaderFields { headers[String(describing: k).lowercased()] = String(describing: v) }
            return RawResponse(status: http.statusCode, headers: headers, body: data)
        } catch { throw transportError(error) }
    }
}
