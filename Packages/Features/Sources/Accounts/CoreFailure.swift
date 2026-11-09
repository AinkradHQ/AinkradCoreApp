import AinkradClient
import CoreKit

/// The Core's refusals (400, 404, 409, ...) are typed outputs of the generated client: reading `.ok` on one throws an
/// "unexpected response" error that holds the answer, not a `CoreError`. This reads the Core's code and message back out.
enum CoreFailure {
    private static let statuses: [String: Int] = [
        "badRequest": 400, "notFound": 404, "conflict": 409, "unprocessableContent": 422, "badGateway": 502,
        "serviceUnavailable": 503, "internalServerError": 500,
    ]

    /// `CoreError` inside what the client threw, else the Core's own answer carried by it, else nil.
    static func of(_ error: any Error) -> CoreError? {
        if let core = CoreError.unwrapping(error) { return core }
        var status: Int?
        var body: Components.Schemas.ErrorBody?
        func walk(_ value: Any, _ depth: Int) {
            guard depth < 8, body == nil else { return }
            if let b = value as? Components.Schemas.ErrorBody {
                body = b
                return
            }
            for child in Mirror(reflecting: value).children {
                if status == nil, let label = child.label, let s = statuses[label] { status = s }
                walk(child.value, depth + 1)
            }
        }
        walk(error, 0)
        guard let body else { return nil }
        return .http(status: status ?? 400, code: body.code, message: body.message)
    }
}
