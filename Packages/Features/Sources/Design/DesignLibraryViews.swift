import AppKit
import CoreUI
import Shell
import SwiftUI
import UniformTypeIdentifiers

/// The library's surfaces: dropping files, the upload strip, the bulk bar, Sort, Add and the extra menu entries.

/// Files dropped anywhere on the home go to the library (in the project being looked at, when there is one).
struct LibraryDrop: ViewModifier {
    let model: DesignModel
    @State private var over = false
    @Environment(\.coreAccent) private var paneAccent

    func body(content: Content) -> some View {
        content
            .dropDestination(for: URL.self) { urls, _ in
                let files = urls.filter(\.isFileURL)
                guard !files.isEmpty else { return false }
                Task { await model.lib.upload(files, project: model.project) }
                return true
            } isTargeted: {
                over = $0
            }
            .overlay {
                if over {
                    ZStack {
                        coreShape(Radius.pane).fill(GlassInk.accent(paneAccent).opacity(0.14))
                        Label("Drop to add to the library", systemImage: "square.and.arrow.down")
                            .coreFont(size: MacTextSize.title, weight: .semibold)
                    }
                    .padding(Space.s2).allowsHitTesting(false).transition(.opacity)
                }
            }
            .animation(Motion.out(Motion.ui), value: over)
    }
}

/// Files going up: a row each, with the Core's refusal in words.
struct UploadStrip: View {
    let model: DesignModel

    var body: some View {
        if !model.lib.uploads.isEmpty {
            VStack(alignment: .leading, spacing: Space.s1) {
                ForEach(model.lib.uploads) { job in
                    HStack(spacing: Space.s2) {
                        switch job.state {
                        case .uploading: ProgressView().controlSize(.small)
                        case .done: Image(systemName: "checkmark.circle").foregroundStyle(GlassInk.secondary)
                        case .failed:
                            Image(systemName: "exclamationmark.triangle").foregroundStyle(GlassInk.secondary)
                        }
                        Text(job.name).lineLimit(1)
                        Text(Self.words(job.state)).foregroundStyle(GlassInk.secondary).lineLimit(1)
                        Spacer(minLength: 0)
                        if case .failed = job.state {
                            CoreIconButton(symbol: "xmark", label: "Dismiss") {
                                model.lib.uploads.removeAll { $0.id == job.id }
                            }
                        }
                    }
                    .frame(minHeight: MacSize.controlSm)
                }
            }
            .padding(Space.s3).background(GlassInk.well, in: coreShape(Radius.pane))
            .padding(.horizontal, Space.s4).padding(.bottom, Space.s2)
            .transition(.opacity)
            .accessibilityIdentifier("design-uploads")
        }
    }

    static func words(_ s: DesignLibrary.UploadJob.State) -> String {
        switch s {
        case .uploading: "Uploading…"
        case .done(let dup): dup ? "Already in the library" : "Added"
        case .failed(let why): why
        }
    }
}

/// What a multi-selection can do: move, add to a kit, export, delete, clear.
struct BulkBar: View {
    let model: DesignModel
    @State private var move = false
    @State private var kit = false

    private var list: [DesignItem] { model.items.filter { model.lib.multi.contains($0.id) } }
    private var files: Bool {
        list.contains { if case .asset(let a) = $0 { a.check == .ok && a.kind != .font } else { false } }
    }

    var body: some View {
        if !model.lib.multi.isEmpty {
            HStack(spacing: Space.s2) {
                Text("\(model.lib.multi.count) selected").coreFont(size: MacTextSize.body, weight: .semibold)
                Spacer(minLength: 0)
                CoreDropdown(
                    items: model.allProjects.map { p in
                        CoreDropdownItem(p.name, symbol: "folder") { Task { await model.move(list, to: p) } }
                    }, isPresented: $move
                ) { Label("Move to project", systemImage: "folder") }
                .disabled(model.allProjects.isEmpty || model.readOnly)
                CoreDropdown(
                    items: model.kits.map { k in
                        CoreDropdownItem(k.name, symbol: "seal") { Task { await model.add(list, to: k) } }
                    }, isPresented: $kit
                ) { Label("Add to kit", systemImage: "seal") }
                .disabled(
                    model.kits.isEmpty || model.readOnly
                        || !list.contains { if case .asset = $0 { true } else { false } }
                )
                .help(model.kits.isEmpty ? "Make a brand kit first" : "Put the selected files into a kit")
                Button {
                    Task { await model.export(list) }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(CoreButtonStyle(.secondary)).disabled(!files)
                .help(files ? "Save the selected files" : "Only checked files can be exported")
                Button(role: .destructive) {
                    model.askDelete(list)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.coreQuietDanger).disabled(model.readOnly)
                Button("Clear") { model.lib.clearSelection() }.buttonStyle(CoreButtonStyle(.plain))
            }
            .padding(.horizontal, Space.s4).padding(.vertical, Space.s2)
            .background(GlassInk.well, in: coreShape(Radius.pane))
            .padding(.horizontal, Space.s4)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .accessibilityIdentifier("design-bulk-bar")
        }
    }
}

/// Sort: Recent or Name, favourites first.
struct LibrarySortMenu: View {
    let model: DesignModel
    @State private var open = false

