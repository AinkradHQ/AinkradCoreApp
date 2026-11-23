import CoreUI
import Shell
import SwiftUI

extension BrainSheets {
    /// New Rule… (⌘N), or Edit Rule… with the rule to change: the change is written as a new rule and the old one is
    /// forgotten (archived, never deleted).
    static func rule(_ m: BrainModel, editing: BrainAreaRecordWire? = nil) {
        let shell = m.host.shell
        shell.present(ShellDialog(id: "brain-rule") { RuleSheet(model: m, editing: editing) { shell.closeDialog() } })
    }

}

/// Write a rule in your own words, say what kind it is and where it applies.
struct RuleSheet: View {
    let model: BrainModel
    let editing: BrainAreaRecordWire?
    let close: () -> Void
    @State private var text = ""
    @State private var kind = RuleKind.always.rawValue
    @State private var place = ""
    @State private var busy = false

    private var typed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        CoreDialogPanel(editing == nil ? "New Rule" : "Edit Rule", width: Space.s8 * 16) {
            VStack(alignment: .leading, spacing: Space.s3) {
                CoreTextField(
                    "Rule", placeholder: "For example, Ask before deleting anything outside the project", text: $text,
                    autofocus: true
                ) { save() }
                CoreSegmented(
                    "Kind", segments: RuleKind.allCases.map { CoreSegment($0.rawValue, $0.title, symbol: $0.symbol) },
                    selection: $kind, fill: true)
                CoreSelect(
                    "Applies to", selection: $place,
                    options: [CoreSelectOption("", "Everywhere", symbol: "globe")]
                        + model.rooms.filter(\.mounted).map { CoreSelectOption($0.id, $0.name, symbol: "folder") })
                Text("Brain follows it from the next AI session on. You can turn it off or forget it any time.")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                CoreDialogFooter(
                    cancel: CoreAction("Cancel", key: .cancel, run: close),
                    primary: CoreAction(editing == nil ? "Add Rule" : "Save Rule", key: .primary) { save() },
                    busy: busy, enabled: !typed.isEmpty)
            }
        }
        .onAppear {
            guard let r = editing else { return }
            text = r.body
            kind = r.kind ?? (r.type == "preference" ? RuleKind.prefer.rawValue : RuleKind.always.rawValue)
            place = r.everywhere == true ? "" : r.room
        }
        .accessibilityIdentifier("brain-rule-sheet")
    }

    private func save() {
        guard !typed.isEmpty, !busy else { return }
        busy = true
        Task {
            let n = await model.calm.newRule(typed, kind: kind, rooms: place.isEmpty ? nil : [place])
            if n != nil, let old = editing { await model.calm.forget(old) }
            busy = false
            guard let n else { return }
            close()
            model.host.shell.showToast(
                n == 0
                    ? "Every place has this rule already"
                    : editing == nil
                        ? (n == 1 ? "Rule added" : "Rule added to \(n) places") : "Rule changed",
                kind: n == 0 ? .info : .ok)
        }
    }
}
