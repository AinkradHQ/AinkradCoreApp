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

/// Access: how the host is reached and signed in to, its host key, the one AI rule, its group and tags, and the runner it can
/// become. The rule is the only control that writes in place; Change… opens the host sheet.
struct AccessPage: View {
    let model: LeylineModel
    let host: HostItem
    let state: HostPageState
    @State private var settled = false

    var body: some View {
        VStack(spacing: Space.s2) {
            HStack(alignment: .top, spacing: Space.s2) {
                connection.coreRise(settled, 0)
                aiRule.coreRise(settled, 1)
            }
            .frame(height: Space.s8 * 10)
            HStack(alignment: .top, spacing: Space.s2) {
                projects.coreRise(settled, 2)
                runner.coreRise(settled, 3)
            }
            .frame(maxHeight: .infinity)
        }
        .onAppear { settled = true }
        .accessibilityIdentifier("host-page-Access")
    }

    private func change(_ help: String) -> some View {
        Button("Change…") { HostDialogs.openEdit(model, host) }
            .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(model.readOnly).help(help)
    }

    // MARK: Connection

    private var connection: some View {
        Island("Connection") {
            VStack(alignment: .leading, spacing: Space.s4) {
                VStack(alignment: .leading, spacing: Space.s2) {
                    CoreFieldLabel("Reached through")
                    HStack(spacing: Space.s2) {
                        RouteChips(hops: model.route(host) + [host.name])
                        change("Change the jump hosts and where the connection starts")
                    }
                }
                VStack(alignment: .leading, spacing: Space.s2) {
                    CoreFieldLabel("Signs in as")
                    HStack(spacing: Space.s2) {
                        Image(systemName: "key").coreFont(size: MacTextSize.body, weight: .medium)
                            .accessibilityHidden(true)
                        Text(signsIn).lineLimit(2)
                        Spacer(minLength: Space.s2)
                        change("Change the user, the port or the key")
                    }
                }
                VStack(alignment: .leading, spacing: Space.s2) {
                    CoreFieldLabel("Host key")
                    hostKey
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

    @ViewBuilder private var hostKey: some View {
        let rule = "If it ever changes, Leyline stops before signing in and asks you."
        if let p = model.pinned(host) {
            HStack(alignment: .top, spacing: Space.s3) {
                FingerprintPattern(fingerprint: p.fingerprint)
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(
                        p.state == .changed
                            ? "Changed · review"
                            : p.since.map { "Trusted on \($0.formatted(.dateTime.day().month(.abbreviated)))" }
                                ?? "Trusted"
                    )
                    .coreFont(size: MacTextSize.body, weight: .medium)
                    Text(FingerprintPattern.short(p.fingerprint)).coreFont(size: MacTextSize.meta, design: .monospaced)
                        .foregroundStyle(GlassInk.secondary)
                    Text(rule).foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            // TODO(Y2-02): the Core pins the key on the first connect; until then there is nothing to show.
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Not pinned yet").coreFont(size: MacTextSize.body, weight: .medium)
                Text("Leyline keeps the host’s key the first time it connects. \(rule)")
                    .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: AI rule

    private var aiRule: some View {
        Island("AI on this host", sub: "one rule for AI sessions, agents and MCP") {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: Space.s2) {
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
                }
                Text(
                    (host.aiRule == .allowed
                        ? "Allowed needed Touch ID. Every AI command is still recorded in History."
                        : "Approvals come to the bell and the host page; approving uses Touch ID. Allowed needs Touch ID to turn on.")
                        + " Keys, host-key trust and Mac-direct are never available to AI."
                )
                .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("access-ai-rule")
    }

    // MARK: Projects, group and tags

    private var projects: some View {
        Island(
            title: "Projects", sub: nil,
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
                    CoreFieldLabel("Group and tags")
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

    private var runner: some View {
        Island(
            title: "Make it a runner", sub: "run AI sessions and projects here",
            accessory: {
                Button {
                    confirmRunner()
                } label: {
                    Label("Make Runner…", systemImage: "server.rack")
                }
                .buttonStyle(CoreButtonStyle(.prominent, busy: state.runnerState == .starting))
                .disabled(model.readOnly || host.runnerDevice != nil || busyInstalling)
                .help(
                    host.runnerDevice != nil
                        ? "This host is already a runner" : "Install the Ainkrad runner here (Touch ID)"
                )
                .accessibilityIdentifier("runner-make")
            }
        ) {
            VStack(alignment: .leading, spacing: Space.s3) {
                runnerStatus
                VStack(alignment: .leading, spacing: Space.s2) {
                    ForEach(
                        Array(
                            [
                                "Create a one-time invite", "Copy it to the host over SSH",
                                "Install the Ainkrad runner (system service with passwordless sudo, else for this user)",
                                "Pair with the Core",
                            ].enumerated()), id: \.offset
                    ) { i, step in
                        Text("\(i + 1). \(step)").foregroundStyle(GlassInk.secondary)
                    }
                }
            }
        }
        .accessibilityIdentifier("access-runner")
    }

    private var busyInstalling: Bool {
        switch state.runnerState {
        case .starting, .waiting: true
        default: false
        }
    }

    private func confirmRunner() { state.confirmRunner() }

    /// What the install is doing, and, once it paired, which machine claimed the invite: the invite is its own approval, so this
    /// is the person's one check that it is the machine they meant.
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
        default:
            if let device = host.runnerDevice { claimer(device) }
        }
    }

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
