import AppKit
import CoreUI
import SwiftUI

/// A session's actions: find, a terminal on its runner, open its folder, and End session (or Wake / Start again once it
/// finished). In the header under 1300 pt; in the side panel's first card at and above it (Ahmed, 2026-11-15).
struct SessionActions: View {
    @Bindable var model: AgentsModel
    let session: AgentSessionInfo
    var find: (() -> Void)?
    /// The side panel's card: a titled header with Find and End session, the folder tools under it.
    var stacked = false

    @Environment(\.corePalette) private var palette

    /// A live session has one action: End session, a quiet red outline. A finished one has recovery only: Wake (secondary)
    /// and Start again (blue). A lost one has Resume in the notice above the transcript, so nothing here.
    var body: some View {
        if stacked {
            // The side panel's first card, shaped like the others: its title with Find and End session at the right
            // (as Files touched has Review), the folder tools under it, and a finished session's ways back below.
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: Space.s2) {
                    Image(systemName: "slider.horizontal.3").coreFont(size: MacTextSize.body)
                        .foregroundStyle(palette.text2).frame(width: Space.s4).accessibilityHidden(true)
                    Text("Session").coreFont(size: MacTextSize.body, weight: .semibold).accessibilityAddTraits(
                        .isHeader)
                    Spacer(minLength: 0)
                    findButton
                    if session.live { state }
                }
                if session.live || session.state != .lost { HStack(spacing: Space.s2) { folderTools } }
                if !session.live && session.state != .lost { HStack(spacing: Space.s2) { state } }
            }
        } else {
            HStack(spacing: Space.s2) {
                findButton
                if session.live || session.state != .lost { folderTools }
                state
            }
        }
    }

    @ViewBuilder private var findButton: some View {
        if let find {
            CoreIconButton(symbol: "magnifyingglass", label: "Find in this conversation", action: find)
                .help("Find in this conversation (⌘F)")
        }
    }

    /// Terminal here, Open in….
    @ViewBuilder private var folderTools: some View {
        terminalHere
        openIn
    }

    /// End session; on a finished one Wake, Start again (and the budget ways out).
    @ViewBuilder private var state: some View {
        if session.live {
            Button(action: { model.confirmEnd(session.id) }) {
                Label("End session", systemImage: "stop")
            }
            .buttonStyle(CoreButtonStyle(.quietDanger, size: .small))
            .disabled(model.stopping[session.id] != nil)
            .help("End the session: the CLI exits and the transcript stays. Esc stops only the current turn.")
        } else if session.state != .lost {
            if session.stoppedByBudget {
                Button("Raise budget…") { model.raiseBudget(session) }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                    .help("Open the budget that stopped this session, raise it, then resume")
                Button("Open Accounts") { model.openAccounts() }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
            }
            if case .succeeded? = session.outcome {
                Button(action: { model.wake(session.id) }) { Label("Wake", systemImage: "alarm") }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small)).environment(\.coreKeycap, "W")
                    .help("Bring the process back on its runner, with the same conversation (W)")
            }
            Button(action: { model.startAgain(session.id) }) {
                Label("Start again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(CoreButtonStyle(.prominent, size: .small)).environment(\.coreKeycap, "R")
            .help("Start a new AI session with the same first message and runner. This one stays as it is (R)")
        }
    }

    // MARK: Terminal here, Open in…

    private var terminalHere: some View {
        Button {
            model.host?.openTerminal(on: session.runner)
        } label: {
            Label("Terminal here", systemImage: "terminal")
        }
        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
        .help(
            "Open a new terminal on \(model.runnerName(session.runner)). The Core cannot start it in the session's folder yet."
        )
        .accessibilityIdentifier("session-terminal-here")
    }

    /// The session's folder on this Mac. The Core sends only the folder's name (`project`), never its path, so this is nil until
    /// the Core adds one; the menu below already uses it when it exists. Needs Core support.
    private var localFolder: URL? { nil }

    private var onThisMac: Bool { model.host?.thisMacRunnerID == session.runner }

    private var openIn: some View {
        CoreDropdown(items: openInItems) { Label("Open in…", systemImage: "folder") }
            .help("Reveal the folder in Finder, open it in an editor, or copy it")
            .accessibilityIdentifier("session-open-in")
    }

    private var openInItems: [CoreDropdownItem] {
        if onThisMac, let url = localFolder {
            var items = [
                CoreDropdownItem("Reveal in Finder", symbol: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            ]
            for (name, id) in [
                ("Visual Studio Code", "com.microsoft.VSCode"), ("Cursor", "com.todesktop.230313mzl4w4u92"),
                ("Xcode", "com.apple.dt.Xcode"),
            ] {
                guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { continue }
                items.append(
                    CoreDropdownItem("Open in \(name)", symbol: "chevron.left.forwardslash.chevron.right") {
                        NSWorkspace.shared.open(
                            [url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                    })
            }
            items.append(CoreDropdownItem("Copy path", symbol: "doc.on.doc") { copy(url.path) })
            return items
        }
        return [
            CoreDropdownItem("Copy folder name", symbol: "doc.on.doc", enabled: session.project != nil) {
                copy(session.project ?? "")
            },
            CoreDropdownItem("On \(model.runnerName(session.runner)): open it there", enabled: false) {},
        ]
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
