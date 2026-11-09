import CoreUI
import SwiftUI

/// New terminal (advanced): where it runs, what it starts, a live preview of what Open will do. The quick New terminal
/// skips this sheet. A refusal lands inline with the Core's own code.
struct NewTerminalView: View {
    let model: TerminalsModel
    @Bindable var form: NewTerminalModel
    @Namespace private var pick
    @State private var shown = false

    /// The shells offered as tiles. Empty means the runner's login shell.
    private static let shells: [(id: String, title: String, symbol: String)] = [
        ("", "Login shell", "person.crop.square"), ("zsh", "zsh", "terminal"), ("bash", "bash", "terminal.fill"),
        ("sh", "sh", "chevron.left.forwardslash.chevron.right"),
    ]

    var body: some View {
        CoreDialogPanel("", width: Space.s8 * 20) {
            HStack(spacing: Space.s3) {
                IconTile("terminal", hue: GlassInk.slate, size: 52, bounce: shown)
                VStack(alignment: .leading, spacing: 2) {
                    Text("New terminal").font(.system(size: MacTextSize.large + 4, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Pick where it runs and what it starts.").foregroundStyle(GlassInk.secondary)
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
            step("What", "chevron.left.forwardslash.chevron.right", index: 2) {
                HStack(spacing: Space.s2) {
                    ForEach(Array(Self.shells.enumerated()), id: \.element.id) { i, sh in
                        ShellTile(title: sh.title, symbol: sh.symbol, on: form.program == sh.id) {
                            form.program = sh.id
                        }
                        .coreTileKey("⌃\(i + 1)", key: Character("\(i + 1)"), modifiers: .control)
                    }
                }
                TextField("Or any command, for example htop", text: $form.program)
                    .textFieldStyle(.plain).font(.system(size: MacTextSize.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .padding(.horizontal, Space.s3).frame(minHeight: MacSize.controlLg)
                    .coreFieldSurface()
                    .onSubmit { Task { await form.submit() } }
                    .accessibilityLabel("Program to start")
            }
            preview.coreRise(shown, 3)
            Label(
                "Runs as the runner's user in a sandbox: sudo, su and ping don't work. The terminal scope counts as admin-level today.",
                systemImage: "info.circle"
            )
            .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
            .fixedSize(horizontal: false, vertical: true)
            if let n = model.host.elevationNotice { ElevationBanner(notice: n) }
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
                .disabled(!form.canOpen)
            }
        }
        .foregroundStyle(GlassInk.primary)
        .onAppear { shown = true }
        .animation(Motion.out(Motion.ui), value: form.runner)
        .animation(Motion.out(Motion.ui), value: form.program)
    }

    private func step<C: View>(_ title: String, _ symbol: String, index: Int, @ViewBuilder _ content: () -> C)
        -> some View
    {
        VStack(alignment: .leading, spacing: Space.s2) {
            Label(title, systemImage: symbol).font(.system(size: MacTextSize.meta, weight: .semibold))
                .foregroundStyle(GlassInk.secondary)
            content()
        }
        .coreRise(shown, index)
    }

    /// What Open will do, as a small terminal: the runner, the program, a blinking cursor.
    private var preview: some View {
        let program = form.program.trimmingCharacters(in: .whitespaces)
        return HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(form.chosen?.name ?? "no runner") $ \(program.isEmpty ? "login shell" : program)")
                    .font(.system(size: MacTextSize.body, design: .monospaced))
                    .contentTransition(.opacity)
                HStack(spacing: 0) {
                    Text("30 × 100").font(.system(size: MacTextSize.meta, design: .monospaced))
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
            "Opens \(program.isEmpty ? "the login shell" : program) on \(form.chosen?.name ?? "no runner")")
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
        let hue: Color = st == .off ? GlassInk.red : st == .ok ? GlassInk.green : GlassInk.orange
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
                        Text(runner.name).font(.system(size: MacTextSize.headline, weight: .semibold))
                        Spacer()
                        Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(
                            on ? GlassInk.blue : GlassInk.track
                        )
                        .contentTransition(.symbolEffect(.replace))
                    }
                    Text([runner.arch, "\(model.onRunner(runner.id)) open"].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
                    CoreSlots(used: runner.load, capacity: runner.capacity)
                    if let warn {
                        Label(warn, systemImage: st.symbol).font(.system(size: MacTextSize.meta, weight: .medium))
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

/// One shell to start with, as a small tile that lights up when chosen.
private struct ShellTile: View {
    let title: String
    let symbol: String
    let on: Bool
    let pick: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: pick) {
            VStack(spacing: Space.s1) {
                Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).coreBounce(on)
                Text(title).font(.system(size: MacTextSize.meta, weight: .medium, design: .monospaced)).lineLimit(1)
            }
            .foregroundStyle(GlassInk.primary)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(
                on ? GlassInk.blue.opacity(0.22) : hovering ? GlassInk.wellHover : GlassInk.well,
                in: coreShape(Radius.row)
            )
            .overlay {
                coreShape(Radius.row).strokeBorder(on ? GlassInk.blue.opacity(0.55) : GlassInk.wellEdge, lineWidth: 1)
            }
            .contentShape(coreShape(Radius.row))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("Start with \(title)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A terminal cursor that blinks (opacity, so it stays under Reduce Motion).
private struct BlinkingCursor: View {
    @State private var on = true
    var body: some View {
        Rectangle().fill(GlassInk.green).frame(width: 9, height: 18)
            .opacity(on ? 1 : 0.15)
            .coreLoop(.easeInOut(duration: 0.55).repeatForever(autoreverses: true), value: on)
            .onAppear { on = false }
            .accessibilityHidden(true)
    }
}
