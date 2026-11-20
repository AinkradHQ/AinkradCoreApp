import CoreKit
import Foundation

// HAND-WRITTEN WIRE for Core 0.10 (E7-2b). The generated client does not know these fields yet; the coordinator runs
// `make clients` at integration and this file then shrinks to the mapping. Every call is gated by API minor 95.

/// An account row's usage meter (`usage` on `GET /accounts` and `/accounts/{id}`, admin devices only).
struct AccountMeterItem: Equatable, Sendable {
    /// `ready`, `limit_hit` (stopped until `stateUntil`) or `unavailable` (resting, unhealthy or turned off).
    var state: String
    var stateUntil: Date?
    /// 0...1 of the most used limit; nil when the account has none.
    var fraction: Double?
    var used: Double?
    var limit: Double?
    /// `percent`, `usd_micros`, `messages` or `tokens`.
    var unit: String?
    /// `five_hours`, `day`, `week`, `month` or `total` (or a harness's own name).
    var window: String?
    var resetsAt: Date?

    var limitHit: Bool { state == "limit_hit" }
    /// The window's length; nil for `total` and for a name this app does not know.
    var windowSecs: Int64? {
        switch window {
        case "five_hours": 18_000
        case "day": 86_400
        case "week": 604_800
        case "month": 2_592_000
        default: nil
        }
    }
}

enum WireDate {
    private static func make(_ fractional: Bool) -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = fractional ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return f
    }
    static func parse(_ s: String?) -> Date? {
        guard let s else { return nil }
        return make(true).date(from: s) ?? make(false).date(from: s)
    }
}

/// `GET /api/v1/accounts` read for the `usage` object and nothing else.
struct AccountUsageProbe: Decodable, Sendable {
    let id: Int64
    let usage: Meter?

    struct Meter: Decodable, Sendable {
        let state: String
        let stateUntil: String?
        let fraction: Double?
        let used: Double?
        let limit: Double?
        let unit: String?
        let window: String?
        let resetsAt: String?
        private enum CodingKeys: String, CodingKey {
            case state, fraction, used, limit, unit, window
            case stateUntil = "state_until"
            case resetsAt = "resets_at"
        }
        var item: AccountMeterItem {
            AccountMeterItem(
                state: state, stateUntil: WireDate.parse(stateUntil), fraction: fraction, used: used, limit: limit,
                unit: unit, window: window, resetsAt: WireDate.parse(resetsAt))
        }
    }

    static func meters(_ data: Data) -> [Int64: AccountMeterItem] {
        let rows = (try? JSONDecoder().decode([AccountUsageProbe].self, from: data)) ?? []
        var out: [Int64: AccountMeterItem] = [:]
        for r in rows { if let m = r.usage { out[r.id] = m.item } }
        return out
    }
}

/// One model of an account with its list price and whether it is allowed (`GET /accounts/{id}/models`, `items`).
struct ModelRowItem: Identifiable, Equatable, Sendable {
    var id: String { model }
    let model: String
    var allowed: Bool
    var inputMicro: Int64?
    var outputMicro: Int64?
}

/// `GET /api/v1/accounts/{id}/models` read for `items`.
struct ModelRowsProbe: Decodable, Sendable {
    let items: [Row]?
    struct Row: Decodable, Sendable {
        let model: String
        let allowed: Bool?
        let inputPerMtokMicro: Int64?
        let outputPerMtokMicro: Int64?
        private enum CodingKeys: String, CodingKey {
            case model, allowed
            case inputPerMtokMicro = "input_per_mtok_micro"
            case outputPerMtokMicro = "output_per_mtok_micro"
        }
    }
    static func rows(_ data: Data) -> [ModelRowItem] {
        ((try? JSONDecoder().decode(ModelRowsProbe.self, from: data))?.items ?? []).map {
            ModelRowItem(
                model: $0.model, allowed: $0.allowed ?? true, inputMicro: $0.inputPerMtokMicro,
                outputMicro: $0.outputPerMtokMicro)
        }
    }
}

