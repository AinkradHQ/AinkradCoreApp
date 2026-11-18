import CoreUI
import Projects
import SwiftUI

/// Commands & runbooks: a pre-set command is one step, a runbook is several that run in order and stop at the first failure.
/// Both run through the Core's gate; a command that asks to be confirmed shows the confirm card first. Adding and editing
/// commands is not here yet (the Core has the routes; the editor is its own story).
struct HostCommandsPage: View {
    let state: HostPageState
    @State private var settled = false

    var body: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            single.coreRise(settled, 0)
            runbooks.coreRise(settled, 1)
        }
        .onAppear { settled = true }
        .task { if state.commands.value == nil { await state.loadCommands() } }
        .accessibilityIdentifier("host-page-Commands")
    }

    private var singles: [PresetCommand] { state.presets.filter { $0.steps.count <= 1 } }
    private var books: [PresetCommand] { state.presets.filter { $0.steps.count > 1 } }

    private var single: some View {
        Island("Pre-set commands", sub: "also on the overview, same rules as AI") {
            list(singles, empty: HostSection.commands.empty.line) { c in
                row(c)
            }
        }
        .accessibilityIdentifier("commands-single")
    }

    private var runbooks: some View {
        Island("Runbooks", sub: "steps run in order, stop on failure") {
            list(books, empty: "No runbooks for this host. A runbook is a command with more than one step.") { c in
                book(c)
            }
        }
        .accessibilityIdentifier("commands-runbooks")
    }

    @ViewBuilder private func list<Row: View>(
        _ items: [PresetCommand], empty: String, @ViewBuilder row: @escaping (PresetCommand) -> Row
    ) -> some View {
        switch state.commands {
        case .idle, .loading: CoreSkeleton().frame(height: Space.s8 * 2)
        case .missing: Text(HostWords.gone("Commands")).foregroundStyle(GlassInk.secondary)
        case .failed(let why):
            CoreNotice(symbol: "exclamationmark.triangle", title: "Commands did not load", text: why, tone: .warn) {
                Button("Retry") { Task { await state.loadCommands() } }.buttonStyle(
                    CoreButtonStyle(.secondary, size: .small))
            }
        case .ready:
            if items.isEmpty {
                Text(empty).foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s3) { ForEach(items) { row($0) } }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func flag(_ c: PresetCommand) -> String {
        c.readOnly ? "Read-only · AI may run" : c.confirm ? "Confirm first" : "Runs at once"
    }

    private func running(_ c: PresetCommand) -> Bool { state.runs[c.id].map { !$0.finished } ?? false }

    private func row(_ c: PresetCommand) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s3) {
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(c.name).coreFont(size: MacTextSize.headline, weight: .semibold).lineLimit(1)
                    Text(c.steps.first ?? "").coreFont(size: MacTextSize.meta, design: .monospaced)
                        .foregroundStyle(GlassInk.secondary).lineLimit(1)
                }
                Spacer(minLength: Space.s2)
                Text(flag(c)).foregroundStyle(GlassInk.secondary)
                CoreIconButton(symbol: "play", label: "Run \(c.name)") { state.tap(c) }
                    .disabled(running(c))
                    .help("Run \(c.name) on this host")
            }
            result(c)
        }
    }

    private func book(_ c: PresetCommand) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text(c.name).coreFont(size: MacTextSize.headline, weight: .semibold)
                Text(Words.count(c.steps.count, "step") + " · " + flag(c)).foregroundStyle(GlassInk.secondary)
                Spacer(minLength: 0)
                Button {
                    state.tap(c)
                } label: {
                    Label("Run", systemImage: "play")
                }
                .buttonStyle(CoreButtonStyle(.prominent, size: .small)).disabled(running(c))
            }
            ForEach(Array(c.steps.enumerated()), id: \.offset) { i, step in
                Text("\(i + 1). \(step)").coreFont(size: MacTextSize.meta, design: .monospaced)
                    .foregroundStyle(GlassInk.secondary).lineLimit(1)
            }
            result(c)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading).coreWell()
    }

    /// The latest run on this host: its words, and what it printed (redacted by the Core).
    @ViewBuilder private func result(_ c: PresetCommand) -> some View {
        if let r = state.runs[c.id] {
            VStack(alignment: .leading, spacing: Space.s1) {
                HStack(spacing: Space.s2) {
                    if !r.finished { CoreWorkingBar() }
                    Text(HostWords.run(r)).foregroundStyle(GlassInk.secondary)
                }
                if let out = r.output, !out.isEmpty {
                    ScrollView {
                        Text(out).coreFont(size: MacTextSize.meta, design: .monospaced).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: Space.s8 * 5).padding(Space.s2).coreWell()
                }
            }
        }
    }
}
