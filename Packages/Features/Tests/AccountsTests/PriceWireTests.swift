import Foundation
import Testing

@testable import Accounts

struct PriceWireTests {
    /// `GET /api/v1/prices` as Core 0.10.0 writes it (`PriceBookEntry` through `Timestamp::new`): a price someone set, and
    /// a shipped one no one set (version 0), whose `created_at` is built from an empty stored time, so `".000Z"`.
    static let core010 = Data(
        """
        [{"provider":"google","model":"gemini-4-argon","version":2,"input_per_mtok_micro":4000000,\
        "output_per_mtok_micro":20000000,"cache_per_mtok_micro":200000,"priced_at":"2026-11-20T00:00:00.000Z",\
        "created_at":"2026-11-20T09:12:44.318Z"},
        {"provider":"google","model":"gemini-4-carbon","version":0,"input_per_mtok_micro":4000000,\
        "output_per_mtok_micro":20000000,"cache_per_mtok_micro":200000,"priced_at":"2026-11-19T00:00:00.000Z",\
        "created_at":".000Z"}]
        """.utf8)

    @Test func theShippedPricesWithAnEmptyCreatedAtStillLoad() throws {
        let rows = try PriceWire.items(Self.core010)
        #expect(rows.map(\.model) == ["gemini-4-argon", "gemini-4-carbon"])
        #expect(rows[1].version == 0 && rows[1].input == 4_000_000 && rows[1].output == 20_000_000)
        #expect(rows[1].pricedAt == ISO8601DateFormatter().date(from: "2026-11-19T00:00:00Z"))
    }

    @Test func aRowWithNoPricedDateIsLeftOutNotTheList() throws {
        let bad = Data(
            #"[{"provider":"x","model":"m","version":1,"input_per_mtok_micro":1,"output_per_mtok_micro":1,"cache_per_mtok_micro":1,"priced_at":".000Z","created_at":".000Z"}]"#
                .utf8)
        #expect(try PriceWire.items(bad).isEmpty)
    }
}