    var body: some View {
        let lib = model.lib
        CoreDropdown(
            items: [
                CoreDropdownItem("Recent", symbol: "clock", checked: lib.sort == .recent) { lib.sort = .recent },
                CoreDropdownItem("Name", symbol: "textformat", checked: lib.sort == .name) { lib.sort = .name },
                CoreDropdownItem("Favourites first", symbol: "star", checked: lib.favouritesFirst) {
                    lib.favouritesFirst.toggle()
                },
            ], isPresented: $open
        ) {
            Image(systemName: "arrow.up.arrow.down")
        }
        .help("Sort: \(lib.sort == .recent ? "recent" : "name")\(lib.favouritesFirst ? ", favourites first" : "")")
        .accessibilityLabel("Sort")
        .accessibilityIdentifier("design-sort")
    }
}

/// Under the header on Library: Upload, New brand kit, New folder.
struct LibraryAddMenu: View {
    let model: DesignModel
    @State private var open = false

    var body: some View {
        CoreDropdown(
            items: [
                CoreDropdownItem("Upload files…", symbol: "square.and.arrow.down", note: "or drop them here") {
                    pickFiles()
                },
                CoreDropdownItem("New brand kit…", symbol: "seal") { ask(.brandKit) },
                CoreDropdownItem("New folder…", symbol: "folder") { ask(.folder) },
            ], isPresented: $open
        ) {
            Label("Add", systemImage: "plus")
        }
        .disabled(model.readOnly)
        .help("Upload files, or start a brand kit or a folder")
        .accessibilityIdentifier("design-library-add")
    }

    private func pickFiles() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.canChooseDirectories = false
        p.message = "Images, SVG, PDF and fonts, up to 25 MB each"
        p.allowedContentTypes = DesignLibrary.uploadTypes.compactMap { UTType(filenameExtension: $0) }
        guard p.runModal() == .OK else { return }
        Task { await model.lib.upload(p.urls, project: model.project) }
    }

    private func ask(_ kind: BrandKit.Kind) {
        model.host.shell.present(ShellDialog(id: "new-kit") { NewKitView(model: model, kind: kind) })
    }
}

struct NewKitView: View {
    let model: DesignModel
    let kind: BrandKit.Kind
    @State private var name = ""
    @State private var busy = false
    @State private var error: String?

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }
    private var valid: Bool { (1...100).contains(trimmed.count) }
    private var word: String { kind == .folder ? "folder" : "brand kit" }

    var body: some View {
        CoreDialogPanel("New \(word)", width: Space.s8 * 12) {
            CoreTextField(
                "Name", placeholder: kind == .folder ? "Illustrations" : "Acme brand kit", text: $name, autofocus: true
            ) {
                make()
            }
            if let error { CoreFieldError(error) }
            HStack(spacing: Space.s2) {
                Button("Cancel") { model.host.shell.closeDialog() }
                    .buttonStyle(CoreButtonStyle(.secondary)).coreShortcut(.cancel)
                Spacer(minLength: Space.s2)
                Button("Create") { make() }
                    .buttonStyle(CoreButtonStyle(.prominent, busy: busy)).coreShortcut(.primary)
                    .disabled(!valid || busy).opacity(valid || busy ? 1 : 0.45)
            }
        }
        .foregroundStyle(GlassInk.primary)
        .accessibilityIdentifier("design-new-kit")
    }

    private func make() {
        guard valid, !busy else { return }
        busy = true
        error = nil
        Task {
            error = await model.createKit(kind, name: trimmed)
            if error == nil { model.host.shell.closeDialog() }
            busy = false
        }
    }
}

/// A note over the archived page.
struct ArchivedNote: View {
    let model: DesignModel

    var body: some View {
        if model.category == .archived {
            HStack(spacing: Space.s2) {
                Image(systemName: "archivebox").foregroundStyle(GlassInk.secondary)
                Text(
                    model.lib.restoreSupported
                        ? "Archived designs are kept by the Core. Right-click one to restore it."
                        : "Archived designs are kept by the Core. Restoring needs a Core update, so they are read-only here."
                )
                .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                if let e = model.lib.archivedError { Text(e).foregroundStyle(GlassInk.secondary) }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.s4).padding(.bottom, Space.s3)
            .accessibilityIdentifier("design-archived-note")
        }
    }
}

/// The card menu's library entries: favourites, copy, export, and what a selection can do together.
struct DesignMenuExtras: View {
    let model: DesignModel
    let item: DesignItem

    var body: some View {
        let list = model.targets(item)
        Divider()
        Button(model.lib.isFavourite(item) ? "Remove from favourites" : "Add to favourites") {
            model.lib.toggleFavourite(item)
        }
        if list.count == 1 {
            if canCopy { Button("Duplicate") { Task { await model.duplicate(item) } }.disabled(model.readOnly) }
            if case .asset(let a) = item, a.check == .ok, a.kind != .font {
                Button("Export…") { Task { await model.export([item]) } }
            }
        } else {
            Menu("Move \(list.count) items to") {
                ForEach(model.allProjects) { p in Button(p.name) { Task { await model.move(list, to: p) } } }
            }
            .disabled(model.allProjects.isEmpty || model.readOnly)
            Menu("Add files to kit") {
                ForEach(model.kits) { k in Button(k.name) { Task { await model.add(list, to: k) } } }
            }
            .disabled(model.kits.isEmpty || model.readOnly)
            Button("Export files…") { Task { await model.export(list) } }
        }
    }

    private var canCopy: Bool {
        switch item {
        case .doc(let d): d.kind == .design
        case .kit: true
        case .asset: false
        }
    }
}
