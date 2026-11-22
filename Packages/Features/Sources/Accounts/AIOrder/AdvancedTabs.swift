import CoreUI
import SwiftUI

/// Models and prices: what each model of the account's provider costs per million tokens. Core fills the prices in; change
/// one only when the plan differs. Return saves it (a new version of the price, from now on).
struct ModelsTab: View {
    @Bindable var model: AccountsModel

    private var chosenID: Int64? { model.limitsAccount ?? model.orderIDs.first }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if let id = chosenID, let a = model.account(id) {
                CoreSelect(
                    "Models of", selection: Binding(get: { a.id }, set: { model.limitsAccount = $0 }),
                    options: model.orderRows.map { CoreSelectOption($0.id, $0.title) })
                let rows = model.prices.filter { $0.provider == a.provider }
                let listed = model.modelRows[a.id] ?? []
                if model.pricesLoad != .ready {
                    SpendState(model: model, state: model.pricesLoad, what: "Prices", scope: "read") {
                        await model.reloadPrices()
                    }
                } else if !listed.isEmpty {
                    HStack(spacing: Space.s3) {
                        head("Model").frame(maxWidth: .infinity, alignment: .leading)
                        if a.isPlan {
                            head("Price").frame(width: Space.s8 * 10 + Space.s3, alignment: .leading)
                        } else {
                            head("Input, per million words").frame(width: Space.s8 * 5, alignment: .leading)
                            head("Output, per million words").frame(width: Space.s8 * 5, alignment: .leading)
                        }
                        Color.clear.frame(width: ModelAllowRow.switchWidth, height: 1)
                    }
                    ForEach(listed) { r in
                        ModelAllowRow(model: model, account: a, row: r, price: rows.first { $0.model == r.model })
                            .id("\(a.id)-\(r.model)-\(r.inputMicro ?? -1)-\(r.outputMicro ?? -1)")
                    }
                } else if rows.isEmpty {
                    Text(
                        a.isPlan
                            ? "Its models show here once the Core lists them or a session runs one."
                            : "No prices for this provider yet. Calls to it count as tokens, not as spend."
                    )
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                } else {
                    HStack(spacing: Space.s3) {
                        head("Model").frame(maxWidth: .infinity, alignment: .leading)
                        head("Input, per million words").frame(width: Space.s8 * 5, alignment: .leading)
                        head("Output, per million words").frame(width: Space.s8 * 5, alignment: .leading)
                    }
                    ForEach(rows) { PriceEditRow(model: model, price: $0) }
                }
                if a.modelsEnforced == false {
                    Text(AccountNotes.unenforcedWords).coreFont(size: MacTextSize.meta).foregroundStyle(
                        GlassInk.amberInk
                    )
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("models-unenforced")
                }
                if !a.isPlan {
                    Text("Prices are filled in for you. Change them only if your plan differs.")
                        .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                }
            } else {
                Text("Add an account first.").foregroundStyle(GlassInk.secondary)
            }
        }
        .task(id: chosenID) {
            await model.reloadPrices()
            if let id = chosenID, let a = model.account(id) { await model.reloadModels(a) }
        }
    }

    private func head(_ s: String) -> some View {
        Text(s).coreFont(size: MacTextSize.meta, weight: .medium).foregroundStyle(GlassInk.secondary)
    }
}

/// One model of the account: its price in and out, and "Allow this model". A model switched off is never picked for this
/// account, in the AI order, a chain or a session.
private struct ModelAllowRow: View {
    static let switchWidth = Space.s8 * 1.5
    let model: AccountsModel
    let account: AccountItem
    let row: ModelRowItem
    let price: PriceItem?
    @State private var input: String
    @State private var output: String

    init(model: AccountsModel, account: AccountItem, row: ModelRowItem, price: PriceItem?) {
        self.model = model
        self.account = account
        self.row = row
        self.price = price
        let i = row.inputMicro ?? price?.input
        let o = row.outputMicro ?? price?.output
        _input = State(initialValue: i.map { AccountsNumbers.dollarsField($0) } ?? "")
        _output = State(initialValue: o.map { AccountsNumbers.dollarsField($0) } ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s3) {
                Text(row.model).coreFont(size: MacTextSize.body, design: .monospaced).lineLimit(1)
                    .foregroundStyle(row.allowed ? GlassInk.primary : GlassInk.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if account.isPlan {
                    // A plan bills nothing per token (Ahmed, 2026-11-22: plans had no models at all).
                    Text("Included in your plan").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                        .frame(width: Space.s8 * 10 + Space.s3, alignment: .leading)
                } else {
                    field($input).frame(width: Space.s8 * 5)
                    field($output).frame(width: Space.s8 * 5)
                }
                CoreSwitch(
                    "",
                    isOn: Binding(
                        get: { row.allowed },
                        set: { on in Task { await model.setModelAllowed(account, row.model, on) } })
                )
                .disabled(model.readOnly)
                .help("Allow this model")
                .accessibilityLabel("Allow \(row.model)")
                .frame(width: Self.switchWidth, alignment: .trailing)
            }
            if let e = model.writeError["model-\(account.id)-\(row.model)"] { AccIssue(text: e) }
        }
    }

    private func field(_ t: Binding<String>) -> some View {
        HStack(spacing: Space.s2) {
            Text("$").foregroundStyle(GlassInk.secondary)
            CoreTextField("", placeholder: "0.00", text: t, error: nil) { Task { await save() } }
        }
    }

    /// A new version of the price, from now on. A model the book has no price for gets its first one.
    private func save() async {
        guard let i = BudgetInput.price(input), let o = BudgetInput.price(output),
            (i, o) != (row.inputMicro ?? price?.input, row.outputMicro ?? price?.output)
        else { return }
        _ = await model.savePrice(
            PriceDraft(
                provider: account.provider, model: row.model, input: i, output: o, cache: price?.cache ?? i,
                pricedAt: model.now()))
        await model.reloadModels(account)
    }
}

private struct PriceEditRow: View {
    let model: AccountsModel
    let price: PriceItem
    @State private var input: String
    @State private var output: String

    init(model: AccountsModel, price: PriceItem) {
        self.model = model
        self.price = price
        _input = State(initialValue: AccountsNumbers.dollarsField(price.input))
        _output = State(initialValue: AccountsNumbers.dollarsField(price.output))
    }

    var body: some View {
        HStack(spacing: Space.s3) {
            Text(price.model).coreFont(size: MacTextSize.body, design: .monospaced).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            field($input).frame(width: Space.s8 * 5)
            field($output).frame(width: Space.s8 * 5)
        }
    }

    private func field(_ t: Binding<String>) -> some View {
        HStack(spacing: Space.s2) {
            Text("$").foregroundStyle(GlassInk.secondary)
            CoreTextField("", placeholder: "0.00", text: t, error: nil) { Task { await save() } }
        }
    }

    private func save() async {
        guard let i = BudgetInput.price(input), let o = BudgetInput.price(output), (i, o) != (price.input, price.output)
        else { return }
        _ = await model.savePrice(
            PriceDraft(
                provider: price.provider, model: price.model, input: i, output: o, cache: price.cache,
                pricedAt: model.now()))
    }
}
