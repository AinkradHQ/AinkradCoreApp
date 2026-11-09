import CoreUI
import Shell
import SwiftUI

/// The Checks dialogs, shown over the shell like the New room sheet.
@MainActor
enum ChecksSheets {
    /// `only` nil is Run all (advanced); an id is one check.
    static func open(_ m: BrainModel, only: String?) {
        let shell = m.host.shell
        shell.present(
            ShellDialog(id: "brain-run-checks") { RunChecksSheet(model: m, only: only) { shell.closeDialog() } })
    }
}

/// Run (advanced): which checks, which rooms and how many test questions. The plain Run now uses the defaults: every
/// mounted room, 1,000 test questions.
struct RunChecksSheet: View {
    let model: BrainModel
    let only: String?
    let close: () -> Void
    @State private var checked: Set<String> = []
    @State private var rooms: Set<String> = []
    @State private var questions = 1000

    private var items: [CheckItem] { model.checks.report.items }
    private var title: String {
        only.flatMap { id in items.first { $0.id == id }?.name.lowercased() }.map { "Run \($0) with options" }
            ?? "Run all checks with options"
    }

    var body: some View {
        CoreDialogPanel(title, width: Space.s8 * 14) {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text(
                    "Choose what to run. The plain Run now uses the defaults: every mounted room, 1,000 test questions."
                )
                .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                if only == nil {
                    CoreFieldLabel("Checks")
                    ForEach(items) { c in CoreCheckbox(c.name, isOn: toggle(c.id, in: $checked)) }
                }
                CoreFieldLabel("Rooms")
                ForEach(model.mountedRooms) { r in CoreCheckbox(r.name, isOn: toggle(r.id, in: $rooms)) }
                CoreSelect(
                    "Test questions", selection: $questions,
                    options: [100, 1000, 5000].map { CoreSelectOption($0, $0.formatted()) })
                HStack(spacing: Space.s2) {
                    Spacer()
                    Button("Cancel", action: close).buttonStyle(CoreButtonStyle(.secondary))
                        .keyboardShortcut(.cancelAction)
                    Button("Run", action: go).buttonStyle(CoreButtonStyle(.prominent)).keyboardShortcut(.defaultAction)
                        .disabled(rooms.isEmpty || (only == nil && checked.isEmpty))
                }
            }
        }
        .onAppear {
            checked = Set(items.map(\.id))
            rooms = Set(model.mountedRooms.map(\.id))
        }
        .accessibilityIdentifier("brain-run-checks")
    }

    private func toggle(_ id: String, in set: Binding<Set<String>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(id) },
            set: { on in if on { set.wrappedValue.insert(id) } else { set.wrappedValue.remove(id) } })
    }

    private func go() {
        let all = Set(model.mountedRooms.map(\.id))
        let chosen = model.mountedRooms.map(\.id).filter(rooms.contains)
        let opts = CheckRunOptions(rooms: rooms == all ? nil : chosen, questions: questions)
        let ids = only.map { [$0] } ?? items.map(\.id).filter(checked.contains)
        close()
        Task { await model.checks.runAll(ids, options: opts) }
    }
}
