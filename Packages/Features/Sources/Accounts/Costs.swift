import CoreKit
import CoreUI
import SwiftUI

/// Tokens, messages and dollars in one window (`UsageWindow`).
struct UsageWindowItem: Equatable, Sendable {
    let tokens: Int64
    let messages: Int64
    let costMicros: Int64
    static let zero = UsageWindowItem(tokens: 0, messages: 0, costMicros: 0)
    static func + (l: Self, r: Self) -> Self {
        UsageWindowItem(
            tokens: l.tokens + r.tokens, messages: l.messages + r.messages, costMicros: l.costMicros + r.costMicros)
    }
}

struct CompanyUsage: Equatable, Sendable {
    let company: String
    let fiveHours: UsageWindowItem
    let sevenDays: UsageWindowItem
}

/// One account's use (`GET /accounts/usage`): the windows, how close its tightest limit is, and drops.
struct UsageItem: Equatable, Sendable {
    let accountID: Int64
    let fiveHours: UsageWindowItem
    let sevenDays: UsageWindowItem
    /// The tightest limit's used/cap, 0...1+.
    let limitShare: Double
    let limitsExhausted: Bool
    let hasLimits: Bool
    let drops: Int64
    let companies: [CompanyUsage]
    /// Where each usage limit of the account stands (`PUT /accounts/{id}/limits`).
    var limits: [LimitItem] = []
}

/// One cost event: one attempt of a session, a delta. No cost when nothing priced it.
struct CostItem: Identifiable, Equatable, Sendable {
    let id: Int64
    let at: Date
    let accountID: Int64?
    let provider: String
    let model: String
    let session: String
    let input: Int64
    let output: Int64
    let cache: Int64
    let costMicros: Int64?
    /// `list_price`, `provider_reported`, `billing_corrected` or `unpriced`.
    let basis: String
    let approximate: Bool
    var tokens: Int64 { input + output + cache }
}

/// A model's newest price: millionths of a dollar per million tokens.
struct PriceItem: Identifiable, Equatable, Sendable {
    var id: String { "\(provider)/\(model)" }
    let provider: String
    let model: String
    let input: Int64
    let output: Int64
    let cache: Int64
    let version: Int64
    let pricedAt: Date
}

struct PriceDraft: Equatable, Sendable {
    var provider: String
    var model: String
    var input: Int64
    var output: Int64
    var cache: Int64
    var pricedAt: Date
}

enum SpendWindow: String, CaseIterable, Sendable {
    case fiveHours = "Last 5 hours"
    case sevenDays = "Last 7 days"
    func of(_ u: UsageItem) -> UsageWindowItem { self == .fiveHours ? u.fiveHours : u.sevenDays }
    func of(_ c: CompanyUsage) -> UsageWindowItem { self == .fiveHours ? c.fiveHours : c.sevenDays }
}

enum CostWords {
    static func usd(_ micros: Int64) -> String { ModelPriceItem.usd(micros) }
    static func tokens(_ n: Int64) -> String { AccountsNumbers.amount(n) }

    static func basis(_ b: String) -> (title: String, hue: Color) {
        switch b {
        case "list_price": ("List price", GlassInk.secondary)
        case "provider_reported": ("Reported by the provider", GlassInk.secondary)
        case "billing_corrected": ("Corrected from the bill", GlassInk.blue)
        case "unpriced": ("No price", GlassInk.orange)
        default: (b, GlassInk.secondary)
        }
    }

    /// A model id Core will price: as the provider names it, no alias and no `:online`.
    static func modelIssue(_ m: String) -> String? {
        let t = m.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return "Type the model id." }
        if t.contains(" ") { return "A model id has no spaces." }
        if t.hasSuffix("-latest") || t.hasSuffix(":online") {
            return "Use the exact id, not an alias like -latest or :online."
        }
        return nil
    }
}

extension AccountsModel {
    func reloadCosts() async {
        guard let service else { return }
        if usage.isEmpty && costs.isEmpty { costsLoad = .loading }
        do {
            async let u = service.usage()
            async let c = service.costs(account: nil)
            (usage, costs) = try await (u, c)
            costsLoad = .ready
        } catch { costsLoad = state(for: error) }
    }

    func reloadPrices() async {
        guard let service else { return }
        if prices.isEmpty { pricesLoad = .loading }
        do {
            prices = try await service.prices()
            pricesLoad = .ready
        } catch { pricesLoad = state(for: error) }
    }

    func savePrice(_ p: PriceDraft) async -> Bool {
        let ok = await write(
            "price", reason: "Set the price of \(p.model). Calls from now on are priced with it.",
            done: "\(p.model) priced", keepsEdit: true
        ) { try await $0.setPrice(p) }
        if ok { await reloadPrices() }
        return ok
    }

    /// Tokens in the loaded calls that no price covered: they count as tokens, not as spend.
    var unpricedTokens: Int64 { costs.filter { $0.basis == "unpriced" }.reduce(0) { $0 + $1.tokens } }

    func label(ofAccount id: Int64?) -> String {
        guard let id else { return "Not a Core account" }
        return account(id)?.label ?? "Account \(id)"
    }
}

/// A refused Spend page: an older Core (when accounts load, a `forbidden_scope` here means the route is missing), a device
/// without `admin`, or the Core's error.
struct SpendState: View {
    let model: AccountsModel
    let state: AccountsLoad
    let what: String
    let scope: String
    let retry: () async -> Void

    var body: some View {
        switch state {
        case .loading: AccSkeleton()
        case .forbidden:
            if model.load == .ready && scope == "read" {
                OlderCoreCard(what: what)
            } else {
                AccStateCard(
                    symbol: "lock", title: "This Mac can't see \(what.lowercased())",
                    text:
                        "This Mac can only look. \(what) need\(what.hasSuffix("s") ? "" : "s") a Mac you allowed to \(scope == "read" ? "read from" : "manage") the Core, or a newer Core.",
                    code: "forbidden_scope")
            }
        case .failed(let code, let message):
            AccStateCard(
                symbol: "exclamationmark.triangle", title: "Could not load \(what.lowercased())",
                text: "The Core answered with an error. \(message)", tone: .fail, code: code
            ) {
                AppActionTile(title: "Try again", symbol: "arrow.clockwise", key: "R", hue: GlassInk.blue) {
                    Task { await retry() }
                }
            }
        case .ready: EmptyView()
        }
    }
}
