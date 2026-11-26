import Admin
import CoreUI
import Projects
import Shell
import SwiftUI

/// Shown under the top bar for as long as a Mac-direct lease is open, whatever page the person is on.
struct DirectBanner: View {
    let state: HostPageState
    let lease: DirectLease

    var body: some View {
        CoreNotice(
            symbol: "key", title: "Mac-direct is on",
            text: lease.expiresAt.map {
                "This Mac may sign in to \(state.host?.name ?? "the host") until \($0.formatted(date: .omitted, time: .shortened))."
            }
                ?? "This Mac may sign in to \(state.host?.name ?? "the host") for a few minutes.", tone: .done
        ) {
            Button("Revoke") { Task { await state.stopDirect() } }
                .buttonStyle(CoreButtonStyle(.quietDanger, size: .small)).disabled(state.directBusy)
        }
        .accessibilityIdentifier("direct-banner")
    }
}

/// "This Mac — Core — jump host — the host": the route a connection takes, as chips on a line.
/// TODO(design-system): proposal CoreRouteChips (the chips with the animated wires of the mockup).
struct RouteChips: View {
    let hops: [String]
    @Environment(\.corePalette) private var palette

    var body: some View {
        HStack(spacing: Space.s1) {
            ForEach(Array(hops.enumerated()), id: \.offset) { i, hop in
                if i > 0 {
                    coreShape(1).fill(palette.track).frame(width: Space.s3, height: 2).accessibilityHidden(true)
                }
                CoreChip(hop, minWidth: 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reached through \(hops.joined(separator: ", then "))")
    }
}

// MARK: Access

/// Access, the slide-over panel (⌘, toggles it, Esc closes it): how the host is reached and signed in to, its host key, the
/// one AI rule, the runner it can become, and its group and tags. The rule is the only control that writes in place;
/// Change… opens the host sheet. Same size and margins as the Keys panel.
struct AccessPanel: View {
    let model: LeylineModel
    let host: HostItem
    let state: HostPageState

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text("Access").coreFont(size: MacTextSize.title, weight: .semibold).accessibilityAddTraits(.isHeader)
                Text(host.name).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
                Spacer(minLength: Space.s2)
                Button("esc") { model.accessOpen = false }
                    .buttonStyle(CoreButtonStyle(.plain, size: .small))
                    .help("Close Access (esc)")
                    .accessibilityLabel("Close Access")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s3) {
                    connection
                    aiRule
                    runner
                    projects
                }
                .padding(.bottom, Space.s1)
            }
            .scrollIndicators(.automatic)
            Text("⌘, toggle · esc close").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                .frame(maxWidth: .infinity).accessibilityHidden(true)
        }
        .frame(width: KeysPanel.width - Space.s4 * 2)
        .frame(maxHeight: .infinity, alignment: .top)
        .corePanel(radius: Radius.pane, padding: Space.s4)
        .contentShape(coreShape(Radius.pane))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Access")
        .accessibilityIdentifier("host-page-Access")
    }

    /// One part of the panel: a title, a quiet line, what sits at its right, then its content, on a well.
    private func part<C: View, A: View>(
        _ title: String, sub: String? = nil, @ViewBuilder accessory: () -> A, @ViewBuilder content: () -> C
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text(title).coreFont(size: MacTextSize.headline, weight: .semibold).accessibilityAddTraits(.isHeader)
                if let sub {
                    Text(sub).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                accessory()
            }
            content()
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .coreWell(radius: Radius.cardMac)
        .accessibilityElement(children: .contain)
    }

    private func change(_ help: String) -> some View {
        Button("Change…") { HostDialogs.openEdit(model, host) }
            .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(model.readOnly).help(help)
    }

    // MARK: Connection

    private var connection: some View {
        part("Connection", accessory: { change("Change the jump hosts, the user, the port or the key") }) {
            VStack(alignment: .leading, spacing: Space.s4) {
                VStack(alignment: .leading, spacing: Space.s2) {
                    CoreFieldLabel("Reached through")
                    RouteChips(hops: model.route(host) + [host.name])
                }
                VStack(alignment: .leading, spacing: Space.s2) {
                    CoreFieldLabel("Signs in as")
                    HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                        Image(systemName: "key").coreFont(size: MacTextSize.body, weight: .medium)
                            .accessibilityHidden(true)
                        Text(signsIn).fixedSize(horizontal: false, vertical: true)
                    }
                }
                VStack(alignment: .leading, spacing: Space.s2) {
                    CoreFieldLabel("Host key")
                    HostKeySection(state: state)
                }
            }
        }
        .accessibilityIdentifier("access-connection")
    }

    private var signsIn: String {
        guard let k = model.key(host.keyID) else {
            return host.keyID == nil
                ? "\(host.login) · a password typed in the terminal" : "\(host.login) · a key that is gone"
        }
        return "\(host.login) · key “\(k.name)” (\(k.typeWord))"
    }

    // MARK: AI rule

    private var aiRule: some View {
        part("AI on this host", sub: "AI sessions, agents and MCP", accessory: { EmptyView() }) {
            VStack(alignment: .leading, spacing: Space.s2) {
                ForEach(AIRule.allCases) { r in
                    RadioRow(
                        r.title, subtitle: r.line, selected: host.aiRule == r,
                        action: { Task { await model.setRule(host, r) } }
                    ) {
                        if r == .allowed {
                            Image(systemName: "touchid").foregroundStyle(GlassInk.secondary)
                                .accessibilityLabel("Needs Touch ID")
                        }
                    }
                    .disabled(model.readOnly)
                    .accessibilityIdentifier("ai-rule-\(r.wire)")
                }
                Text(
                    (host.aiRule == .allowed
                        ? "Allowed needed Touch ID. Every AI command is still recorded in History."
                        : "Approvals come to the bell and the host page; approving uses Touch ID. Allowed needs Touch ID to turn on.")
                        + " Keys, host-key trust and Mac-direct are never available to AI."
                )
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("access-ai-rule")
    }

    // MARK: Projects, group and tags

    private var projects: some View {
        part(
            "Group and tags",
            accessory: {
                // TODO(Y9-03): attaching a host to a project, with a role, needs a Core route; today only the group is stored.
                Soon(prominent: false, help: "Attaching a host to a project arrives with the project link") {
                    Label("Attach", systemImage: "plus")
                }
            }
        ) {
            VStack(alignment: .leading, spacing: Space.s4) {
                if let g = host.group {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text(g).coreFont(size: MacTextSize.body, weight: .medium)
                        Text("Grouped with the other hosts called \(g) in the gallery.")
                            .foregroundStyle(GlassInk.secondary)
                    }
                } else {
                    Text("Not in a project. Give it a group and it sits with the others in the gallery.")
                        .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: Space.s2) {
                    CoreFieldLabel("In the gallery")
                    HStack(spacing: Space.s2) {
                        if let g = host.group { CoreChip(g, minWidth: 0) }
                        ForEach(host.tags, id: \.self) { CoreChip($0, minWidth: 0) }
                        CoreIconButton(symbol: "plus", label: "Change the group and tags") {
                            HostDialogs.openEdit(model, host)
                        }
                        .disabled(model.readOnly)
                    }
                }
            }
        }
        .accessibilityIdentifier("access-projects")
    }

    // MARK: Make it a runner

    /// A host that is a runner says so (with its runner's page in Machines); only one that is not offers Make Runner.
    private var runner: some View {
        part("Runner", sub: "run AI sessions and projects here", accessory: { EmptyView() }) {
            VStack(alignment: .leading, spacing: Space.s3) {
                if let r = model.runner(of: host), !busyInstalling {
                    isRunner(r)
                } else if let device = host.runnerDevice, !busyInstalling {
                    claimer(device)
                } else {
                    makeRunner
                }
            }
        }
        .accessibilityIdentifier("access-runner")
    }

    @ViewBuilder private func isRunner(_ r: RunnerSummary) -> some View {
        CoreNotice(
            symbol: "server.rack", title: "This host runs a runner",
            text: "\(r.name) · \(r.online ? "Online" : "Offline")", tone: r.online ? .done : .queue
        )
        .accessibilityIdentifier("runner-match")
        if let open = model.openRunner {
            Button("Open in Machines") { open(r.id) }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
        }
    }

    @ViewBuilder private var makeRunner: some View {
        runnerStatus
        VStack(alignment: .leading, spacing: Space.s1) {
            ForEach(
                Array(
                    [
                        "Create a one-time invite", "Copy it to the host over SSH",
                        "Install the Ainkrad runner (system service with passwordless sudo, else for this user)",
                        "Pair with the Core",
                    ].enumerated()), id: \.offset
            ) { i, step in
                Text("\(i + 1). \(step)").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        Button {
            state.confirmRunner()
        } label: {
            Label("Make Runner…", systemImage: "server.rack")
        }
        .buttonStyle(CoreButtonStyle(.secondary, busy: state.runnerState == .starting))
        .disabled(model.readOnly || busyInstalling)
        .help("Install the Ainkrad runner here (Touch ID)")
        .accessibilityIdentifier("runner-make")
    }

    private var busyInstalling: Bool {
        switch state.runnerState {
        case .starting, .waiting: true
        default: false
        }
    }

    /// What the install is doing: the invite is its own approval, so the paired notice is the person's one check that it is
    /// the machine they meant.
    @ViewBuilder private var runnerStatus: some View {
        switch state.runnerState {
        case .waiting(let until):
            CoreNotice(
                symbol: "arrow.down.circle", title: "Installing the runner",
                text: until.map {
                    "Ainkrad is installing it over SSH. The invite ends \($0.formatted(date: .omitted, time: .shortened))."
                }
                    ?? "Ainkrad is installing it over SSH.", tone: .queue)
        case .expired:
            CoreNotice(
                symbol: "clock.badge.exclamationmark", title: "The invite ended",
                text: "Nothing was installed and the invite is gone. Start again.", tone: .warn)
        case .failed(let why):
            CoreNotice(symbol: "exclamationmark.triangle", title: "The install did not finish", text: why, tone: .fail)
        default: EmptyView()
        }
    }

    /// Paired, but the runner is not in the list (yet): who claimed the invite.
    private func claimer(_ device: String) -> some View {
        let c = model.deviceLookup?(device)
        let facts = [c?.name, c?.platform, c?.fingerprint.map { "key \($0)" }].compactMap { $0 }
        return CoreNotice(
            symbol: "checkmark.seal", title: "This host is a runner",
            text: facts.isEmpty
                ? "Paired as device \(device)."
                : "Paired as \(facts.joined(separator: " · ")). Check it is the machine you meant.", tone: .done
        )
        .accessibilityIdentifier("runner-claimer")
    }
}
