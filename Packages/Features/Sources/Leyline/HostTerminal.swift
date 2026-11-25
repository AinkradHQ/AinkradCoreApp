import Admin
import AppKit
import CoreUI
import Projects
import SwiftUI

/// Terminal: a real shell on the host, drawn right here by the app's terminal emulator and relayed through the Core (the key
/// stays in the Core). It opens as soon as the view does (Touch ID first, like every terminal), and coming back to the host
/// shows the same one. With no terminal app (the Debug demo) a stand-in screen shows instead.
struct HostTerminalTab: View {
    let model: LeylineModel
    let host: HostItem
    @State private var failure: String?
    @State private var opening = false

    var body: some View {
        Group {
            if model.terminalView == nil {
                StandInTerminal(host: host)
            } else if let id = model.hostTerminals[host.id], let v = model.terminalView?(id) {
                v
            } else if let failure {
                VStack(alignment: .leading, spacing: Space.s3) {
                    Text(failure).foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Try Again") { Task { await open() } }.buttonStyle(CoreButtonStyle(.secondary))
                }
                .padding(Space.s4).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Text("Opening a terminal on \(host.name)…").foregroundStyle(GlassInk.secondary)
                    .padding(Space.s4).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .task(id: host.id) { if model.terminalView != nil, model.hostTerminals[host.id] == nil { await open() } }
        .accessibilityIdentifier("host-page-Terminal")
    }

    private func open() async {
        guard !opening else { return }
        opening = true
        defer { opening = false }
        failure = nil
        do { _ = try await model.terminal(for: host.id) } catch is AdminDeclined {
            failure = "The terminal needs Touch ID. Try again when you are ready."
        } catch { failure = model.words(error) }
    }
}

/// The Debug demo's terminal: what a real one would show, in the terminal's own colours. Never on a live Core.
struct StandInTerminal: View {
    let host: HostItem
    var body: some View {
        let p =
            Text("\(host.login)").foregroundStyle(Color(red: 0.56, green: 0.82, blue: 0.56))
            + Text(":").foregroundStyle(Color(red: 0.84, green: 0.86, blue: 0.9))
            + Text("~").foregroundStyle(Color(red: 0.48, green: 0.65, blue: 1)) + Text("$ ")
        let out = Text(
            " 10:42:07 up 23 days,  4:11,  1 user,  load average: 0.58, 0.61, 0.66\n")
        VStack(alignment: .leading, spacing: 0) {
            p + Text("uptime\n") + out + p + Text("df -h /\n")
                + Text("Filesystem      Size  Used Avail Use% Mounted on\n/dev/sda1        80G   49G   31G  61% /\n")
                + p
                + Text("▍")
        }
        .font(.system(size: 12.5, design: .monospaced)).lineSpacing(4)
        .foregroundStyle(Color(red: 0.84, green: 0.86, blue: 0.9))
        .padding(.horizontal, Space.s4 + 2).padding(.vertical, Space.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.043, green: 0.051, blue: 0.07))
        .accessibilityLabel("Terminal on \(host.name)")
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
