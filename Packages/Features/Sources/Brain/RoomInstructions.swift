import CoreUI
import SwiftUI

/// The instructions AI sessions read for this room: a draft until approved, then in use. Edit changes the text and Save
/// approves it; Approve takes it as written.
struct InstructionsCard: View {
    let o: RoomOverviewModel
    let room: String
    let overview: OverviewBody
    let approved: Bool
    let text: String
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                Text("Instructions for AI sessions").coreFont(size: MacTextSize.title, weight: .semibold)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Space.s3)
                if approved {
                    StateBadge("In use in this room", tone: .run, symbol: "checkmark")
                } else {
                    BrainChip(
                        "Not in use yet", GlassInk.slate, help: "AI sessions do not read these until you approve them.")
                }
            }
            if o.editing {
                CoreTextArea(
                    nil, placeholder: "Tell AI sessions how to work in this room", text: Bindable(o).draft,
                    minHeight: Space.s8 * 4, focus: $focused
                )
                .task { focused = true }
            } else {
                Text(text).coreFont(size: MacTextSize.body)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            HStack(spacing: Space.s2) {
                Spacer(minLength: Space.s3)
                if o.editing {
                    Button("Cancel") { o.cancelEdit() }.buttonStyle(CoreButtonStyle(.secondary))
                        .keyboardShortcut(.cancelAction)
                    Button("Save") { Task { await o.save(room) } }.buttonStyle(CoreButtonStyle(.prominent))
                        .disabled(!o.canSave)
                } else {
                    Button("Edit") { o.startEdit() }.buttonStyle(CoreButtonStyle(.secondary))
                    if !approved {
                        Button("Approve") { Task { await o.approve(room) } }
                            .buttonStyle(CoreButtonStyle(.prominent)).disabled(o.busy)
                    }
                }
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .coreWell()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("room-instructions")
    }
}
