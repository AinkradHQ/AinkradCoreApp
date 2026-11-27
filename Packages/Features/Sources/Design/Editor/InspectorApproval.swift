import CoreUI
import SwiftUI

/// The inspector's Approval section for a screen (a top-level frame): approve it, or clear the approval. The Core freezes
/// the design at that moment; later edits show as "changed since approved". Nothing here for other layers.
struct ApprovalBlock: View {
    let editor: DesignEditor
    let node: EditorNode
    @Environment(DesignCollab.self) private var collab: DesignCollab?
    @State private var busy = false

    private var isScreen: Bool {
        ["frame", "component"].contains(node.type) && node.parent.flatMap { editor.layers[$0]?.type } == "page"
    }

    var body: some View {
        if isScreen, let collab, let model = collab.model {
            let a = collab.approval(editor.doc, screen: node.id)
            InspectorBlock("Approval") {
                HStack(spacing: Space.s2) {
                    switch a?.state {
                    case .approved:
                        StateBadge("Approved", tone: .done, symbol: "checkmark.circle")
                    case .changed:
                        StateBadge("Changed since approved", tone: .queue, symbol: "pencil.circle")
                    default:
                        Text("Not approved").foregroundStyle(GlassInk.secondary)
                    }
                    Spacer(minLength: 0)
                }
                if let a, a.state != .other {
                    Text("\(AboutIsland.who(a.decidedBy)) · \(Ago.words(a.decidedAt))")
                        .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                }
                HStack(spacing: Space.s2) {
                    Button(a?.state == .changed ? "Approve again" : "Approve") {
                        run { await collab.approve(doc: editor.doc, screen: node.id) }
                    }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small, busy: busy))
                    .disabled(a?.state == .approved || busy || model.readOnly)
                    .help(
                        model.readOnly
                            ? "This device can look at designs but not change them."
                            : "Keep this screen as it is now; the Core remembers it")
                    if a != nil {
                        Button("Clear") { run { await collab.withdraw(doc: editor.doc, screen: node.id) } }
                            .buttonStyle(CoreButtonStyle(.plain, size: .small))
                            .disabled(busy || model.readOnly)
                            .help("Take the approval back")
                    }
                }
                if let e = collab.error { CoreFieldError(e) }
            }
            .accessibilityIdentifier("design-approval")
        }
    }

    private func run(_ work: @escaping () async -> Void) {
        busy = true
        Task {
            await work()
            busy = false
        }
    }
}
