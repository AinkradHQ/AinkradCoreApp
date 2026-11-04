import CoreUI
import SwiftUI

/// The New terminal sheet: where it runs, what it starts, and Open. A refusal lands inline with the Core's own code.
struct NewTerminalView: View {
    let model: TerminalsModel
    @Bindable var form: NewTerminalModel
    @Environment(\.corePalette) private var palette
    @FocusState private var programFocus: Bool

    var body: some View {
        CoreDialogPanel("New terminal", width: Space.s8 * 17) {
            Text("A shell on one of your runners. Pick where it runs.").foregroundStyle(palette.text2)
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("Runner").font(.system(size: MacTextSize.meta, weight: .semibold)).foregroundStyle(palette.text2)
                if model.runners.isEmpty {
                    Text("No runners are paired with this Core.").foregroundStyle(palette.text2)
                }
                ForEach(model.runners) { r in PickTile(model: model, form: form, runner: r) }
            }
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Starts with").font(.system(size: MacTextSize.meta, weight: .semibold)).foregroundStyle(
                    palette.text2)
                TextField("Login shell", text: $form.program)
                    .textFieldStyle(.plain).font(.system(size: MacTextSize.body, design: .monospaced))
                    .autocorrectionDisabled().focused($programFocus)
                    .padding(.horizontal, Space.s3).frame(minHeight: MacSize.controlLg)
                    .background(palette.glassCard, in: coreShape(Radius.control))
                    .overlay { coreShape(Radius.control).strokeBorder(palette.glassCardEdge, lineWidth: 1) }
                    .coreFocusRing(programFocus, radius: Radius.control, palette: palette)
                    .onSubmit { Task { await form.submit() } }
                    .accessibilityLabel("Program to start")
                Text("Leave empty for the runner’s login shell.").font(.system(size: MacTextSize.meta)).foregroundStyle(
                    palette.text2)
            }
            Text(
                "Runs as the runner’s user in a sandboxed shell: sudo, su and ping do not work. Don’t treat it as isolated: the terminal scope counts as admin-level today. \(model.openCount) open."
            )
            .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
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
                Text("Needs Touch ID").font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                Spacer(minLength: Space.s2)
                Button("Cancel") { model.shell.closeDialog() }
                    .buttonStyle(CoreButtonStyle(.secondary)).keyboardShortcut(.cancelAction)
                Button(form.error?.code == "runner_busy" ? "Try again" : "Open terminal") {
                    Task { await form.submit() }
                }
                .buttonStyle(CoreButtonStyle(.prominent, busy: form.busy)).keyboardShortcut(.defaultAction)
                .disabled(!form.canOpen)
            }
        }
    }
}

private struct PickTile: View {
    let model: TerminalsModel
    @Bindable var form: NewTerminalModel
    let runner: RunnerItem
    @Environment(\.corePalette) private var palette

    var body: some View {
        let st = RunnerStatus(runner)
        let on = form.runner == runner.id
        let warn: String? =
            st == .off
            ? "Not connected"
            : st == .busy
                ? "Busy: new work is refused (503)"
                : st == .degraded ? "Slow to answer heartbeats" : !runner.hasPty ? "Terminals are off" : nil
        Button {
            form.pick(runner.id)
        } label: {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack {
                    Text(runner.name).font(.system(size: MacTextSize.headline, weight: .semibold, design: .monospaced))
                    Spacer()
                    StateBadge(st.label, tone: st.tone, symbol: st.symbol)
                }
                Text(
                    [runner.arch, "\(model.onRunner(runner.id)) terminals"].compactMap { $0 }.joined(separator: " · ")
                )
                .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                HStack(spacing: Space.s2) {
                    Text("Work").font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                    CoreSlots(used: runner.load, capacity: runner.capacity)
                    Text("\(runner.load) of \(runner.capacity)").font(.system(size: MacTextSize.meta)).monospacedDigit()
                    Spacer()
                    if let warn {
                        Text(warn).font(.system(size: MacTextSize.meta, weight: .medium)).foregroundStyle(
                            palette.tone(st.tone).ink)
                    }
                }
            }
            .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? palette.navActive : palette.glassCard, in: coreShape(Radius.cardMac))
            .overlay { if on { coreShape(Radius.cardMac).strokeBorder(palette.navActiveEdge, lineWidth: 1) } }
            .contentShape(coreShape(Radius.cardMac))
            .opacity(st == .off && !on ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(st == .off && !on)
        .accessibilityLabel("\(runner.name), \(st.label)\(warn.map { ", \($0)" } ?? "")")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
