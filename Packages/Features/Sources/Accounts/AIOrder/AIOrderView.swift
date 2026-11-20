import CoreUI
import SwiftUI

/// The Accounts app from Core 0.10 (E7-1, E7-2): one list, "AI order". The first account that is ready serves a new
/// session; when it hits a limit or stops working the next one takes over. Pools and chains are not shown: they are the
/// Core's own words, kept under it. Limits, models and prices and the per-agent order sit under Advanced.
struct AIOrderView: View {
    @Bindable var model: AccountsModel
    @State private var dragging: Int64?
    @State private var dy: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduce

    private let pitch = OrderRowView.height + Space.s2

    var body: some View {
        let rows = model.orderRows
        VStack(alignment: .leading, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("AI order").coreFont(size: MacTextSize.large, weight: .bold)
                Text(
                    "Core uses the first account that is ready. When one hits its limit or stops working, the next one takes over."
                )
                .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let e = model.writeError["order"] { AccIssue(text: e) }
            if rows.isEmpty { empty } else { list(rows) }
            footer(rows.count)
            if model.advancedOpen {
                AdvancedPanel(model: model).transition(reduce ? .identity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ai-order")
    }

    private var empty: some View {
        AccStateCard(
            symbol: "list.number", title: "No accounts yet",
            text: "Add an account and it becomes number 1 in your AI order. Add more to give Core somewhere to go next."
        ) {
            AppActionTile(title: "Add account", symbol: "plus", key: "⌘N", hue: GlassInk.blue, prominent: true) {
                AccountDialogs.openConnect(model, provider: nil)
            }
            .disabled(model.readOnly)
        }
    }

    private func list(_ rows: [OrderRow]) -> some View {
        let from = dragging.flatMap { id in rows.firstIndex { $0.id == id } }
        let target = from.map { OrderMoves.dragTarget(from: $0, translation: dy, pitch: pitch, count: rows.count) }
        return VStack(spacing: Space.s2) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                let isDragged = dragging == row.id
                let shift = from.flatMap { f in target.map { OrderMoves.shift(row: i, dragged: f, target: $0) } } ?? 0
                OrderRowView(
                    row: row, first: i == 0, last: i == rows.count - 1, dragging: isDragged,
                    onDrag: {
                        dragging = row.id
                        dy = $0
                    },
                    onDrop: { t in
                        let to = OrderMoves.dragTarget(from: i, translation: t, pitch: pitch, count: rows.count)
                        dragging = nil
                        dy = 0
                        Task { await model.move(row.id, to: to) }
                    },
                    onKey: { d in Task { await model.move(row.id, to: i + d) } },
                    onAction: { act(row, $0) }
                )
                // grid: ok a drag shows where the row will land; layout stays on the stack.
                .offset(y: isDragged ? dy : CGFloat(shift) * pitch)
                .zIndex(isDragged ? 1 : 0)
                .animation(reduce || isDragged ? nil : Motion.out(Motion.ui), value: shift)
            }
        }
        .disabled(model.readOnly || model.host.pausedReason != nil)
        .accessibilityIdentifier("ai-order-list")
    }

    private func act(_ row: OrderRow, _ a: OrderRowView.RowAction) {
        switch a {
        case .open: withAnimation(.smooth(duration: 0.3)) { model.detail = row.id }
        case .up: Task { await model.moveUp(row.id) }
        case .down: Task { await model.moveDown(row.id) }
        case .check:
            if row.chip == .signingIn {
                AccountDialogs.openConnect(model, provider: row.account.provider)
            } else {
                Task { await model.checkNow(row.account) }
            }
        case .limits:
            model.limitsAccount = row.id
            model.limitsTarget = .account(row.id)
            model.advancedTab = .limits
            withAnimation(reduce ? nil : Motion.out(Motion.ui)) { model.advancedOpen = true }
        case .remove:
            // 0.10: gone at once with an Undo toast; below it the confirmation stays.
            if model.aiOrderOn {
                Task { await model.removeWithUndo(row.account) }
            } else {
                AccountDialogs.openDelete(model, row.account)
            }
        }
    }

    private func footer(_ n: Int) -> some View {
        HStack(spacing: Space.s2) {
            Button {
                withAnimation(reduce ? nil : Motion.out(Motion.ui)) { model.advancedOpen.toggle() }
            } label: {
                Label("Advanced", systemImage: model.advancedOpen ? "chevron.up" : "chevron.down")
            }
            .buttonStyle(CoreButtonStyle(.plain, size: .small))
            .help("Limits, models and prices, and a different order for one agent")
            .accessibilityIdentifier("advanced-toggle")
            Spacer(minLength: 0)
            Text(n == 1 ? "1 account" : "\(n) accounts").coreFont(size: MacTextSize.meta)
                .foregroundStyle(GlassInk.secondary)
        }
    }
}
