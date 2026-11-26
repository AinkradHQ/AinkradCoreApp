import Admin
import CoreUI
import Shell
import SwiftUI

/// Rename and Delete for a card, an island row or the open item: each opens a small dialog; Delete asks for Touch ID (the
/// Core's step-up). A design is archived (the Core keeps every row); a library file or a brand kit is deleted.
extension DesignModel {
    func askRename(_ item: DesignItem) {
        guard !readOnly else {
            return host.shell.showToast("This device can look at designs but not change them.", kind: .warn)
        }
        host.shell.present(ShellDialog(id: "design-rename") { RenameDesignView(model: self, item: item) })
    }

    func askDelete(_ item: DesignItem) {
        guard !readOnly else {
            return host.shell.showToast("This device can look at designs but not change them.", kind: .warn)
        }
        host.shell.present(ShellDialog(id: "design-delete") { DeleteDesignView(model: self, item: item) })
    }

    /// Nil on success, else the Core's refusal in words (the dialog shows it).
    func rename(_ item: DesignItem, to name: String) async -> String? {
        guard let service else { return "Not connected to a Core." }
        if let why = host.pausedReason { return why }
        do {
            try await service.rename(item, to: name)
            host.shell.closeDialog()
            await reload()
            return nil
        } catch {
            return words(error)
        }
    }

    func remove(_ item: DesignItem) async -> String? {
        guard let service else { return "Not connected to a Core." }
        if let why = host.pausedReason { return why }
        do {
            try await host.elevated("Delete \(item.name).", done: "deleted", keepsEdit: false) {
                try await service.remove(item)
            }
            host.shell.closeDialog()
            if openID == item.id { closeItem() }
            if selected == item.id { selected = nil }
            await reload()
            host.shell.showToast("\(item.name) deleted")
            return nil
        } catch is AdminDeclined {
            return "Not deleted: Touch ID was not confirmed."
        } catch {
            return words(error)
        }
    }
}

struct RenameDesignView: View {
    let model: DesignModel
    let item: DesignItem
    @State private var name: String
    @State private var busy = false
    @State private var error: String?

    init(model: DesignModel, item: DesignItem) {
        self.model = model
        self.item = item
        _name = State(initialValue: item.name)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }
    private var valid: Bool { (1...100).contains(trimmed.count) && trimmed != item.name }

    var body: some View {
        CoreDialogPanel("Rename", width: Space.s8 * 12) {
            CoreTextField("Name", placeholder: item.name, text: $name, autofocus: true) { save() }
            if let error { CoreFieldError(error) }
            HStack(spacing: Space.s2) {
                Button("Cancel") { model.host.shell.closeDialog() }
                    .buttonStyle(CoreButtonStyle(.secondary)).coreShortcut(.cancel)
                Spacer(minLength: Space.s2)
                Button("Rename") { save() }
                    .buttonStyle(CoreButtonStyle(.prominent, busy: busy)).coreShortcut(.primary)
                    .disabled(!valid || busy).opacity(valid || busy ? 1 : 0.45)
            }
        }
        .foregroundStyle(GlassInk.primary)
        .accessibilityIdentifier("design-rename")
    }

    private func save() {
        guard valid, !busy else { return }
        busy = true
        error = nil
        Task {
            error = await model.rename(item, to: trimmed)
            busy = false
        }
    }
}

struct DeleteDesignView: View {
    let model: DesignModel
    let item: DesignItem
    @State private var busy = false
    @State private var error: String?

    private var line: String {
        switch item {
        case .doc:
            "It leaves Design and every project it is related to. The Core keeps it archived, so it is not lost."
        case .asset:
            "The file leaves the library and every project. A design or mockup that still uses it keeps it from going."
        case .kit: "The kit leaves the library. Its logos and fonts stay in the library."
        }
    }

    var body: some View {
        CoreDialogPanel("Delete \(item.name)?", width: Space.s8 * 13) {
            Text(line).foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            if let error { CoreFieldError(error) }
            HStack(spacing: Space.s2) {
                Button("Cancel") { model.host.shell.closeDialog() }
                    .buttonStyle(CoreButtonStyle(.secondary)).coreShortcut(.cancel)
                Spacer(minLength: Space.s2)
                Button("Delete") {
                    guard !busy else { return }
                    busy = true
                    error = nil
                    Task {
                        error = await model.remove(item)
                        busy = false
                    }
                }
                .buttonStyle(CoreButtonStyle(.danger, busy: busy)).coreShortcut(.primary)
                .disabled(busy)
            }
        }
        .foregroundStyle(GlassInk.primary)
        .accessibilityIdentifier("design-delete")
    }
}
