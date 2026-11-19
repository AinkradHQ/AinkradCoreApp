import CoreUI
import SwiftUI

/// New design (advanced): name, kind and project. The quick New design skips this sheet and uses the defaults. The Core's
/// refusal lands inline.
struct NewDesignView: View {
    let model: DesignModel
    @State private var name = DesignModel.defaultName(.design)
    @State private var kind = DesignDoc.Kind.design.rawValue
    @State private var project: String
    @State private var busy = false
    @State private var error: String?

    init(model: DesignModel) {
        self.model = model
        _project = State(initialValue: model.project ?? "")
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }
    private var valid: Bool { (1...100).contains(trimmed.count) }

    var body: some View {
        CoreDialogPanel("New design", width: Space.s8 * 11) {
            Text("It opens on a blank canvas. You can ask AI to draw on it any time.")
                .foregroundStyle(GlassInk.secondary)
            CoreTextField("Name", placeholder: "Welcome screen", text: $name, autofocus: true) { create() }
            VStack(alignment: .leading, spacing: Space.s1) {
                CoreFieldLabel("What are you making?")
                CoreSegmented(
                    "What are you making?",
                    segments: [
                        CoreSegment(DesignDoc.Kind.design.rawValue, "Design"),
                        CoreSegment(DesignDoc.Kind.system.rawValue, "Design system"),
                        CoreSegment(DesignDoc.Kind.mockup.rawValue, "Mockup"),
                    ],
                    selection: $kind)
            }
            CoreSelect(
                "Project", selection: $project,
                options: [CoreSelectOption("", "No project")]
                    + model.allProjects.map { CoreSelectOption($0.id, $0.name) })
            if let error { CoreFieldError(error) }
            HStack(spacing: Space.s2) {
                Button("Cancel") { model.host.shell.closeDialog() }
                    .buttonStyle(CoreButtonStyle(.secondary)).coreShortcut(.cancel)
                Spacer(minLength: Space.s2)
                Button("Create") { create() }
                    .buttonStyle(CoreButtonStyle(.prominent, busy: busy)).coreShortcut(.primary)
                    .disabled(!valid || busy).opacity(valid || busy ? 1 : 0.45)
            }
        }
        .foregroundStyle(GlassInk.primary)
        .onChange(of: kind) { old, new in
            // The suggested name follows the kind until the person has typed their own.
            if let o = DesignDoc.Kind(rawValue: old), name == DesignModel.defaultName(o),
                let n = DesignDoc.Kind(rawValue: new)
            {
                name = DesignModel.defaultName(n)
            }
        }
    }

    private func create() {
        guard valid, !busy, let k = DesignDoc.Kind(rawValue: kind) else { return }
        busy = true
        error = nil
        Task {
            error = await model.create(kind: k, name: trimmed, project: project.isEmpty ? nil : project, toast: false)
            busy = false
        }
    }
}