/// `PUT /api/v1/accounts/{id}/models/{model}`.
struct ModelAllowedPut: Encodable, Sendable { let allowed: Bool }

/// `GET /api/v1/budgets` read for the message cap and count (0.10 budgets), and `GET /accounts/providers` for `preset`.
struct BudgetMessagesProbe: Decodable, Sendable {
    let id: Int64
    let messageCap: Int64?
    let messages: Int64?
    private enum CodingKeys: String, CodingKey {
        case id, messages
        case messageCap = "message_cap"
    }
}

struct ProviderPresetProbe: Decodable, Sendable {
    let id: String
    let preset: Bool?
}

/// `PUT /api/v1/budgets` with a message cap or a 5-hour period, which the generated body cannot say yet.
struct BudgetPut: Encodable, Sendable {
    let kind: String
    let subject: String
    let period: String
    let tokenCap: Int64
    let usdCapMicros: Int64?
    let messageCap: Int64?
    let warnAtPercent: Int64
    let hardStop: Bool
    private enum CodingKeys: String, CodingKey {
        case kind, subject, period
        case tokenCap = "token_cap"
        case usdCapMicros = "usd_cap_micros"
        case messageCap = "message_cap"
        case warnAtPercent = "warn_at_percent"
        case hardStop = "hard_stop"
    }
    init(_ b: BudgetDraft) {
        (kind, subject, period, tokenCap) = (b.kind, b.subject, b.period, b.tokenCap)
        (usdCapMicros, messageCap, warnAtPercent, hardStop) = (b.usdCap, b.messageCap, b.warnAt, b.hardStop)
    }
}

extension AccountsService {
    func accountMeters() async -> [Int64: AccountMeterItem] { [:] }
    func accountModels(account: Int64) async -> [ModelRowItem] { [] }
    func setModelAllowed(account: Int64, model: String, allowed: Bool) async throws {
        throw CoreError.invalidInput("Switching a model off needs a newer Core.")
    }
}

extension LiveAccountsService {
    func accountMeters() async -> [Int64: AccountMeterItem] {
        guard await aiOrderSupported(),
            let data = try? await connection.signedRequest(method: "GET", target: "/api/v1/accounts")
        else { return [:] }
        return AccountUsageProbe.meters(data)
    }

    func accountModels(account: Int64) async -> [ModelRowItem] {
        guard await aiOrderSupported(),
            let data = try? await connection.signedRequest(method: "GET", target: "/api/v1/accounts/\(account)/models")
        else { return [] }
        return ModelRowsProbe.rows(data)
    }

    func setModelAllowed(account: Int64, model: String, allowed: Bool) async throws {
        let body = try JSONEncoder().encode(ModelAllowedPut(allowed: allowed))
        _ = try await connection.signedRequest(
            method: "PUT", target: "/api/v1/accounts/\(account)/models/\(Self.segment(model))", body: body)
    }

    /// The generated budgets plus the 0.10 message cap and count each one carries.
    func withMessages(_ list: [BudgetItem]) async -> [BudgetItem] {
        guard await aiOrderSupported(),
            let data = try? await connection.signedRequest(method: "GET", target: "/api/v1/budgets"),
            let rows = try? JSONDecoder().decode([BudgetMessagesProbe].self, from: data)
        else { return list }
        return list.map { b in
            var b = b
            if let r = rows.first(where: { $0.id == b.id }) {
                (b.messageCap, b.messages) = (r.messageCap, r.messages ?? 0)
            }
            return b
        }
    }

    /// The generated providers plus whether each is a preset.
    func withPresets(_ list: [ProviderItem]) async -> [ProviderItem] {
        guard await aiOrderSupported(),
            let data = try? await connection.signedRequest(method: "GET", target: "/api/v1/accounts/providers"),
            let rows = try? JSONDecoder().decode([ProviderPresetProbe].self, from: data)
        else { return list }
        return list.map { p in
            var p = p
            p.preset = rows.first { $0.id == p.id }?.preset ?? false
            return p
        }
    }
}
