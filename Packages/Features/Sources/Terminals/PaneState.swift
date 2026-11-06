import CoreKit
import CoreUI
import Foundation

/// Where this window stands with one terminal's socket. The terminal's own state comes from the Core (`TerminalItem`).
enum Link: Equatable, Sendable {
    /// No socket here and none being opened (never attached, or detached).
    case none
    case attaching
    /// Attached here. `letterbox`: someone else typed last, so the terminal keeps their size and this window shows it inside.
    case attached(letterbox: Bool)
    case reconnecting
    /// The elevation lapsed (close 4003) or Touch ID was declined: the terminal runs on, a new attach needs Touch ID.
    case stepUp
    /// The attach was refused or the stream failed: the Core's code and words.
    case failed(code: String, message: String)
}

/// What a screen resumed with after a reconnect, shown until dismissed.
enum ResumeNote: Equatable, Sendable {
    case resumed(from: UInt64, to: UInt64)
    case repainted
}

enum PaneAction: String, Sendable { case attach, verify, retry, runner, dismiss, closePane, newTerminal }

/// Everything the terminal pane shows for one state: pure, so every state of the prototype is a test.
struct PaneView: Equatable {
    struct Chip: Equatable {
        var label: String
        var tone: Tone
        var symbol: String
    }
    struct Banner: Equatable {
        var tone: Tone
        var title: String
        var detail: String
        var busy = false
        var action: PaneAction?
        /// The raw code behind the words, for hover help.
        var help = ""
    }
    struct Card: Equatable {
        var title: String
        var body: String
        var note: String?
        var actions: [PaneAction]
    }
    enum Controls: Equatable { case running, ended, pending, endOnly }

    var chip: Chip
    var banner: Banner?
    var card: Card?
    var info: String
    var controls: Controls
    /// The screen is dimmed: it shows what this window last had, or a finished terminal.
    var dim = false
    var showsCursor = true
    var screenVisible = true

    static func label(_ action: PaneAction) -> String {
        switch action {
        case .attach: "Attach here"
        case .verify: "Verify with Touch ID"
        case .retry: "Check again"
        case .runner: "View runner"
        case .dismiss: "Dismiss"
        case .closePane: "Close pane"
        case .newTerminal: "New terminal"
        }
    }

