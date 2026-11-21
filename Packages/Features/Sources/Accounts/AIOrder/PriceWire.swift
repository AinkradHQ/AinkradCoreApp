import CoreKit
import Foundation

// HAND-WRITTEN WIRE for `GET /api/v1/prices`. Core 0.10.0 lists the prices it ships but no one set (version 0) with
// `created_at` built from an empty stored time: `".000Z"`. The generated client reads every timestamp as a date, so that
// one field failed the whole list ("Could not load prices"). Here only `priced_at` must be a date; `created_at` is unused.

/// One row of the price book, read leniently.
struct PriceWire: Decodable, Sendable {
    let provider: String
    let model: String
    let version: Int64
    let input: Int64
    let output: Int64
    let cache: Int64
    let pricedAt: String

    private enum CodingKeys: String, CodingKey {
        case provider, model, version
        case input = "input_per_mtok_micro"
        case output = "output_per_mtok_micro"
        case cache = "cache_per_mtok_micro"
        case pricedAt = "priced_at"
    }

    /// The rows of the answer; a row whose `priced_at` is no date is left out rather than failing the rest.
    static func items(_ data: Data) throws -> [PriceItem] {
        try JSONDecoder().decode([PriceWire].self, from: data).compactMap { p in
            WireDate.parse(p.pricedAt).map {
                PriceItem(
                    provider: p.provider, model: p.model, input: p.input, output: p.output, cache: p.cache,
                    version: p.version, pricedAt: $0)
            }
        }
    }
}

extension LiveAccountsService {
    func prices() async throws -> [PriceItem] {
        let data = try await connection.signedRequest(method: "GET", target: "/api/v1/prices")
        do { return try PriceWire.items(data) } catch {
            throw CoreError.protocolViolation("The Core answered something this app does not know.")
        }
    }
}
