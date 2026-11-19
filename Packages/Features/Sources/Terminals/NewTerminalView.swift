import CoreUI
import SwiftUI

/// New terminal… (`screens/08-terminals.html`): where it runs (This Mac is a real shell, every other machine a sandbox), and
/// whether it opens in the sandbox home or a project's folder. ⌘T skips this sheet and opens on the last machine. A refusal
/// lands inline with the Core's own code.
struct NewTerminalView: View {
    let model: TerminalsModel
    @Bindable var form: NewTerminalModel
    @Namespace private var pick
    @State private var shown = false

    private enum Where: Hashable, Sendable { case home, project }

    var body: some View {
        CoreDialogPanel("", width: Space.s8 * 20) {
            HStack(spacing: Space.s3) {
                IconTile("terminal", hue: GlassInk.blue, size: 52, bounce: shown)
                Text("New terminal").coreFont(size: MacTextSize.large + 4, weight: .bold)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
            }
            .coreRise(shown, 0)
            step("Where should it run?", index: 1) {
                if model.runners.isEmpty {
                    Label("No runners are paired with this Core.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(GlassInk.secondary)
                }
                VStack(spacing: Space.s1) {
                    ForEach(machines) { r in
                        RunnerTile(model: model, form: form, runner: r, lens: pick)
                    }
                }
            }
            step("Open it in", index: 2) {
                // The Core has no real shell in a project folder yet, so This Mac offers only its home folder.
                CoreSegmented(
                    "Open it in",
                    segments: form.isThisMac
                        ? [CoreSegment(Where.home, "Home folder")]
                        : [CoreSegment(Where.home, "Sandbox home"), CoreSegment(Where.project, "A project folder")],
                    selection: Binding(
                        get: { form.inProject && !form.isThisMac ? .project : .home },
                        set: { form.inProject = $0 == .project })
                )
                if form.inProject, !form.isThisMac {
                    CoreSelect(
                        nil, selection: Binding(get: { form.projectID ?? 0 }, set: { form.projectID = $0 }),
                        options: form.projects.map { CoreSelectOption($0.id, $0.name) })
                }
            }
            note
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
                Text("⌘T opens one right away on \(form.chosen?.name ?? "the last machine").")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
                Spacer(minLength: Space.s2)
                Button("Cancel") { model.shell.closeDialog() }
                    .buttonStyle(CoreButtonStyle(.secondary)).coreShortcut(.cancel)
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

    /// This Mac first, then the others as the Core lists them.
    private var machines: [RunnerItem] {
        let mac = model.host.thisMacRunnerID
        return model.runners.filter { $0.id == mac } + model.runners.filter { $0.id != mac }
    }

    private func step<C: View>(_ title: String, index: Int, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title).coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(GlassInk.secondary)
            content()
        }
        .coreRise(shown, index)
    }

    /// What this choice means for the person's files.
    private var note: some View {
        let mac = form.isThisMac
        let text =
            mac
            ? "This is a real shell on your Mac. It can read and change your files, so be careful with commands you paste."
            : form.inProject
                ? "The sandbox can only see the project folder you share, nothing else."
                : "A safe room with its own home folder. It cannot see your files unless you share a project."
        return Label(text, systemImage: mac ? "exclamationmark.triangle" : "shield")
            .coreFont(size: MacTextSize.meta)
            .foregroundStyle(mac ? GlassInk.ink(GlassInk.amber) : GlassInk.primary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
            .background((mac ? GlassInk.amber : GlassInk.blue).opacity(0.14), in: coreShape(Radius.row))
            .coreRise(shown, 3)
    }
}

/// A machine to pick: its picture, name and what a terminal there is, a chip (This Mac or Sandbox), and why it can't be picked.
private struct RunnerTile: View {
    let model: TerminalsModel
    @Bindable var form: NewTerminalModel
    let runner: RunnerItem
    let lens: Namespace.ID
    @State private var hovering = false
    @Environment(\.corePalette) private var palette

    var body: some View {
        let st = RunnerStatus(runner)
        let on = form.runner == runner.id
        let mac = model.host.thisMacRunnerID == runner.id
        let warn: String? =
            st == .off
            ? "Offline right now"
            : st == .busy
                ? "Busy: new work is refused"
                : st == .degraded ? "Slow to answer" : !runner.hasPty ? "Terminals are off" : nil
        let about =
            mac
            ? "A real shell on this Mac. It can change your files."
            : runner.builtIn ? "Sandbox. A safe room that cannot see your files." : "Sandbox on this machine."
        Button {
            form.pick(runner.id)
        } label: {
            HStack(spacing: Space.s3) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .foregroundStyle(on ? GlassInk.blue : GlassInk.track)
                    .contentTransition(.symbolEffect(.replace)).accessibilityHidden(true)
                IconTile(
                    mac ? "laptopcomputer" : runner.builtIn ? "diamond" : "server.rack",
                    hue: mac ? GlassInk.amber : GlassInk.blue, size: 36, bounce: on)
                VStack(alignment: .leading, spacing: 1) {
                    Text(mac ? "This Mac" : runner.name).coreFont(size: MacTextSize.headline, weight: .semibold)
                    Text(warn ?? about).coreFont(size: MacTextSize.meta)
                        .foregroundStyle(warn == nil ? GlassInk.secondary : GlassInk.ink(GlassInk.red)).lineLimit(1)
                }
                Spacer(minLength: Space.s2)
                MachineChip(real: mac)
            }
            .padding(.horizontal, Space.s3).padding(.vertical, Space.s2).frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if on {
                    coreShape(Radius.row).fill(palette.navActive).matchedGeometryEffect(id: "runner", in: lens)
                } else {
                    coreShape(Radius.row).fill(hovering ? GlassInk.wellHover : GlassInk.well)
                }
            }
            .contentShape(coreShape(Radius.row))
            .opacity(st == .off && !on ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(st == .off && !on)
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
        .accessibilityLabel("\(mac ? "This Mac" : runner.name), \(mac ? "real shell" : "sandbox"), \(st.label)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
