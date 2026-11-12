import AppKit
import CoreUI
import Shell
import SwiftUI
import UniformTypeIdentifiers

/// A file chooser and drop zone for a secret's value. It shows the file name, size and type, never the content.
struct FileDrop: View {
    let form: SecretForm
    let prompt: String
    @Binding var error: String?
    @State private var over = false
    @Environment(\.corePalette) private var palette

    var body: some View {
        Button(action: choose) {
            HStack(spacing: Space.s3) {
                IconTile(form.fileName == nil ? "arrow.down.doc" : "doc.fill", hue: GlassInk.blue, size: 32)
                VStack(alignment: .leading, spacing: 0) {
                    Text(form.fileName ?? prompt).fontWeight(.semibold).lineLimit(1)
                    Text(
                        form.fileName == nil
                            ? "Up to 1 MB. Ainkrad never shows what is inside."
                            : "\(form.fileKindWord ?? "file") · \(SecretWords.size(form.fileSize ?? 0)). Choose another to replace it."
                    )
                    .foregroundStyle(palette.text2)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s3)
            .background(over ? GlassInk.wellHover : GlassInk.well, in: coreShape(Radius.cardMac))
            .overlay {
                coreShape(Radius.cardMac).strokeBorder(over ? GlassInk.blue : GlassInk.wellEdge, lineWidth: 1)
            }
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(.plain)
        .onDrop(of: [.fileURL], isTargeted: $over) { providers in
            guard let p = providers.first else { return false }
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in error = form.setFile(url) }
            }
            return true
        }
        .accessibilityLabel(prompt)
        .accessibilityIdentifier("secret-file-drop")
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        error = form.setFile(url)
    }
}

/// New group, or edit one: a name (new only), what it is for, and which runners its secrets get. The Core has no rename.
struct GroupDialog: View {
    let admin: AdminModel
    let existing: SecretGroupItem?
    let close: () -> Void
    @State private var name: String
    @State private var about: String
    @State private var runners: Set<String>
    @State private var issue: String?
    @State private var busy = false
    @Environment(\.corePalette) private var palette

    init(admin: AdminModel, existing: SecretGroupItem?, close: @escaping () -> Void) {
        self.admin = admin
        self.existing = existing
        self.close = close
        _name = State(initialValue: existing?.name ?? "")
        _about = State(initialValue: existing?.description ?? "")
        _runners = State(initialValue: Set(existing?.runners ?? []))
    }

    var body: some View {
        let model = admin.secrets!
        CoreDialogPanel(existing.map { "Edit \($0.name)" } ?? "New group", width: Space.s8 * 16) {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("A group keeps related secrets together. Its runners can use all of them, in one step.")
                    .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                if existing == nil {
                    CoreTextField("Name", placeholder: "e.g. aws-production", text: $name, autofocus: true)
                }
                CoreTextField("What is it for?", placeholder: "e.g. Keys for the production account", text: $about)
                VStack(alignment: .leading, spacing: Space.s1) {
                    CoreFieldLabel("Runners that may use it")
                    HStack(spacing: Space.s2) {
                        ForEach(model.runners) { r in
                            let on = runners.contains(r.id)
                            Button {
                                if on { runners.remove(r.id) } else { runners.insert(r.id) }
                            } label: {
                                Label(r.name, systemImage: on ? "checkmark" : "server.rack")
                                    .padding(.horizontal, Space.s2).padding(.vertical, Space.s1)
                                    .background(
                                        on ? GlassInk.blue.opacity(0.2) : GlassInk.wellHover, in: coreShape(7))
                            }
                            .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                }
                if let issue { IssueLine(code: nil, text: issue) }
                AdminNoticeBanner(notice: admin.host.elevationNotice)
                HStack(spacing: Space.s2) {
                    Button("Cancel", action: close).buttonStyle(.coreSecondary).coreShortcut(.cancel)
                    Spacer(minLength: 0)
                    Button(existing == nil ? "Make group" : "Save", action: save)
                        .buttonStyle(CoreButtonStyle(.prominent, busy: busy)).coreShortcut(.primary).disabled(busy)
                }
            }
        }
        .accessibilityIdentifier("secret-group")
    }

    private func save() {
        busy = true
        Task {
            let why = await admin.secrets.saveGroup(
                name: existing?.name ?? name, description: about.trimmingCharacters(in: .whitespacesAndNewlines),
                runners: runners.sorted(), existing: existing != nil)
            busy = false
            if let why { issue = why.isEmpty ? nil : why } else { close() }
        }
    }
}

struct DeleteGroupDialog: View {
    let admin: AdminModel
    let group: SecretGroupItem
    let close: () -> Void
    @State private var issue: String?
    @State private var busy = false
    @Environment(\.corePalette) private var palette

    var body: some View {
        CoreDialogPanel("Delete the group \(group.name)?", width: Space.s8 * 16) {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text(
                    group.members.isEmpty
                        ? "The group is empty. This cannot be undone."
                        : "\(group.members.count) secret\(group.members.count == 1 ? " is" : "s are") in it: \(group.members.joined(separator: ", ")). The Core may refuse until they are moved or deleted."
                )
                .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                if let issue { IssueLine(code: nil, text: issue) }
                AdminNoticeBanner(notice: admin.host.elevationNotice)
                HStack(spacing: Space.s2) {
                    Button("Cancel", action: close).buttonStyle(.coreSecondary).coreShortcut(.cancel)
                    Spacer(minLength: 0)
                    Button("Delete with Touch ID") {
                        busy = true
                        Task {
                            let why = await admin.secrets.deleteGroup(group)
                            busy = false
                            if let why { issue = why.isEmpty ? nil : why } else { close() }
                        }
                    }
                    .buttonStyle(CoreButtonStyle(.danger)).disabled(busy)
                }
            }
        }
        .accessibilityIdentifier("secret-group-delete")
    }
}
