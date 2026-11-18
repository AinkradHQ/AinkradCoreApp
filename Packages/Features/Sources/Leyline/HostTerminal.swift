import AppKit
import CoreUI
import Projects
import SwiftUI

/// Terminal: the host's shell opens in the app's own terminal pane (the one every terminal uses), relayed through the Core's
/// runner. Next to it, Mac-direct: this Mac's own `ssh` borrows the key for a few minutes, for this host only.
struct HostTerminalPage: View {
    let state: HostPageState
    @State private var settled = false

    var body: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            relayed.coreRise(settled, 0)
            MacDirectIsland(state: state).coreRise(settled, 1)
        }
        .onAppear { settled = true }
        .accessibilityIdentifier("host-page-Terminal")
    }

    private var relayed: some View {
        Island("Terminal", sub: "relayed through the Core") {
            VStack(alignment: .leading, spacing: Space.s4) {
                if let h = state.host {
                    RouteChips(hops: ["This Mac"] + state.model.route(h) + [h.name])
                }
                Text(
                    "Connect opens a terminal on this host in its own pane. The key stays in the Core. Closing the pane ends the session."
                )
                .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await state.connect() }
                } label: {
                    Label("Connect", systemImage: "terminal")
                }
                .buttonStyle(CoreButtonStyle(.prominent, busy: state.opening))
                .disabled(state.opening || state.model.readOnly)
                .help("Open a terminal on this host")
                .accessibilityIdentifier("terminal-connect")
            }
        }
        .accessibilityIdentifier("terminal-relayed")
    }
}

/// The Mac-direct lease. Off by default; Start asks Touch ID, shows the one command to use, and Revoke drops it at once.
struct MacDirectIsland: View {
    let state: HostPageState

    var body: some View {
        Island("Mac-direct", sub: "ssh, scp and rsync from this Mac") {
            VStack(alignment: .leading, spacing: Space.s4) {
                if let lease = state.direct {
                    CoreNotice(
                        symbol: "key", title: "This Mac may sign in to \(state.host?.name ?? "the host")",
                        text: lease.expiresAt.map {
                            "Ends \($0.formatted(date: .omitted, time: .shortened)), or when you revoke."
                        }
                            ?? "Ends in a few minutes, or when you revoke.", tone: .done)
                    CoreFieldLabel("Use it with")
                    Text(lease.command).coreFont(size: MacTextSize.meta, design: .monospaced).textSelection(.enabled)
                        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading).coreWell()
                    HStack(spacing: Space.s2) {
                        Button("Copy Command") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(lease.command, forType: .string)
                            state.model.host.shell.showToast("Command copied")
                        }
                        .buttonStyle(CoreButtonStyle(.secondary))
                        Button("Revoke") { Task { await state.stopDirect() } }
                            .buttonStyle(CoreButtonStyle(.quietDanger)).disabled(state.directBusy)
                            .help("Take the key back from this Mac now")
                    }
                } else {
                    Text(
                        "Your Mac’s own ssh borrows the key for a few minutes, for this host only. Nothing is written to disk, and AI can never start it."
                    )
                    .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                    Button {
                        Task { await state.startDirect() }
                    } label: {
                        Label("Start Mac-direct", systemImage: "touchid")
                    }
                    .buttonStyle(CoreButtonStyle(.secondary, busy: state.directBusy))
                    .disabled(state.directBusy || state.model.readOnly)
                    .help("Lend the key to this Mac for a few minutes (Touch ID)")
                    .accessibilityIdentifier("direct-start")
                }
            }
        }
        .accessibilityIdentifier("terminal-direct")
    }
}
