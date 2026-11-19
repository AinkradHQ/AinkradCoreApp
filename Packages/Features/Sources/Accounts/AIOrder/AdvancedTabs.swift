import CoreUI
import SwiftUI

/// Models and prices: what each model of the account's provider costs per million tokens. Core fills the prices in; change
/// one only when the plan differs. Return saves it (a new version of the price, from now on).
struct ModelsTab: View {
    @Bindable var model: AccountsModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if let id = (model.limitsAccount ?? model.orderIDs.first), let a = model.account(id) {
                CoreSelect(
                    "Models of", selection: Binding(get: { a.id }, set: { model.limitsAccount = $0 }),
                    options: model.orderRows.map { CoreSelectOption($0.id, $0.title) })
                let rows = model.prices.filter { $0.provider == a.provider }
                if model.pricesLoad != .ready {
                    SpendState(model: model, state: model.pricesLoad, what: "Prices", scope: "read") {
                        await model.reloadPrices()
                    }
                } else if rows.isEmpty {
                    Text("No prices for this provider yet. Calls to it count as tokens, not as spend.")
                        .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                } else {
                    HStack(spacing: Space.s3) {
                        head("Model").frame(maxWidth: .infinity, alignment: .leading)
                        head("Input, per million words").frame(width: Space.s8 * 5, alignment: .leading)
                        head("Output, per million words").frame(width: Space.s8 * 5, alignment: .leading)
                    }
                    ForEach(rows) { PriceEditRow(model: model, price: $0) }
                }
                Text("Prices are filled in for you. Change them only if your plan differs.")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            } else {
                Text("Add an account first.").foregroundStyle(GlassInk.secondary)
            }
        }
        .task { await model.reloadPrices() }
    }

    private func head(_ s: String) -> some View {
        Text(s).coreFont(size: MacTextSize.meta, weight: .medium).foregroundStyle(GlassInk.secondary)
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

/// Per-agent order: every agent follows the AI order unless it is given another here.
struct AgentsTab: View {
    @Bindable var model: AccountsModel
    @State private var newAgent = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Every agent follows the AI order unless you pick something else here.")
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            ForEach(model.orderAgents, id: \.self) { agent in
                HStack(spacing: Space.s3) {
                    Label(agent, systemImage: "sparkles").lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    CoreSelect(
                        nil,
                        selection: Binding(
                            get: { model.agentChoice(agent) },
                            set: { c in Task { await model.setAgentOrder(agent, c) } }),
                        options: options(agent)
                    )
                    .frame(width: Space.s8 * 8)
                }
                if let e = model.writeError["agent-\(agent)"] { AccIssue(text: e) }
            }
            HStack(alignment: .top, spacing: Space.s2) {
                CoreTextField(
                    "", placeholder: "An agent's id, like atlas", text: $newAgent,
                    error: newAgent.isEmpty || AccountsModel.validAgent(newAgent)
                        ? nil : "1 to 64 letters, digits, . _ : -"
                ) { add() }
                AppActionTile(title: "Add agent", symbol: "plus", key: "", hue: GlassInk.blue) { add() }
                    .disabled(!AccountsModel.validAgent(newAgent) || model.readOnly)
            }
        }
    }

    private func options(_ agent: String) -> [CoreSelectOption<AgentChoice>] {
        var all: [AgentChoice] = [.follow]
        for id in model.orderIDs { all += [.first(id), .only(id)] }
        let now = model.agentChoice(agent)
        if !all.contains(now) { all.append(now) }
        return all.map { CoreSelectOption($0, model.agentChoiceTitle($0)) }
    }

    /// An agent is listed once it has an order of its own; the first choice makes it its own order.
    private func add() {
        let a = newAgent.trimmingCharacters(in: .whitespaces)
        guard AccountsModel.validAgent(a), let first = model.orderIDs.first else { return }
        newAgent = ""
        Task { await model.setAgentOrder(a, .first(first)) }
    }
}
