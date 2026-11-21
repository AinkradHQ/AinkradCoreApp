import CoreUI
import SwiftUI

/// "Advanced" under the AI order: Limits, and Models and prices. Most people never open it.
struct AdvancedPanel: View {
    @Bindable var model: AccountsModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(spacing: Space.s3) {
                CoreSegmented(
                    "Advanced", segments: AdvancedTab.allCases.map { CoreSegment($0, $0.title) },
                    selection: $model.advancedTab)
                Spacer(minLength: Space.s2)
                Text("Most people never need this.").coreFont(size: MacTextSize.meta).foregroundStyle(
                    GlassInk.secondary)
            }
            switch model.advancedTab {
            case .limits: LimitsTab(model: model)
            case .models: ModelsTab(model: model)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .coreWell()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ai-order-advanced")
    }
}

struct LimitsTab: View {
    @Bindable var model: AccountsModel
    @State private var adding = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if !model.aiOrderOn {
                // Core 0.10 retired the old usage limits for budgets; a Core below it has no message limits to set here.
                Text("Limits by messages need a newer Core. Budgets in tokens and dollars are under Spending.")
                    .foregroundStyle(GlassInk.secondary)
                spendingLink
            } else if let t = model.limitTarget {
                CoreSelect(
                    "Limits for",
                    selection: Binding(
                        get: { t },
                        set: {
                            model.limitsTarget = $0
                            adding = false
                        }),
                    options: model.limitOptions
                )
                .frame(width: Space.s8 * 9)
                if case .account(let id) = t, let b = model.account(id)?.runnerBinding { RunnerBoundNote(binding: b) }
                HStack(spacing: Space.s3) {
                    header("Window").frame(width: BudgetLimitRow.Col.window, alignment: .leading)
                    header("Stop at").frame(width: BudgetLimitRow.Col.stop, alignment: .leading)
                    header("Warn me at").frame(width: BudgetLimitRow.Col.warn, alignment: .leading)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Space.s3)
                BudgetLimitRows(model: model, target: t, adding: $adding)
                HStack(spacing: Space.s2) {
                    AccLink(title: "Add a limit", symbol: "plus") { adding = true }
                        .disabled(model.readOnly || adding)
                        .keyboardShortcut("l", modifiers: [.command, .option]).environment(\.coreKeycap, "⌥⌘L")
                    Spacer(minLength: Space.s2)
                    spendingLink
                }
            } else {
                Text("Add an account first. Limits belong to a provider.").foregroundStyle(GlassInk.secondary)
            }
        }
        .task { await model.reloadBudgets() }
    }

    private var spendingLink: some View {
        AccLink(title: "Budgets, costs and ledger", symbol: "dollarsign.circle") {
            withAnimation(.smooth(duration: 0.3)) { model.page = .spending }
        }
    }

    private func header(_ s: String) -> some View {
        Text(s).coreFont(size: MacTextSize.meta, weight: .medium).foregroundStyle(GlassInk.secondary)
    }
}
