import CoreUI
import Projects
import SwiftUI

/// Files: the host's folders over SFTP. Click a folder to go in, a file to see it; drag files in from Finder to upload and a
/// file out to Finder to download. A file that usually holds secrets is not drawn until Touch ID says so. Nothing is edited
/// here, and a link is shown, never followed.
struct HostFilesPage: View {
    let state: HostPageState
    @State private var settled = false

    var body: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            FolderIsland(state: state).coreRise(settled, 0)
            PreviewIsland(state: state).coreRise(settled, 1)
        }
        .onAppear { settled = true }
        .task { if state.entries.value == nil { await state.loadFiles() } }
        .accessibilityIdentifier("host-page-Files")
    }
}

private struct FolderIsland: View {
    let state: HostPageState
    @State private var over = false

    var body: some View {
        Island(
            title: state.path, sub: "\(state.host?.name ?? "") · SFTP",
            accessory: {
                HStack(spacing: Space.s2) {
                    Button {
                        state.chooseUpload()
                    } label: {
                        Label("Upload…", systemImage: "arrow.up")
                    }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                    .disabled(state.model.readOnly).help("Choose files to send to this folder")
                    CoreIconButton(symbol: "arrow.clockwise", label: "Reload this folder") {
                        Task { await state.loadFiles() }
                    }
                }
            }
        ) {
            VStack(alignment: .leading, spacing: Space.s2) {
                crumbs
                list
                drop
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            state.upload(urls)
            return true
        } isTargeted: {
            over = $0
        }
        .accessibilityIdentifier("files-folder")
    }

    private var crumbs: some View {
        HStack(spacing: Space.s1) {
            ForEach(Array(RemotePath.crumbs(state.path).enumerated()), id: \.offset) { i, c in
                if i > 0 {
                    Image(systemName: "chevron.right").coreFont(size: MacTextSize.meta).accessibilityHidden(true)
                }
                Button {
                    Task { await state.loadFiles(c.path) }
                } label: {
                    CoreChip(c.name, minWidth: 0)
                }
                .buttonStyle(.plain).help("Go to \(c.path)").accessibilityLabel(c.path)
            }
        }
    }

    @ViewBuilder private var list: some View {
        switch state.entries {
        case .idle, .loading: CoreSkeleton().frame(height: Space.s8 * 3)
        case .missing: Text(HostWords.gone("Browsing files")).foregroundStyle(GlassInk.secondary)
        case .failed(let why):
            CoreNotice(symbol: "exclamationmark.triangle", title: "This folder did not open", text: why, tone: .warn) {
                if state.path != "/" {
                    Button("Up") { Task { await state.loadFiles(RemotePath.parent(state.path)) } }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                }
            }
        case .ready(let files):
            if files.isEmpty {
                Text("This folder is empty. Drag files in to upload.").foregroundStyle(GlassInk.secondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: Space.s1) {
                        ForEach(files) { f in
                            CoreRow(
                                f.isFolder ? f.name + "/" : f.name, subtitle: line(f),
                                symbol: f.isFolder ? "folder" : f.kind == .link ? "link" : "doc",
                                selected: state.selected == f
                            ) {
                                state.open(f)
                            }
                            .onDrag { state.dragProvider(f) }
                            .accessibilityIdentifier("file-\(f.name)")
                        }
                    }
                }
            }
        }
    }

    private func line(_ f: RemoteFile) -> String {
        if f.kind == .link { return "→ \(f.target ?? "?")" }
        let parts = [f.isFolder ? nil : HostWords.size(f.size), f.modified.map { HostWords.ago($0) }]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    private var drop: some View {
        Group {
            if let t = state.transfer {
                HStack(spacing: Space.s2) {
                    CoreWorkingBar()
                    Text(t).foregroundStyle(GlassInk.secondary)
                }
            } else {
                Text("Drag files from Finder to upload · drag a file out to download").foregroundStyle(
                    GlassInk.secondary)
            }
        }
        .frame(maxWidth: .infinity).padding(Space.s3).coreWell(active: over)
        .accessibilityLabel("Drop files here to upload")
    }
}

private struct PreviewIsland: View {
    let state: HostPageState

    var body: some View {
        Island(
            title: state.selected?.name ?? "Preview", sub: state.selected.map { HostWords.size($0.size) },
            accessory: {
                if let f = state.selected, f.kind == .file {
                    Button("Download") { Task { await state.download(f) } }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small)).help("Save \(f.name) on this Mac")
                }
            }
        ) {
            content
        }
        .accessibilityIdentifier("files-preview")
    }

    @ViewBuilder private var content: some View {
        if let f = state.selected {
            if f.kind == .link {
                Text("A link to \(f.target ?? "somewhere"). Links are shown, not followed.")
                    .foregroundStyle(GlassInk.secondary)
            } else if state.isLocked(f) {
                VStack(alignment: .leading, spacing: Space.s3) {
                    Label("This file may hold secrets, so it isn’t shown.", systemImage: "lock")
                        .foregroundStyle(GlassInk.secondary)
                    Button {
                        Task { await state.reveal(f) }
                    } label: {
                        Label("Show with Touch ID", systemImage: "touchid")
                    }
                    .buttonStyle(CoreButtonStyle(.secondary))
                }
            } else {
                switch state.preview {
                case .idle, .missing:
                    Text("Not shown: it is large or not text. Download it to read it.").foregroundStyle(
                        GlassInk.secondary)
                case .loading: CoreWorkingBar()
                case .failed(let why): Text(why).foregroundStyle(GlassInk.secondary)
                case .ready(let text):
                    ScrollView {
                        Text(
                            text.split(separator: "\n", omittingEmptySubsequences: false).prefix(400).joined(
                                separator: "\n")
                        )
                        .coreFont(size: MacTextSize.meta, design: .monospaced).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(Space.s3).coreWell()
                }
            }
        } else {
            Text("Select a file to see it here.").foregroundStyle(GlassInk.secondary)
        }
    }
}
