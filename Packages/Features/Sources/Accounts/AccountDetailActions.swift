import CoreUI
import SwiftUI

/// Everything the account page can do, each with its key. One is the page's main action, the rest sit in ⋯ (⌘.).
enum DetailAction: CaseIterable {
    case check, order, signIn, turnOn, turnOff, key, budget, up, down, limits, rename, tech, remove

    var title: String {
        switch self {
        case .check: "Check"
        case .order: "Open AI order"
        case .signIn: "Sign in again"
        case .turnOn: "Turn on"
        case .turnOff: "Turn off"
        case .key: "Replace key…"
        case .budget: "Budget…"
        case .up: "Move up in the AI order"
        case .down: "Move down in the AI order"
        case .limits: "Limits…"
        case .rename: "Rename…"
        case .tech: "Technical details"
        case .remove: "Remove…"
        }
    }

    var symbol: String {
        switch self {
        case .check: "arrow.clockwise"
        case .order: "list.number"
        case .signIn: "person.crop.circle.badge.checkmark"
        case .turnOn: "play.fill"
        case .turnOff: "pause.fill"
        case .key: "key"
        case .budget: "dollarsign.circle"
        case .up: "arrow.up"
        case .down: "arrow.down"
        case .limits: "slider.horizontal.3"
        case .rename: "pencil"
        case .tech: "info.circle"
        case .remove: "trash"
        }
    }

    /// ⌘K stays the launcher's, so Replace key is ⇧⌘K.
    var key: (KeyEquivalent, EventModifiers, String) {
        switch self {
        case .check: ("r", .command, "⌘R")
        case .order: ("o", .command, "⌘O")
        case .signIn: ("i", .command, "⌘I")
        case .turnOn, .turnOff: ("t", .command, "⌘T")
        case .key: ("k", [.command, .shift], "⇧⌘K")
        case .budget: ("b", .command, "⌘B")
        case .up: (.upArrow, [.command, .option], "⌥⌘↑")
        case .down: (.downArrow, [.command, .option], "⌥⌘↓")
        case .limits: ("l", .command, "⌘L")
        case .rename: ("e", .command, "⌘E")
        case .tech: ("d", .command, "⌘D")
        case .remove: (.delete, .command, "⌘⌫")
        }
    }
}

extension AccountsModel {
    /// The page's one main action for the state it is in.
    func primaryAction(_ a: AccountItem) -> DetailAction {
        switch detailState(a) {
        case .full: .order
        case .signedOut: .signIn
        case .off: .turnOn
        case .ready, .problem: .check
        }
    }

    /// What ⋯ holds: everything that applies, but the main action. A plan has no key; a key's check is the main action.
    func moreActions(_ a: AccountItem) -> [DetailAction] {
        let onOff: DetailAction = a.phase == .disabled ? .turnOn : .turnOff
        let own: [DetailAction] = a.isPlan ? [.check, .signIn, onOff] : [.check, .key, .budget, onOff]
        let order: [DetailAction] = aiOrderOn ? [.up, .down] : []
        return (own + order + [.limits, .rename, .tech, .remove]).filter { $0 != primaryAction(a) }
    }

    func enabled(_ act: DetailAction, _ a: AccountItem) -> Bool {
        switch act {
        case .order, .tech: return true
        case .check: return !readOnly && checking == nil && testing == nil
        case .up: return !readOnly && orderIDs.first != a.id
        case .down: return !readOnly && orderIDs.last != a.id
        default: return !readOnly && busy == nil
        }
    }

    func run(_ act: DetailAction, _ a: AccountItem) {
        guard enabled(act, a) else { return }
        detailMore = false
        switch act {
        case .check: Task { await checkNow(a) }
        case .order:
            cursor = "a-\(a.id)"
            go(.accounts)
        case .signIn, .key: AccountDialogs.openConnect(self, provider: a.provider, replacing: a)
        case .turnOn: Task { await setEnabled(a, true) }
        case .turnOff: Task { await setEnabled(a, false) }
        case .budget: openBudget(a)
        case .up: Task { await moveUp(a.id) }
        case .down: Task { await moveDown(a.id) }
        case .limits: AccountDialogs.openLimits(self, a)
        case .rename: AccountDialogs.openRename(self, a)
        case .tech: withAnimation(Motion.out(Motion.ui)) { detailTech.toggle() }
        case .remove:
            if aiOrderOn { Task { await removeWithUndo(a) } } else { AccountDialogs.openDelete(self, a) }
        }
    }
}

/// The main action as a button with its key, and ⋯ (⌘.) with the rest.
struct DetailActions: View {
    @Bindable var model: AccountsModel
    let account: AccountItem

    var body: some View {
        let main = model.primaryAction(account)
        let busy = model.checking == account.id || model.testing == account.id
        HStack(spacing: Space.s2) {
            Button {
                model.run(main, account)
            } label: {
                Label(busy ? "Checking…" : main.title, systemImage: main.symbol)
            }
            .buttonStyle(CoreButtonStyle(busy ? .secondary : .prominent))
            .keyboardShortcut(main.key.0, modifiers: main.key.1).environment(\.coreKeycap, main.key.2)
            .disabled(busy || !model.enabled(main, account))
            .detailSwap(main.title)
            CoreDropdown(
                items: model.moreActions(account).map { act in
                    CoreDropdownItem(
                        act.title, symbol: act.symbol, destructive: act == .remove,
                        enabled: model.enabled(act, account), note: act.key.2
                    ) { model.run(act, account) }
                }, isPresented: $model.detailMore
            ) {
                Image(systemName: "ellipsis").frame(width: MacSize.controlMd, height: MacSize.controlMd)
                    .background(GlassInk.well, in: coreShape(Radius.control))
                    .accessibilityLabel("More actions")
            }
            .help("More actions (⌘.)")
        }
    }
}

/// The keys of the actions inside ⋯, live on the page itself: ⌘. opens the menu, the others run at once.
struct DetailKeys: View {
    let model: AccountsModel
    let account: AccountItem

    var body: some View {
        ZStack {
            Button("") { model.detailMore.toggle() }.keyboardShortcut(".", modifiers: .command)
            ForEach(model.moreActions(account), id: \.self) { act in
                Button("") { model.run(act, account) }.keyboardShortcut(act.key.0, modifiers: act.key.1)
            }
        }
        .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
    }
}
