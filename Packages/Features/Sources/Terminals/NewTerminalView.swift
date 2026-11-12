import CoreUI
import SwiftUI

/// New terminal (advanced): where it runs, and a live preview of what Open will do. It always starts the Ainkrad shell. The quick New terminal
/// skips this sheet. A refusal lands inline with the Core's own code.
struct NewTerminalView: View {
    let model: TerminalsModel
    @Bindable var form: NewTerminalModel
    @Namespace private var pick
    @State private var shown = false

    var body: some View {
        CoreDialogPanel("", width: Space.s8 * 20) {
            HStack(spacing: Space.s3) {
                IconTile("terminal", hue: GlassInk.slate, size: 52, bounce: shown)
                VStack(alignment: .leading, spacing: 2) {
                    Text("New terminal").coreFont(size: MacTextSize.large + 4, weight: .bold)
                        .accessibilityAddTraits(.isHeader)
                    Text("Pick where it runs.").foregroundStyle(GlassInk.secondary)
                }
            }
            .coreRise(shown, 0)
            step("Where", "server.rack", index: 1) {
                if model.runners.isEmpty {
                    Label("No runners are paired with this Core.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(GlassInk.secondary)
                }
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: Space.s2), GridItem(.flexible())], spacing: Space.s2
                ) {
                    ForEach(Array(model.runners.enumerated()), id: \.element.id) { i, r in
                        RunnerTile(model: model, form: form, runner: r, lens: pick)
                            .coreTileKey("⌘\(i + 1)", key: Character("\(min(i + 1, 9))"))
                    }
                }
            }
            preview.coreRise(shown, 2)
            Label(
                "Runs as the runner's user in a sandbox: sudo, su and ping don't work. The terminal scope counts as admin-level today.",
                systemImage: "info.circle"
            )
            .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            .fixedSize(horizontal: false, vertical: true)
            if let n = model.host.elevationNotice { ElevationBanner(notice: n) }
            if let why = form.blockedReason, form.error == nil {
                Label(why, systemImage: "exclamationmark.triangle").coreFont(size: MacTextSize.meta)
                    .foregroundStyle(GlassInk.secondary).accessibilityIdentifier("new-terminal-blocked")
            }
            if let e = form.error {
                TermBanner(
                    tone: .fail, title: e.title,
                    detail: [e.text, e.http > 0 ? "\(e.code) · \(e.http)" : e.code].filter { !$0.isEmpty }.joined(
                        separator: "\n")
                )
                .accessibilityIdentifier("new-terminal-error")
            }
            HStack(spacing: Space.s2) {
                Button("Cancel") { model.shell.closeDialog() }
                    .buttonStyle(CoreButtonStyle(.secondary)).coreShortcut(.cancel)
                Spacer(minLength: Space.s2)
                Button {
                    Task { await form.submit() }
                } label: {
                    Label(form.error?.code == "runner_busy" ? "Try again" : "Open terminal", systemImage: "touchid")
                }
                .buttonStyle(CoreButtonStyle(.prominent, busy: form.busy)).coreShortcut(.primary)
                .disabled(!form.canOpen).opacity(form.canOpen || form.busy ? 1 : 0.45)
                .help(form.blockedReason ?? "")
            }
        }
        .foregroundStyle(GlassInk.primary)
        .onAppear { shown = true }
        .animation(Motion.out(Motion.ui), value: form.runner)
    }

    private func step<C: View>(_ title: String, _ symbol: String, index: Int, @ViewBuilder _ content: () -> C)
        -> some View
    {
        VStack(alignment: .leading, spacing: Space.s2) {
            Label(title, systemImage: symbol).coreFont(size: MacTextSize.meta, weight: .semibold)
                .foregroundStyle(GlassInk.secondary)
            content()
        }
        .coreRise(shown, index)
    }

    /// What Open will do, as a small terminal: the runner, the program, a blinking cursor.
    private var preview: some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(form.chosen?.name ?? "no runner") $ ainkrad shell")
                    .coreFont(size: MacTextSize.body, design: .monospaced)
                    .contentTransition(.opacity)
                HStack(spacing: 0) {
                    Text("30 × 100").coreFont(size: MacTextSize.meta, design: .monospaced)
                        .foregroundStyle(GlassInk.secondary)
                }
            }
            Spacer(minLength: 0)
            BlinkingCursor()
        }
        .padding(Space.s3)
        .background(Color.black.opacity(0.35), in: coreShape(Radius.row))
        .overlay { coreShape(Radius.row).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Opens the Ainkrad shell on \(form.chosen?.name ?? "no runner")")
    }
}

/// A runner to pick: its picture coloured by state, name, architecture, work slots, and why it can't be picked.
private struct RunnerTile: View {
    let model: TerminalsModel
    @Bindable var form: NewTerminalModel
    let runner: RunnerItem
    let lens: Namespace.ID
    @State private var hovering = false

    var body: some View {
        let st = RunnerStatus(runner)
        let on = form.runner == runner.id
        let hue: Color = st == .off ? GlassInk.red : st == .ok ? GlassInk.green : GlassInk.amber
        let warn: String? =
            st == .off
            ? "Not connected"
            : st == .busy
                ? "Busy: new work is refused"
                : st == .degraded ? "Slow to answer" : !runner.hasPty ? "Terminals are off" : nil
        Button {
            form.pick(runner.id)
        } label: {
            HStack(alignment: .top, spacing: Space.s3) {
                IconTile("server.rack", hue: hue, size: 40, bounce: on)
                VStack(alignment: .leading, spacing: Space.s1) {
                    HStack {
                        Text(runner.name).coreFont(size: MacTextSize.headline, weight: .semibold)
                        Spacer()
                        Image(systemName: on ? "checkmark.square.fill" : "square").foregroundStyle(
                            on ? GlassInk.blue : GlassInk.track
                        )
                        .contentTransition(.symbolEffect(.replace))
                    }
                    Text([runner.arch, "\(model.onRunner(runner.id)) open"].compactMap { $0 }.joined(separator: " · "))
                        .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    CoreSlots(used: runner.load, capacity: runner.capacity)
                    if let warn {
                        Label(warn, systemImage: st.symbol).coreFont(size: MacTextSize.meta, weight: .medium)
                            .foregroundStyle(GlassInk.ink(hue))
                    }
                }
            }
            .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if on {
                    coreShape(Radius.cardMac).fill(GlassInk.blue.opacity(0.16))
                        .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.blue.opacity(0.5), lineWidth: 1) }
                        .matchedGeometryEffect(id: "runner", in: lens)
                } else {
                    coreShape(Radius.cardMac).fill(hovering ? GlassInk.wellHover : GlassInk.well)
                }
            }
            .contentShape(coreShape(Radius.cardMac))
            .opacity(st == .off && !on ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(st == .off && !on)
        .coreScaleEffect(hovering ? 1.015 : 1)
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.25), value: hovering)
        .accessibilityLabel("\(runner.name), \(st.label)\(warn.map { ", \($0)" } ?? "")")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A terminal cursor that blinks (opacity, so it stays under Reduce Motion).
private struct BlinkingCursor: View {
    @State private var on = true
    var body: some View {
        Rectangle().fill(GlassInk.blue).frame(width: 9, height: 18)
            .opacity(on ? 1 : 0.15)
            .coreLoop(.easeInOut(duration: 0.55).repeatForever(autoreverses: true), value: on)
            .onAppear { on = false }
            .accessibilityHidden(true)
    }
}
