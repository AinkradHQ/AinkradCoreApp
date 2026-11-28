import CoreUI
import SwiftUI

/// A type tile of "What it is": the kind's icon, name and what it adds, with a check box. Several may be on.
struct SettingsKindTile: View {
    let kind: ProjectKind
    let on: Bool
    let action: () -> Void
    @State private var hover = false

    static func name(_ k: ProjectKind) -> String {
        switch k {
        case .web: "Web"
        case .app: "App"
        case .infra: "Infra"
        case .other: "Not software"
        }
    }

    static func adds(_ k: ProjectKind) -> String {
        switch k {
        case .web: "Live site, link"
        case .app: "Builds, devices"
        case .infra: "Services, health"
        case .other: "Documents only"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s3) {
                Image(systemName: kind.symbol).foregroundStyle(on ? GlassInk.blue : GlassInk.secondary)
                    .frame(width: Space.s5).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(Self.name(kind)).coreFont(size: MacTextSize.body, weight: .semibold)
                    Text(Self.adds(kind)).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                }
                Spacer(minLength: 0)
                coreShape(4).fill(on ? GlassInk.blue : GlassInk.track).frame(width: Space.s4, height: Space.s4)
                    .overlay {
                        if on { Image(systemName: "checkmark").coreFont(size: 9, weight: .bold).foregroundStyle(.white) }
                    }
            }
            .padding(.horizontal, Space.s3).padding(.vertical, Space.s2 + 2)
            .background(coreShape(Radius.row).fill(on ? GlassInk.blue.opacity(0.16) : hover ? GlassInk.wellHover : GlassInk.well))
            .contentShape(coreShape(Radius.row))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(Motion.out(Motion.ui)) { hover = h } }
        .accessibilityLabel("\(Self.name(kind)), \(Self.adds(kind))")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Archive or delete, each with its words; Delete asks for the project's name first.
struct ArchiveDeleteBlock: View {
    let model: ProjectsModel
    let project: ProjectItem
    @State private var confirming = false
    @State private var typed = ""

    private var matches: Bool { typed.trimmingCharacters(in: .whitespaces) == project.name }

    var body: some View {
        PgBlock("Archive or delete") {
            VStack(alignment: .leading, spacing: Space.s3) {
                line(
                    "Archive",
                    model.insightsService == nil
                        ? "Stops it and hides it. Repos, secrets and the Brain room stay. This Core cannot bring it back from here."
                        : "Stops it and hides it. Repos, secrets and the Brain room stay. Undo for a few seconds.",
                    button: "Archive…", symbol: "archivebox", danger: false
                ) {
                    if model.insightsService == nil {
                        model.confirmArchive(project)
                    } else {
                        Task { await model.archive(project) }
                    }
                }
                if model.core112 {
                    line(
                        "Delete permanently",
                        "Removes the project, its copies and runs. Your repos stay on GitHub and the Brain room stays.",
                        button: "Delete…", symbol: "trash", danger: true,
                        block: model.isRunningOrStarting(project) ? "Stop it first." : nil
                    ) { withAnimation(Motion.out(Motion.ui)) { confirming = true } }
                    if confirming { confirm }
                }
            }
        }
    }

    private func line(
        _ title: String, _ sub: String, button: String, symbol: String, danger: Bool, block: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(sub).foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(action: action) { Label(button, systemImage: symbol) }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                .foregroundStyle(danger ? GlassInk.red : GlassInk.primary)
                .disabled(model.readOnly || model.busy || block != nil)
                .help(model.readOnly ? "This device can look at projects but not change them." : block ?? sub)
        }
    }

    private var confirm: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            CoreTextField(
                "Type “\(project.name)” to delete it for good", placeholder: project.name, text: $typed,
                error: typed.isEmpty || matches ? nil : "That is not the project’s name.")
            HStack(spacing: Space.s2) {
                Spacer(minLength: 0)
                Button("Cancel") {
                    withAnimation(Motion.out(Motion.ui)) {
                        confirming = false
                        typed = ""
                    }
                }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                Button("Delete Permanently") { Task { await model.deleteForever(project) } }
                    .buttonStyle(CoreButtonStyle(.prominent, size: .small, busy: model.busy))
                    .disabled(!matches || model.busy)
                    .help(matches ? "Delete \(project.name) for good" : "Type the project’s name first")
            }
        }
        .padding(Space.s3).coreCard(GlassInk.well, radius: Radius.row)
        .transition(.opacity)
    }
}
