import SwiftUI

/// The footer of every dialog: the way back at the left edge (Esc), then the one action at the right (Return, or ⌘Return when
/// it removes something, so Return alone never destroys). With no `cancel` only the action shows, and Esc runs it.
public struct CoreDialogFooter: View {
    let confirm: String
    let cancelTitle: String
    let danger: Bool
    let busy: Bool
    let enabled: Bool
    let cancel: (() -> Void)?
    let run: () -> Void

    public init(
        confirm: String, cancelTitle: String = "Cancel", danger: Bool = false, busy: Bool = false, enabled: Bool = true,
        cancel: (() -> Void)?, run: @escaping () -> Void
    ) {
        self.confirm = confirm
        self.cancelTitle = cancelTitle
        self.danger = danger
        self.busy = busy
        self.enabled = enabled
        self.cancel = cancel
        self.run = run
    }

    public var body: some View {
        HStack(spacing: Space.s2) {
            if let cancel {
                Button(cancelTitle, action: cancel).buttonStyle(.coreSecondary).coreShortcut(.cancel)
            }
            Spacer(minLength: 0)
            primary
        }
        .onExitCommand { if cancel == nil { run() } }
    }

    @ViewBuilder private var primary: some View {
        if danger {
            Button(confirm, action: run).buttonStyle(CoreButtonStyle(.danger, busy: busy))
                .keyboardShortcut(.return, modifiers: .command).environment(\.coreKeycap, "⌘↩")
                .disabled(!enabled || busy)
        } else {
            Button(confirm, action: run).buttonStyle(CoreButtonStyle(.prominent, busy: busy))
                .coreShortcut(.primary).disabled(!enabled || busy)
        }
    }
}
