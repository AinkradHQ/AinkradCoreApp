import CoreUI
import SwiftUI

/// New design (advanced): name, kind and project. The quick New design skips this sheet and uses the defaults. The Core's
/// refusal lands inline.
struct NewDesignView: View {
    let model: DesignModel
    @State private var name = DesignModel.defaultName(.design)
    @State private var kind = DesignDoc.Kind.design.rawValue
    @State private var project: String
    /// The design system a new design follows (designs only); empty for none.
    @State private var system = ""
    @State private var busy = false
    /// Mockup: the design to present.
    @State private var source = ""
    @State private var error: String?

    init(model: DesignModel) {
        self.model = model
        _project = State(initialValue: model.project ?? "")
    }

    /// The mockup's three kind tiles.
    static let kinds: [(DesignDoc.Kind, String, String, String)] = [
        (.design, "Design", "rectangle.dashed", "A screen or page"),
        (.system, "Design system", "paintpalette", "Colours, type and parts"),
        (.mockup, "Mockup", "iphone", "A design in a device, clickable"),
    ]

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }
    private var designs: [DesignDoc] { model.docs.filter { $0.kind == .design } }
    private var systems: [DesignDoc] { model.docs.filter { $0.kind == .system } }
    private var mockup: Bool { kind == DesignDoc.Kind.mockup.rawValue }
    private var valid: Bool { mockup ? designs.contains { $0.id == source } : (1...100).contains(trimmed.count) }

    var body: some View {
        CoreDialogPanel("New design", width: Space.s8 * 14) {
            Text("It opens on a blank canvas. You can ask AI to draw on it any time.")
                .foregroundStyle(GlassInk.secondary)
            if !mockup {
                CoreTextField("Name", placeholder: "Welcome screen", text: $name, autofocus: true) { create() }
            }
            VStack(alignment: .leading, spacing: Space.s1) {
                CoreFieldLabel("What are you making?")
                HStack(alignment: .top, spacing: Space.s2) {
                    ForEach(Self.kinds, id: \.0.rawValue) { k, title, symbol, line in
                        Button {
                            kind = k.rawValue
                        } label: {
                            VStack(alignment: .leading, spacing: Space.s1) {
                                Image(systemName: symbol).coreFont(size: MacTextSize.title)
                                    .foregroundStyle(kind == k.rawValue ? Color.accentColor : GlassInk.secondary)
                                Text(title).coreFont(size: MacTextSize.body, weight: .semibold)
                                Text(line).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(Space.s3)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .coreCard(
                                kind == k.rawValue ? Color.accentColor.opacity(0.16) : GlassInk.well,
                                radius: Radius.pane)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(kind == k.rawValue ? .isSelected : [])
                    }
                }
                // Every tile as tall as the tallest, whatever its words wrap to.
                .fixedSize(horizontal: false, vertical: true)
            }
            if mockup {
                if designs.isEmpty {
                    Text("Make a design first: a mockup shows one of your designs in a device.")
                        .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    CoreSelect(
                        "Which design?", selection: $source,
                        options: designs.map { CoreSelectOption($0.id, $0.name) })
                    Text(
                        "It opens in Present: pick the device and backdrop, click through its prototype links, export a PNG."
                    )
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                CoreSelect(
                    "Project", selection: $project,
                    options: [CoreSelectOption("", "No project")]
                        + model.allProjects.map { CoreSelectOption($0.id, $0.name) })
            }
            if kind == DesignDoc.Kind.design.rawValue, !systems.isEmpty {
                CoreSelect(
                    "Design system", selection: $system,
                    options: [CoreSelectOption("", "None")] + systems.map { CoreSelectOption($0.id, $0.name) })
            }
            if let error { CoreFieldError(error) }
            HStack(spacing: Space.s2) {
                Button("Cancel") { model.host.shell.closeDialog() }
                    .buttonStyle(CoreButtonStyle(.secondary)).coreShortcut(.cancel)
                Spacer(minLength: Space.s2)
                Button(mockup ? "Present" : "Create") { create() }
                    .buttonStyle(CoreButtonStyle(.prominent, busy: busy)).coreShortcut(.primary)
                    .disabled(!valid || busy).opacity(valid || busy ? 1 : 0.45)
            }
        }
        .foregroundStyle(GlassInk.primary)
        .onAppear { if source.isEmpty { source = designs.first?.id ?? "" } }
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
        if mockup, let d = designs.first(where: { $0.id == source }) {
            model.host.shell.closeDialog()
            model.openItem(DesignItem.doc(d).id)
            model.present(d)
            return
        }
        guard valid, !busy, let k = DesignDoc.Kind(rawValue: kind) else { return }
        busy = true
        error = nil
        Task {
            error = await model.create(
                kind: k, name: trimmed, project: project.isEmpty ? nil : project,
                system: k == .design && !system.isEmpty ? system : nil, toast: false)
            busy = false
        }
    }
}
