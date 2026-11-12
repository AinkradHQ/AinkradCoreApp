import CoreUI
import Shell
import SwiftUI

/// One line of the Sources page in the shared grid: switch, name with a quiet line, items, last run.
struct SourceLine<Lead: View, Last: View>: View {
    let name: String
    let sub: String
    let items: String
    var dim = false
    var tap: (() -> Void)?
    @ViewBuilder var lead: Lead
    @ViewBuilder var last: Last

    var body: some View {
        let row = HStack(alignment: .center, spacing: Space.s4) {
            lead.fixedSize(horizontal: false, vertical: true).frame(width: Space.s8 + Space.s1, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).coreFont(size: MacTextSize.body, weight: .medium)
                    .foregroundStyle(dim ? GlassInk.secondary : GlassInk.primary).lineLimit(1)
                Text(sub).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(items).coreFont(size: MacTextSize.body).monospacedDigit().foregroundStyle(GlassInk.secondary)
                .frame(width: Space.s8 * 3.5, alignment: .trailing)
            last.frame(width: Space.s8 * 4.5, alignment: .trailing)
        }
        .padding(.horizontal, Space.s3).frame(height: Space.s8 + Space.s4)
        .modifier(BrainRowHover(enabled: !dim || tap != nil))
        .accessibilityElement(children: .contain)
        if let tap { Button(action: tap) { row }.buttonStyle(CoreQuietPressStyle(radius: Radius.control)) } else { row }
    }
}

/// A section title over its plain-words note.
struct SourceGroupHead: View {
    let title: String
    let note: String
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(title).coreFont(size: MacTextSize.body, weight: .semibold).foregroundStyle(GlassInk.secondary)
                .accessibilityAddTraits(.isHeader)
            Text(note).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Space.s3).padding(.top, Space.s4)
    }
}

/// Jira and GitHub, read by the Core through the accounts in Connections.
struct ConnectionSources: View {
    let sync: SyncModel

    var body: some View {
        let rows = sync.sources.filter(\.isConnection)
        if !rows.isEmpty {
            SourceGroupHead(
                title: "Connections",
                note:
                    "Read through the accounts in Connections. Titles, descriptions, comments and reviews are read. Tokens never enter the Brain."
            )
            VStack(spacing: 2) {
                ForEach(rows) { s in
                    SourceLine(
                        name: s.id == "jira" ? "Jira" : "GitHub", sub: Self.sub(s),
                        items: s.items.map { $0.formatted() } ?? "", dim: !s.enabled
                    ) {
                        CoreSwitch(
                            s.id == "jira" ? "Jira" : "GitHub",
                            isOn: Binding(get: { s.enabled }, set: { on in Task { await sync.toggle(s, on: on) } }))
                    } last: {
                        Text(Self.last(s)).coreFont(size: MacTextSize.meta + 1).foregroundStyle(GlassInk.secondary)
                    }
                    .accessibilityIdentifier("source-\(s.id)")
                }
            }
        }
    }

    static func sub(_ s: SourceWire) -> String {
        let scope = s.roots.isEmpty ? "Nothing chosen yet" : s.roots.joined(separator: " · ")
        return s.id == "jira" ? "Atlassian · \(scope)" : scope
    }

    static func last(_ s: SourceWire) -> String {
        guard s.enabled else { return "Off" }
        return SyncWords.date(s.lastRun).map { SyncWords.ago($0) } ?? "Not yet"
    }
}

/// Each runner with its history switch. Off by default; turning one on opens the sheet that says what is read.
struct RunnerSources: View {
    let model: BrainModel
    private var c: BrainCandidates { model.candidates }

    var body: some View {
        if !c.runners.isEmpty {
            SourceGroupHead(
                title: "Runners",
                note:
                    "Off by default. A runner reads the AI tool history stored on its own machine and sends the text to your Core. Keys, certificates and restricted paths are never sent."
            )
            VStack(spacing: 2) {
                ForEach(c.runners) { r in
                    SourceLine(
                        name: r.name, sub: r.online ? r.toolLine : r.lastRun.map { "Offline since \($0)" } ?? "Offline",
                        items: r.online ? r.items.formatted() : "", dim: !r.enabled || !r.online
                    ) {
                        if r.online {
                            CoreSwitch(
                                r.name,
                                isOn: Binding(
                                    get: { r.enabled },
                                    set: { _ in
                                        Task {
                                            await c.toggleRunner(r.id)
                                            if c.runnerSheet != nil { BrainSheets.runnerHistory(model) }
                                        }
                                    }))
                        }
                    } last: {
                        Text(r.online ? (r.enabled ? r.lastRun ?? "Not yet" : "Off") : "Offline")
                            .coreFont(size: MacTextSize.meta + 1).foregroundStyle(GlassInk.secondary)
                    }
                    .help(r.online ? "" : "Turn it on when the runner is back")
                    .accessibilityIdentifier("runner-\(r.id)")
                }
            }
        }
    }
}