    static func make(
        item t: TerminalItem, runner: RunnerItem?, link: Link, note: ResumeNote?
    ) -> PaneView {
        let machine = runner?.name ?? t.runner
        let sizeText = "\(t.cols)×\(t.rows)"
        let others = "\(t.attached) attached"

        if let u = unknown(item: t) { return u }
        // Ended terminals first: nothing else about the link matters.
        switch t.status {
        case "reaped":
            return PaneView(
                chip: .init(label: "Output gone", tone: .queue, symbol: "xmark.square"),
                card: .init(
                    title: "Output is gone",
                    body: "This terminal ended and its output is no longer kept, so there is nothing left to show.",
                    note: nil, actions: [.closePane]),
                info: "Ended", controls: .ended, screenVisible: false)
        case "exited":
            if t.hostLost {
                return PaneView(
                    chip: .init(label: "Exited · runner lost it", tone: .fail, symbol: "wifi.exclamationmark"),
                    banner: .init(
                        tone: .fail, title: "Ended: the runner lost it",
                        detail:
                            "The terminal host process on \(machine) was killed, so the shell ended without an exit code. It cannot be recovered.",
                        help: "host_lost"
                    ),
                    card: .init(
                        title: "Terminal lost",
                        body: "Whatever was running here on \(machine) is gone. Open a new terminal to continue.",
                        note: nil, actions: [.closePane, .newTerminal]),
                    info: "Ended without an exit code.", controls: .ended, dim: true, showsCursor: false,
                    screenVisible: false)
            }
            let how: String
            if let s = t.exitSignal {
                how = "signal \(s)"
            } else if let c = t.exitCode {
                how = "code \(c)"
            } else {
                how = "no exit code"
            }
            return PaneView(
                chip: .init(label: "Exited · \(how)", tone: .queue, symbol: "checkmark.square"),
                banner: .init(
                    tone: .queue, title: "Exited with \(how)",
                    detail: "Output stays readable for a while after exit. Nothing can be typed here."),
                info: "Read-only.", controls: .ended, dim: true, showsCursor: false)
        default: break
        }

        if runner?.online == false, !isAttached(link) {
            return PaneView(
                chip: .init(label: "Runner offline", tone: .fail, symbol: "wifi.slash"),
                banner: .init(
                    tone: .fail, title: "\(machine) is not connected",
                    detail:
                        "The Core can’t reach this terminal while its runner is disconnected. Terminal output only ever lives on the runner.",
                    action: .runner, help: "runner_offline"),
                card: .init(
                    title: "Can’t attach right now", body: "Attach again once \(machine) reconnects.", note: nil,
                    actions: [.retry]),
                info: "Can’t reach \(machine)", controls: .endOnly, screenVisible: false)
        }

        switch link {
        case .attaching:
            return PaneView(
                chip: .init(label: "Attaching", tone: .done, symbol: "arrow.triangle.2.circlepath"),
                banner: .init(
                    tone: .done, title: "Attaching to \(machine)",
                    detail: "Opening the connection and replaying the screen.", busy: true),
                info: "Input starts when the screen is back", controls: .pending, dim: true, showsCursor: false)
        case .reconnecting:
            return PaneView(
                chip: .init(label: "Reconnecting", tone: .done, symbol: "arrow.triangle.2.circlepath"),
                banner: .init(
                    tone: .done, title: "Reconnecting, resuming from where you were",
                    detail:
                        "The connection went quiet. Your screen stays as it was. Output replays from the last byte you saw, so nothing is lost.",
                    busy: true),
                info: "Input is paused until the connection is back", controls: .pending, dim: true,
                showsCursor: false)
        case .stepUp:
            return PaneView(
                chip: .init(label: "Verification expired", tone: .warn, symbol: "touchid"),
                banner: .init(
                    tone: .warn, title: "Verification expired. Your terminal is still running",
                    detail:
                        "Verification lasts 5 minutes. The connection was closed but the terminal keeps running. What you see is the last screen this window had.",
                    help: "Step-up expired (close code 4003)"
                ),
                card: .init(
                    title: "Verify to reattach",
                    body: "Confirm it is you to attach again. Terminals keep running without you.",
                    note: nil, actions: [.verify]),
                info: "Socket closed · still running on \(machine)", controls: .pending, dim: true,
                showsCursor: false)
        case .failed(let code, let message):
            return PaneView(
                chip: .init(label: "Can’t attach", tone: .fail, symbol: "exclamationmark.triangle"),
                banner: .init(
                    tone: .fail, title: message.isEmpty ? "The Core refused that" : message,
                    detail: "Try again in a moment.", help: code),
                card: .init(
                    title: "Can’t attach right now", body: "The terminal is not changed by this. Try again.", note: nil,
                    actions: [.retry]),
                info: "Not attached", controls: .endOnly, screenVisible: false)
        case .attached(let letterbox):
            var v = PaneView(
                chip: .init(label: "Attached", tone: .run, symbol: "terminal"), info: "\(sizeText) · \(others)",
                controls: .running)
            if letterbox {
                v.banner = .init(
                    tone: .queue, title: "Sized by another device (\(sizeText))",
                    detail:
                        "The terminal follows whoever typed last, and everyone else sees it letterboxed. Type here and it resizes to this window; a resize you make without typing is held until you do."
                )
                v.info = "\(sizeText) · letterboxed · \(others)"
            } else {
                v.info = "\(sizeText) · sized by this Mac · \(others)"
            }
            switch note {
            case .resumed(let from, let to)?:
                v.banner = .init(
                    tone: .run, title: "Resumed. Nothing was lost",
                    detail: "Replayed the output you missed",
                    action: .dismiss, help: "Replayed from byte \(from.formatted()) to \(to.formatted()).")
            case .repainted?:
                v.banner = .init(
                    tone: .done, title: "Screen repainted from a snapshot",
                    detail:
                        "You were away longer than the replay buffer, so the screen was redrawn as it is now. Output in between is not shown. A brief redraw is normal.",
                    action: .dismiss)
            case nil: break
            }
            return v
        case .none:
            if t.attached > 0 {
                return PaneView(
                    chip: .init(label: "Attached elsewhere", tone: .done, symbol: "rectangle.on.rectangle"),
                    card: .init(
                        title: "Attached on another device",
                        body:
                            "\(t.attached) other \(t.attached == 1 ? "client is" : "clients are") attached to this terminal on \(machine). Attach here and all stay attached. There is no input lock: any of them can type, and the terminal takes the size of whoever typed last.",
                        note: "Needs Touch ID. The screen repaints from a snapshot.", actions: [.attach]),
                    info: "Not attached here · \(sizeText) · \(others)", controls: .endOnly, screenVisible: false)
            }
            return PaneView(
                chip: .init(label: "Running, not attached", tone: .queue, symbol: "pause.rectangle"),
                card: .init(
                    title: "Still running",
                    body:
                        "This terminal is running on \(machine) with no one attached. Detaching never stops it. Attach to see it again.",
                    note: t.orphaned
                        ? "Needs Touch ID. The Core closes a terminal nobody attaches to once it has been idle for too long."
                        : "Needs Touch ID.",
                    actions: [.attach]),
                info: t.orphaned ? "Nobody is attached · closes when idle" : "Nobody is attached",
                controls: .endOnly, screenVisible: false)
        }
    }

    private static func isAttached(_ l: Link) -> Bool {
        if case .attached = l { true } else { false }
    }

    /// Unknown statuses show their raw word (every enum is open).
    static func unknown(item t: TerminalItem) -> PaneView? {
        guard !["created", "running", "exited", "reaped"].contains(t.status) else { return nil }
        return PaneView(
            chip: .init(label: "Newer state", tone: .queue, symbol: "questionmark.square"),
            banner: .init(tone: .queue, title: "A newer state", detail: "This app does not know that state yet."),
            info: t.status, controls: .endOnly, dim: true, showsCursor: false, screenVisible: false)
    }
}

/// The signals the protocol takes (spec §2).
enum TerminalSignals {
    static let all = ["HUP", "INT", "QUIT", "TERM", "KILL", "USR1", "USR2", "CONT", "STOP", "TSTP", "WINCH"]

    /// What each signal does, in words (the signal name stays a help text where there is room for one).
    static func title(_ name: String) -> String {
        switch name {
        case "HUP": "Hang up"
        case "INT": "Interrupt (Ctrl-C)"
        case "QUIT": "Quit"
        case "TERM": "Stop"
        case "KILL": "Kill"
        case "USR1": "User signal 1"
        case "USR2": "User signal 2"
        case "CONT": "Continue"
        case "STOP": "Freeze"
        case "TSTP": "Suspend (Ctrl-Z)"
        case "WINCH": "Window resized"
        default: name
        }
    }
}
