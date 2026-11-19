import CoreUI
import Shell
import SwiftUI

// The host page (mockup 14, D-24): who the host is, then four big cards (Connect, Files, Projects, Runner). Everything else
// the old rail held sits behind Advanced.

/// The host's name, a way back, what it is, and the Advanced button.
struct HostHero: View {
    let model: LeylineModel
    let host: HostItem
    let state: HostPageState
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            BackButton("Hosts") { model.closeHost() }
            HStack(spacing: Space.s4) {
                IconTile("server.rack", hue: GlassInk.blue, size: Space.s8 * 2)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: Space.s3) {
                        Text(host.name).coreFont(size: MacTextSize.large + 6, weight: .semibold).lineLimit(1)
                            .accessibilityAddTraits(.isHeader)
                        if let p = host.presence { StateBadge(p.label, tone: p.tone, symbol: "circle") }
                        if let g = host.group { CoreChip(g, minWidth: 0) }
                    }
                    Text([host.os, host.login, host.seenLine?.lowercased()].compactMap { $0 }.joined(separator: " · "))
                        .foregroundStyle(palette.text2).lineLimit(1)
                }
                Spacer(minLength: Space.s3)
                RouteChips(hops: ["This Mac"] + model.route(host) + [host.name])
                Button {
                    HostAdvanced.open(model: model, host: host, state: state)
                } label: {
                    Label("Advanced", systemImage: "gearshape")
                }
                .buttonStyle(CoreButtonStyle(.secondary))
                .help("Route, AI rules, commands and history")
                .accessibilityIdentifier("host-advanced")
            }
        }
    }
}

/// On a page behind Advanced: back to the host, and the page's name.
struct HostSubpageBar: View {
    let model: LeylineModel
    let host: HostItem

    var body: some View {
        HStack(spacing: Space.s3) {
            BackButton(host.name) { model.section = .overview }
            Text(model.section.title).coreFont(size: MacTextSize.title, weight: .semibold)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
    }
}

/// The four cards, two by two.
struct HostCards: View {
    let model: LeylineModel
    let host: HostItem
    let state: HostPageState
    @State private var settled = false
    @Environment(\.corePalette) private var palette

    var body: some View {
        Grid(horizontalSpacing: Space.s3, verticalSpacing: Space.s3) {
            GridRow {
                connect.coreRise(settled, 0)
                files.coreRise(settled, 1)
            }
            GridRow {
                projects.coreRise(settled, 2)
                runner.coreRise(settled, 3)
            }
        }
        .onAppear { settled = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("host-cards")
    }

    // MARK: cards

    private var connect: some View {
        HostBigCard(
            symbol: "terminal", title: "Connect", text: "Open a terminal on this host.", go: "Open terminal",
            busy: state.opening, disabled: model.readOnly || state.opening
        ) {
            Task { await state.connect() }
        } preview: {
            MiniTerminal(prompt: "\(host.username)@\(host.name.lowercased()) ~ $")
        }
        .accessibilityIdentifier("host-card-connect")
    }

    private var files: some View {
        HostBigCard(
            symbol: "folder", title: "Files", text: "Look at and move files on this host.", go: "Browse files"
        ) {
            model.section = .files
        } preview: {
            previewLine("folder", "Browse over SFTP, drag files in and out")
        }
        .accessibilityIdentifier("host-card-files")
    }

    private var projects: some View {
        HostBigCard(
            symbol: "square.stack.3d.up", title: "Projects", text: "Projects whose work lives on this host.",
            go: "Group and tags"
        ) {
            HostDialogs.openEdit(model, host)
        } preview: {
            VStack(alignment: .leading, spacing: Space.s2) {
                if let g = host.group { previewLine("folder", g) } else {
                    previewLine("folder", "Not in a project yet")
                }
                if !host.tags.isEmpty {
                    HStack(spacing: Space.s1) { ForEach(host.tags.prefix(4), id: \.self) { CoreChip($0, minWidth: 0) } }
                }
            }
        }
        .accessibilityIdentifier("host-card-projects")
    }

    @ViewBuilder private var runner: some View {
        let glance = host.runnerDevice.flatMap { model.runnerGlance?($0) }
        let starting = state.runnerState == .starting
        let waiting: Bool = if case .waiting = state.runnerState { true } else { false }
        HostBigCard(
            symbol: "server.rack", title: "Runner",
            text: "Let this host do work for you, with AI tools ready.",
            go: host.runnerDevice == nil ? "Make runner" : "Open runner", busy: starting,
            disabled: model.readOnly || starting || waiting,
            chip: host.runnerDevice == nil ? nil : (glance?.online == false ? "Offline" : "Idle")
        ) {
            if let d = host.runnerDevice { model.openRunner?(d) } else { state.confirmRunner() }
        } preview: {
            VStack(alignment: .leading, spacing: Space.s2) {
                if let g = glance, let tool = g.installing {
                    HStack(spacing: Space.s2) {
                        Text("Installing \(tool)…").coreFont(size: MacTextSize.meta, weight: .medium)
                        CoreMeter(Double(g.percent) / 100, label: "Installing \(tool)").frame(width: Space.s8 * 3)
                    }
                } else if waiting {
                    previewLine("arrow.down.circle", "Installing the runner over SSH")
                } else if case .failed(let why) = state.runnerState {
                    previewLine("exclamationmark.triangle", why)
                } else if host.runnerDevice != nil {
                    previewLine("checkmark", glance?.online == false ? "Offline right now" : "Ready for work")
                } else {
                    previewLine("minus", "No runner on this host yet")
                }
            }
        }
        .accessibilityIdentifier("host-card-runner")
    }

    private func previewLine(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).foregroundStyle(palette.text2).lineLimit(2)
    }
}

/// One big card: symbol and title, one line, a live preview, and where it goes.
struct HostBigCard<Preview: View>: View {
    let symbol: String
    let title: String
    let text: String
    let go: String
    var busy = false
    var disabled = false
    var chip: String?
    let action: () -> Void
    @ViewBuilder let preview: () -> Preview
    @Environment(\.corePalette) private var palette
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: Space.s3) {
                    IconTile(symbol, hue: GlassInk.blue, size: Space.s8 + Space.s1)
                    Text(title).coreFont(size: MacTextSize.title, weight: .semibold)
                    Spacer(minLength: 0)
                    if let chip { StateBadge(chip, tone: chip == "Offline" ? .fail : .queue, symbol: "circle") }
                }
                Text(text).foregroundStyle(palette.text2)
                preview()
                    .padding(Space.s3).frame(maxWidth: .infinity, minHeight: Space.s8 * 2, alignment: .topLeading)
                    .background(GlassInk.well, in: coreShape(Radius.control))
                Spacer(minLength: 0)
                HStack(spacing: Space.s1) {
                    Text(go).coreFont(size: MacTextSize.body, weight: .semibold)
                    Image(systemName: "arrow.right").imageScale(.small)
                }
                .foregroundStyle(hovering ? palette.primary : palette.text2)
            }
            .padding(Space.s5)
            .frame(maxWidth: .infinity, minHeight: Space.s8 * 7, alignment: .topLeading)
            .coreWell(radius: Radius.pane, active: hovering)
            .contentShape(coreShape(Radius.pane))
        }
        .buttonStyle(.coreQuietPress)
        .disabled(disabled)
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
        .accessibilityLabel("\(title). \(text)")
    }
}

