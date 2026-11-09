import CoreUI
import SwiftUI

/// This account's own share of Costs and the Ledger, on its page: what it used in the last 5 hours and 7 days and its
/// latest cost events, with the way to the full pages. Nothing is estimated: no figure, no line.
struct AccountSlice: View {
    let model: AccountsModel
    let account: AccountItem

    var body: some View {
        let use = model.usage.first { $0.accountID == account.id }
        let events = model.costs.filter { $0.accountID == account.id }.sorted { $0.at > $1.at }.prefix(4)
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Label("Spend and usage", systemImage: "chart.bar").font(.system(size: MacTextSize.meta, weight: .semibold))
                    .foregroundStyle(GlassInk.secondary)
                Spacer(minLength: Space.s2)
                AccLink(title: "Open Costs", symbol: "arrow.right") { go(.costs) }
                AccLink(title: "Open Ledger", symbol: "arrow.right") { go(.ledger) }
            }
            switch model.costsLoad {
            case .loading: AccSkeleton()
            case .forbidden:
                Text("Only a device with the admin scope can see usage and costs.").foregroundStyle(GlassInk.secondary)
            case .failed(_, let message):
                Text("Could not load usage. \(message)").foregroundStyle(GlassInk.orangeInk)
            case .ready:
                if let use {
                    HStack(alignment: .top, spacing: Space.s3) {
                        window("Last 5 hours", use.fiveHours)
                        window("Last 7 days", use.sevenDays)
                    }
                } else {
                    Text("Not used yet, so there is nothing to count.").foregroundStyle(GlassInk.secondary)
                }
                ForEach(Array(events)) { e in
                    HStack(spacing: Space.s2) {
                        Text(e.at.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(GlassInk.secondary)
                        Text(e.model).lineLimit(1)
                        Spacer(minLength: Space.s2)
                        Text(AccountsNumbers.tokens(e.tokens)).foregroundStyle(GlassInk.secondary)
                        Text(e.costMicros.map { AccountsNumbers.usd($0) } ?? "Not priced")
                    }
                    .font(.system(size: MacTextSize.meta))
                }
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
        .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("account-slice")
    }

    private func window(_ title: String, _ w: UsageWindowItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
            Text(AccountsNumbers.tokens(w.tokens)).font(.system(size: MacTextSize.title, weight: .semibold))
            Text("\(AccountsNumbers.usd(w.costMicros)), \(w.messages.formatted()) \(w.messages == 1 ? "message" : "messages")")
                .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func go(_ page: AccountsPage) {
        model.page = page
        model.detail = nil
    }
}
