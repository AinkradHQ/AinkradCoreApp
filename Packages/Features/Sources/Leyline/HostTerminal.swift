import Admin
import AppKit
import CoreUI
import Projects
import SwiftUI

/// Terminal: a real shell on the host, drawn over the whole pane by the app's terminal emulator and relayed through the Core
/// (the key stays in the Core). It opens when the view does (Touch ID first, like every terminal), and coming back to the host
/// shows the same one. With no terminal app (the Debug demo) a stand-in screen shows instead. A runner too old for ssh, or a
/// terminal that did not open, is the state card with its fix, never a bare sentence.
struct HostTerminalTab: View {
    let model: LeylineModel
    let host: HostItem
    let state: HostPageState
    @State private var failure: String?
    @State private var opening = false
    @Environment(\.coreAccent) private var paneAccent

    var body: some View {
        Group {
            if let p = state.problem {
                HostProblemCard(problem: p, model: model, hostID: host.id) { await open() }.hostPage()
            } else if state.hostKeys.asked != nil {
                // Terminals refuse until the key is trusted: the one prompt, never "Exited with code 70".
                HostKeyPrompt(state: state).hostPage()
            } else if model.terminalView == nil {
                surface(StandInTerminal(host: host))
            } else if let id = model.hostTerminals[host.id], let v = model.terminalView?(id, ended) {
                surface(v)
            } else if let failure {
                LeylineStateCard(
                    symbol: "terminal", title: "The terminal did not open", text: failure, tone: .warn
                ) {
                    AppActionTile(
                        title: "Try Again", symbol: "arrow.clockwise", key: "", hue: GlassInk.accent(paneAccent),
                        prominent: true
                    ) { Task { await open() } }
                }
                .hostPage()
            } else {
                VStack(spacing: Space.s3) {
                    CoreBusyBar().frame(maxWidth: Space.s8 * 5)
                    Text("Opening a terminal on \(host.name)…").foregroundStyle(GlassInk.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
        // Again once the key is trusted from the prompt.
        .task(id: state.hostKeys) {
            guard state.hostKeys != .unknown else { return }
            if model.terminalView != nil, model.hostTerminals[host.id] == nil, state.problem == nil,
                state.hostKeys.asked == nil
            {
                await open()
            }
        }
        .accessibilityIdentifier("host-page-Terminal")
    }

    /// A shell that ends at once with 70 met a host key nobody pinned: the Core stored what it saw, so the prompt takes over.
    private func ended(_ code: Int32) {
        guard code == 70 else { return }
        Task {
            await state.loadHostKeys()
            if state.hostKeys.asked != nil { model.hostTerminals[host.id] = nil }
        }
    }

    private func surface(_ v: some View) -> some View {
        v.clipShape(coreShape(Radius.cardMac)).padding(.horizontal, Space.s4).padding(.bottom, Space.s4)
    }

    private func open() async {
        guard !opening, model.terminalView != nil else { return }
        opening = true
        defer { opening = false }
        failure = nil
        do { _ = try await model.terminal(for: host.id) } catch is AdminDeclined {
            failure = "The terminal needs Touch ID. Try again when you are ready."
        } catch {
            state.note(error)
            failure = model.words(error)
        }
    }
}

/// The Debug demo's terminal: what a real one would show, in the terminal's own colours. Never on a live Core.
struct StandInTerminal: View {
    let host: HostItem
    @Environment(\.coreLook) private var look
    @Environment(\.corePalette) private var palette
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
        .font(.core(size: 12.5, design: .monospaced, scale: TextSizePrefs.shared.scale)).lineSpacing(Space.s1)
        .foregroundStyle(Color(red: 0.84, green: 0.86, blue: 0.9))
        .padding(.horizontal, Space.s4 + 2).padding(.vertical, Space.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The surface every terminal pane draws (TerminalPaneView): the Look's night surface at its transparency and blur,
        // at least 0.85 by day so the light glass under it does not wash it grey.
        .background {
            AppSurfaceFill(
                style: look.mode.style, opacity: palette.isDay ? max(0.85, look.opacity) : look.opacity,
                blur: look.mode.blur, radius: 0, blurAmount: look.blur
            )
            .environment(\.corePalette, .night)
        }
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