/// Two prompt lines and a cursor that blinks; Reduce Motion: the cursor stays on.
struct MiniTerminal: View {
    let prompt: String
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var on = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(prompt) ls").foregroundStyle(GlassInk.secondary)
            HStack(spacing: 2) {
                Text(prompt)
                Text("▌").opacity(on ? 1 : 0.1)
            }
        }
        .coreFont(size: MacTextSize.meta, design: .monospaced)
        .lineLimit(1)
        .onAppear {
            guard !reduce else { return }
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { on = false }
        }
        .accessibilityHidden(true)
    }
}

/// Advanced for one host, in a sheet: how Core reaches it, and the pages and form the old rail held.
enum HostAdvanced {
    @MainActor static func open(model: LeylineModel, host: HostItem, state: HostPageState) {
        let shell = model.host.shell
        shell.present(
            ShellDialog(id: "host-advanced") {
                HostAdvancedSheet(model: model, host: host, state: state) { shell.closeDialog() }
            })
    }
}

private struct HostAdvancedSheet: View {
    let model: LeylineModel
    let host: HostItem
    let state: HostPageState
    let close: () -> Void
    @Environment(\.corePalette) private var palette

    private var mode: Binding<String> {
        Binding(
            get: { state.direct == nil ? "relayed" : "direct" },
            set: { new in
                Task { if new == "direct" { await state.startDirect() } else { await state.stopDirect() } }
            })
    }

    var body: some View {
        CoreDialogPanel("", width: Space.s8 * 20) {
            VStack(alignment: .leading, spacing: Space.s4) {
                DialogHead(title: "Advanced for \(host.name)", line: "Most people never need these.")
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("How Core reaches it").coreFont(size: MacTextSize.body, weight: .semibold)
                    CoreSegmented(
                        "Route",
                        segments: [CoreSegment("relayed", "Relayed"), CoreSegment("direct", "Mac-direct")],
                        selection: mode
                    )
                    .fixedSize().disabled(state.directBusy || model.readOnly)
                    Text(
                        "Relayed: the key never leaves the Core. Mac-direct: this Mac’s ssh borrows the key for a few minutes (Touch ID)."
                    )
                    .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: Space.s2) {
                    row("lock", "Access and AI rules", "Route, sign-in, host key and what AI may do here") { go(.access) }
                    row("chevron.right.2", "Commands and runbooks", "Pre-set commands and what they did") { go(.commands) }
                    row("clock.arrow.circlepath", "History and recordings", "Everything you and AI did on this host") {
                        go(.history)
                    }
                    row("pencil", "Edit this host", "Name, address, login, key, jump hosts, group and tags") {
                        close()
                        HostDialogs.openEdit(model, host)
                    }
                }
                HStack {
                    Spacer()
                    Button("Done", action: close).buttonStyle(CoreButtonStyle(.prominent)).keyboardShortcut(.defaultAction)
                }
            }
        }
        .accessibilityIdentifier("host-advanced-sheet")
    }

    private func go(_ s: HostSection) {
        close()
        model.section = s
    }

    private func row(_ symbol: String, _ title: String, _ line: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: Space.s3) {
                IconTile(symbol, hue: GlassInk.slate, size: Space.s8 - Space.s2)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).coreFont(size: MacTextSize.body, weight: .medium)
                    Text(line).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").imageScale(.small).foregroundStyle(palette.text2)
            }
            .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading).coreWell(radius: Radius.control)
            .contentShape(coreShape(Radius.control))
        }
        .buttonStyle(.coreQuietPress)
    }
}
