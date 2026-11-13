import AppKit
import BrainImport
import CoreUI
import SwiftUI

/// What the "Where to look" block says, in one place so a test can read it.
enum WhereWords {
    static let noFolders = "No folders yet. Add the folders where your projects and notes live."
    static let diskAbout =
        "Looks through your home folder for docs, READMEs, AGENTS.md and CLAUDE.md files and Obsidian vaults. System folders, caches and hidden folders are left out."
    static let noteVaults = "Notes are read from folders that hold an Obsidian vault."

    static func searching(_ n: Int) -> String { "Searching… \(n.formatted()) files checked" }

    /// How a search ended: "Checked 48,210 files." or why it stopped early.
    static func searched(_ f: DocWalker.Found) -> String {
        let n = f.checked.formatted()
        switch f.stopped {
        case "files": return "Stopped at \(n) files. Choose folders to narrow it down."
        case "time": return "Stopped after 3 minutes at \(n) files. Choose folders to narrow it down."
        case "cancelled": return "Stopped at \(n) files."
        default: return "Checked \(n) files."
        }
    }

    static func notAllowed(_ n: Int) -> String {
        "\(BrainWords.plural(n, "folder was", "folders were")) not allowed. Allow access in System Settings › Privacy & Security."
    }

    static func tilde(_ url: URL) -> String { (url.path as NSString).abbreviatingWithTildeInPath }
}

/// The Notes and docs choice: folders the person adds, or a search of the home folder.
struct WhereBlock: View {
    let model: ImportModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            CoreSegmented(
                "Where to look",
                segments: [
                    CoreSegment(ImportPlaces.Mode.folders, "Folders I choose", symbol: "folder"),
                    CoreSegment(.disk, "Search the whole disk", symbol: "internaldrive"),
                ],
                selection: Binding(get: { model.mode }, set: { model.setMode($0) }), fill: true
            )
            .accessibilityIdentifier("brain-import-where")
            switch model.mode {
            case .folders: FoldersPart(model: model)
            case .disk: DiskPart(model: model)
            }
            if model.notAllowed > 0 {
                Text(WhereWords.notAllowed(model.notAllowed)).coreFont(size: MacTextSize.meta)
                    .foregroundStyle(GlassInk.secondary)
            }
        }
        .padding(.horizontal, Space.s3)
        .padding(.bottom, Space.s2)
    }
}

private struct FoldersPart: View {
    let model: ImportModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if model.folders.isEmpty {
                Text(WhereWords.noFolders).coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
            } else {
                VStack(spacing: 2) {
                    ForEach(model.folders, id: \.path) { f in
                        CoreRow(f.lastPathComponent, subtitle: WhereWords.tilde(f), symbol: "folder") {
                            Button("Remove") { model.removeFolder(f) }
                                .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                                .help("Stop reading \(f.lastPathComponent)")
                        }
                    }
                }
            }
            HStack(spacing: Space.s2) {
                Button("Add Folder…") { Self.choose { model.addFolders($0) } }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                    .help("Choose folders with your projects or notes")
                    .accessibilityIdentifier("brain-import-add-folder")
                if !model.suggestions.isEmpty {
                    Text("Found here").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    ForEach(model.suggestions, id: \.path) { s in
                        Button {
                            model.addFolders([s])
                        } label: {
                            Label(s.lastPathComponent, systemImage: "plus").lineLimit(1)
                        }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                        .help("Add \(WhereWords.tilde(s))")
                    }
                }
                Spacer(minLength: 0)
            }
            Text(WhereWords.noteVaults).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
        }
    }

    /// The system folder picker: directories only, several at once.
    @MainActor static func choose(_ done: ([URL]) -> Void) {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.allowsMultipleSelection = true
        p.prompt = "Add"
        guard p.runModal() == .OK else { return }
        done(p.urls)
    }
}

private struct DiskPart: View {
    let model: ImportModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(WhereWords.diskAbout).coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.s3) {
                if model.searching {
                    CoreWorkingBar()
                    Text(WhereWords.searching(model.checked)).coreFont(size: MacTextSize.meta)
                        .foregroundStyle(GlassInk.secondary).monospacedDigit()
                        .accessibilityIdentifier("brain-import-searching")
                } else if let f = model.searched {
                    Text(WhereWords.searched(f)).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: Space.s3)
                if model.searching {
                    Button("Stop") { model.stopSearch() }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
                } else if model.searched != nil {
                    Button("Search Again") { model.searchAgain() }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                        .help("Look through the home folder again")
                }
            }
        }
    }
}

/// Chat exports are read from one folder the person picks; there is no search for them.
struct ChatFolderLine: View {
    let model: ImportModel

    var body: some View {
        HStack(spacing: Space.s2) {
            Text(model.chatFolder.map(WhereWords.tilde) ?? "No folder chosen").coreFont(size: MacTextSize.meta)
                .foregroundStyle(GlassInk.secondary).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: Space.s3)
            Button(model.chatFolder == nil ? "Choose Folder…" : "Change…") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.prompt = "Choose"
                if panel.runModal() == .OK { model.setChatFolder(panel.url) }
            }
            .buttonStyle(CoreButtonStyle(.secondary, size: .small))
            .help("Choose the folder with your chat exports")
        }
        .padding(.horizontal, Space.s3)
    }
}