/// "Collect history on vps-1?": what is read, what is never sent, and Turn On (Touch ID, every time). One Touch ID
/// covers both steps at the Core: the runner's history sharing, then the source's switch.
struct RunnerHistorySheet: View {
    let model: BrainModel
    @State private var busy = false
    private var c: BrainCandidates { model.candidates }
    private static let neverSent = [
        "Passwords, keys, certificates and .env files", "Deprecated projects and restricted paths",
    ]

    var body: some View {
        if let r = c.runnerSheet {
            CoreDialogPanel("", width: Space.s8 * 15) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    HStack {
                        Text("Collect history on \(r.name)?")
                            .coreFont(size: MacTextSize.title, weight: .semibold)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: Space.s3)
                        CoreIconButton(symbol: "xmark", label: "Close") { close() }
                    }
                    Text(
                        "\(r.name) reads these AI tool histories and sends the text to your Core, "
                            + "where it is cleaned and filed into rooms."
                    )
                    .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                    block("Read") {
                        if r.tools.isEmpty {
                            line("The AI tool histories stored on this runner")
                        }
                        ForEach(r.tools) { t in
                            HStack(spacing: Space.s3) {
                                Image(systemName: t.installed ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(t.installed ? GlassInk.blue : GlassInk.secondary)
                                    .accessibilityHidden(true)
                                HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                                    Text(t.name).coreFont(size: MacTextSize.body, weight: .medium)
                                    Text(note(t)).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, Space.s3).frame(minHeight: Space.s8)
                        }
                    }
                    block("Never sent") {
                        ForEach(Self.neverSent, id: \.self) { l in
                            HStack(spacing: Space.s3) {
                                Image(systemName: "lock").foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
                                Text(l)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, Space.s3).frame(minHeight: Space.s8)
                        }
                    }
                    HStack(spacing: Space.s3) {
                        Button("Not now") { close() }.buttonStyle(CoreButtonStyle(.plain)).keyboardShortcut(
                            .cancelAction)
                        Spacer(minLength: Space.s3)
                        Text("Asks for Touch ID").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                        Button("Turn On") {
                            busy = true
                            Task {
                                if await c.turnOnRunner() { model.host.shell.closeDialog() }
                                busy = false
                            }
                        }
                        .buttonStyle(CoreButtonStyle(.prominent, busy: busy))
                        .disabled(busy)
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                }
            }
            .accessibilityIdentifier("runner-history-sheet")
        }
    }

    private func note(_ t: RunnerTool) -> String {
        guard t.installed else { return "Not installed" }
        return t.found.map { BrainWords.plural($0, "session found", "sessions found") } ?? "On this runner"
    }

    private func line(_ s: String) -> some View {
        Text(s).padding(.horizontal, Space.s3).frame(minHeight: Space.s8, alignment: .leading)
    }

    private func close() {
        c.closeRunnerSheet()
        model.host.shell.closeDialog()
    }

    private func block<V: View>(_ title: String, @ViewBuilder _ rows: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).coreFont(size: MacTextSize.body, weight: .semibold).padding(.horizontal, Space.s3)
                .frame(minHeight: Space.s8, alignment: .leading)
            rows()
        }
        .padding(.vertical, Space.s2).frame(maxWidth: .infinity, alignment: .leading).coreWell()
    }
}

@MainActor
extension BrainSheets {
    /// The per-runner history sheet. Turn On asks for Touch ID every time, never once for the session.
    static func runnerHistory(_ m: BrainModel) {
        m.host.clearElevationNotice()
        m.host.shell.present(
            ShellDialog(
                id: "runner-history",
                onClose: { [weak m] in
                    m?.host.clearElevationNotice()
                    m?.candidates.closeRunnerSheet()
                }
            ) { RunnerHistorySheet(model: m) })
    }
}
