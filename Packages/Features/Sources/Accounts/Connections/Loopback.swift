import Foundation
import Network

/// CN7: catches the Atlassian sign-in's redirect on this Mac (decision 2: loopback first, Core's own URL later). It
/// listens on 127.0.0.1 only, only while a sign-in is open, takes one `GET /callback?code&state` whose state matches,
/// answers the browser with a short page and hands the code on. Nothing else is read or kept.
final class LoopbackCatcher: Sendable {
    /// The redirect registered with the Atlassian OAuth app is `http://127.0.0.1:47613/callback`.
    // ponytail: one fixed port, as the OAuth registration needs; a busy port fails the sign-in with a plain message.
    static let port: UInt16 = 47613
    private let listener: NWListener
    private let state: String?
    private let onCode: @Sendable (String) -> Void

    /// With a `state`: catches a sign-in's `code`. Without: catches GitHub's app setup redirect and hands on its
    /// `installation_id`.
    init(state: String?, onCode: @escaping @Sendable (String) -> Void) throws {
        self.state = state
        self.onCode = onCode
        let p = NWParameters.tcp
        p.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
        p.allowLocalEndpointReuse = true
        listener = try NWListener(using: p)
    }

    func start() {
        let state = state
        let onCode = onCode
        listener.newConnectionHandler = { @Sendable c in
            c.start(queue: .global())
            c.receive(minimumIncompleteLength: 1, maximumLength: 8192) { @Sendable data, _, _, _ in
                let code = Self.code(in: data.flatMap { String(data: $0, encoding: .utf8) } ?? "", state: state)
                c.send(content: Self.page(ok: code != nil), completion: .contentProcessed { @Sendable _ in c.cancel() })
                if let code { onCode(code) }
            }
        }
        listener.start(queue: .global())
    }

    func stop() { listener.cancel() }

    /// The code from the request's first line, only for `/callback` with a matching state.
    static func code(in request: String, state: String?) -> String? {
        let parts = request.split(separator: "\r\n", maxSplits: 1).first?.split(separator: " ") ?? []
        guard parts.count >= 2, parts[0] == "GET", let url = URLComponents(string: String(parts[1])),
            url.path == "/callback"
        else { return nil }
        let q = Dictionary(
            (url.queryItems ?? []).compactMap { i in i.value.map { (i.name, $0) } }, uniquingKeysWith: { a, _ in a })
        guard let state else { return q["installation_id"].flatMap { Int64($0) != nil ? $0 : nil } }
        guard q["state"] == state, let code = q["code"], !code.isEmpty else { return nil }
        return code
    }

    static func page(ok: Bool) -> Data {
        let (title, line) =
            ok
            ? ("You're all set", "You can close this tab and go back to Ainkrad.")
            : ("This sign-in didn't match", "Go back to Ainkrad and try again.")
        let html = """
            <!doctype html><meta charset="utf-8"><title>Ainkrad</title>
            <body style="font:15px -apple-system,system-ui;text-align:center;padding:80px 20px;color:#0F172A;background:#F4F6FA">
            <h1 style="font-size:22px">\(title)</h1><p style="color:#475569">\(line)</p></body>
            """
        let body = Data(html.utf8)
        let head =
            "HTTP/1.1 \(ok ? "200 OK" : "400 Bad Request")\r\nContent-Type: text/html; charset=utf-8\r\n"
            + "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}
