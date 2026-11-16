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
    /// A narrow header: icons only, their names in the tooltips.
    var compact = false
    /// The side panel's card: where the session runs, as label and value rows under the title.
    var facts: [(String, String)] = []

    @Environment(\.corePalette) private var palette
    @Environment(\.sessionUI) private var ui

    /// A live session has one action: End session, a quiet red outline. A finished one has recovery only: Wake (secondary)
    /// and Start again (blue). A lost one has Resume in the notice above the transcript, so nothing here.
    var body: some View {
        if stacked {
            // The side panel's Session section is information only (review 2026-11-16: one home per action); the
            // actions live in the title line, with the same names everywhere.
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: Space.s2) {
                    Image(systemName: "slider.horizontal.3").coreFont(size: MacTextSize.body)
                        .foregroundStyle(palette.text2).frame(width: Space.s4).accessibilityHidden(true)
                    Text("Session").coreFont(size: MacTextSize.body, weight: .semibold).accessibilityAddTraits(
                        .isHeader)
                    Spacer(minLength: 0)
                }
                // Room at the right for the fixed panel toggle (SessionView), as the sidebar leaves room at the left.
                .padding(.trailing, Space.s6)
                if !facts.isEmpty {
                    VStack(spacing: Space.s1) {
                        ForEach(Array(facts.enumerated()), id: \.offset) { _, f in PanelRow(label: f.0, value: f.1) }
                    }
                }
            }
        } else {
            HStack(spacing: Space.s2) {
                keysButton
                findButton
                if session.live || session.state != .lost { folderTools }
                state
            }
        }
    }

    @ViewBuilder private var findButton: some View {
        if let find {
            CoreIconButton(symbol: "magnifyingglass", label: "Find in this conversation", action: find)
                .help("Find in this conversation (⌘F)").keyHint(.find)
        }
    }

    /// ⌘/: the list of this screen's keys.
    @ViewBuilder private var keysButton: some View {
        if let ui {
            CoreIconButton(symbol: "keyboard", label: "Keyboard shortcuts") { ui.shortcuts.toggle() }
                .help("Show every keyboard shortcut of this screen (⌘/)").keyHint(.shortcuts)
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
                if compact {
                    Image(systemName: "stop").accessibilityLabel("End Session…")
                } else {
                    Label("End Session…", systemImage: "stop").lineLimit(1)
                }
            }
            // Neutral at rest, red only on hover: occasional and destructive, never the loudest thing on screen.
            .buttonStyle(EndButtonStyle(iconOnly: compact))
            .disabled(model.stopping[session.id] != nil)
            .help("End Session… (⇧⌘E): the CLI exits and the transcript stays. Esc stops only the current turn.")
            .keyHint(.endSession)
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
                    .help("Bring the process back on its runner, with the same conversation (W)").keyHint("W")
            }
            Button(action: { model.startAgain(session.id) }) {
                Label("Start again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(CoreButtonStyle(.prominent, size: .small)).environment(\.coreKeycap, "R")
            .help("Start a new AI session with the same first message and runner. This one stays as it is (R)")
            .keyHint("R")
        }
    }

    // MARK: Terminal here, Open in…

    @ViewBuilder private var terminalHere: some View {
        let help =
            session.folder == nil
            ? "Terminal (⇧⌘T): open a new terminal on \(model.runnerName(session.runner))"
            : "Terminal (⇧⌘T): open a new terminal in this session's folder on \(model.runnerName(session.runner))"
        if compact {
            // Icons only in the title line, like Find and the shortcuts (Ahmed, 2026-11-16); the name is in the tooltip.
            CoreIconButton(symbol: "terminal", label: "Terminal") {
                model.host?.openTerminal(on: session.runner, session: session.id)
            }
            .help(help).keyHint(.terminal).accessibilityIdentifier("session-terminal-here")
        } else {
            Button {
                model.host?.openTerminal(on: session.runner, session: session.id)
            } label: {
                Label("Terminal", systemImage: "terminal").lineLimit(1).frame(maxWidth: stacked ? .infinity : nil)
            }
            .buttonStyle(CoreButtonStyle(.secondary, size: .medium))
            .help(help).keyHint(.terminal).accessibilityIdentifier("session-terminal-here")
        }
    }

    /// The session's folder, when it is on this Mac and still there (an ended session's worktree is moved away).
    private var localFolder: URL? {
        guard onThisMac, let path = session.folder, FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Small tiles in a narrow header and in the panel's grid; body size beside the title on a medium window.
    private var small: Bool { compact }

    private var onThisMac: Bool { model.host?.thisMacRunnerID == session.runner }

    private var openIn: some View {
        // Drawn like Terminal here beside it: the same quiet tile, the same size.
        CoreDropdown(
            items: openInItems, isPresented: Binding(get: { ui?.openIn ?? false }, set: { ui?.openIn = $0 })
        ) {
            Group {
                if compact {
                    Image(systemName: "folder").accessibilityLabel("Open In…")
                } else {
                    Label("Open In…", systemImage: "folder").lineLimit(1)
                }
            }
            .coreFont(size: compact ? MacTextSize.body : MacTextSize.body, weight: compact ? .regular : .semibold)
            .foregroundStyle(compact ? SessionInk.text2 : GlassInk.primary)
            .padding(.horizontal, small ? Space.s2 : Space.s3)
            .frame(maxWidth: stacked ? .infinity : nil, minHeight: small ? MacSize.controlSm : MacSize.controlMd)
            .frame(minWidth: compact ? MacSize.controlSm : nil)
            .background(compact ? .clear : GlassInk.well, in: coreShape(small ? Radius.chip : Radius.control))
            .contentShape(coreShape(small ? Radius.chip : Radius.control))
        }
        .help("Open In… (⇧⌘O): reveal the folder in Finder, open it in an editor, or copy it")
        .keyHint(.openIn)
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

/// A label and its value on one line, the value at the right: the side panel's one row style.
struct PanelRow: View {
    let label: String
    let value: String
    var mono = false
    @Environment(\.corePalette) private var palette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            Text(label).coreFont(size: MacTextSize.body).foregroundStyle(palette.text2)
            Spacer(minLength: Space.s2)
            Text(value).coreFont(size: MacTextSize.body, design: mono ? .monospaced : .default).lineLimit(1)
                .truncationMode(.middle).monospacedDigit().help(value)
        }
        .accessibilityElement(children: .combine)
    }
}
