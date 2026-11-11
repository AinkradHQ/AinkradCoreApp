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
                chip: .init(label: "Output gone", tone: .queue, symbol: "xmark.circle"),
                card: .init(
                    title: "Output is gone",
                    body: "This terminal ended and its output is no longer kept, so there is nothing left to show.",
                    note: nil, actions: [.closePane]),
                info: "Ended", controls: .ended, screenVisible: false)
        case "exited":
            if t.hostLost {
                return PaneView(
                    chip: .init(label: "Exited · host_lost", tone: .fail, symbol: "wifi.exclamationmark"),
                    banner: .init(
                        tone: .fail, title: "Ended: host_lost",
                        detail:
                            "The terminal host process on \(machine) was killed, so the shell ended without an exit code. It cannot be recovered."
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
                chip: .init(label: "Exited · \(how)", tone: .queue, symbol: "checkmark.circle"),
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
                    action: .runner),
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
                    tone: .warn, title: "Verification expired. Your terminal is still running.",
                    detail:
                        "Verification lasts 5 minutes. The connection was closed (4003 step-up expired) but the terminal keeps running. What you see is the last screen this window had."
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
                banner: .init(tone: .fail, title: message.isEmpty ? "The Core refused that." : message, detail: code),
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
                    tone: .run, title: "Resumed. Nothing was lost.",
                    detail: "Replayed from byte \(from.formatted()) to \(to.formatted()) while you were away.",
                    action: .dismiss)
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
                chip: .init(label: "Running, not attached", tone: .queue, symbol: "pause.circle"),
                card: .init(
                    title: "Still running",
                    body:
                        "This terminal is running on \(machine) with no one attached. Detaching never stops it. Attach to see it again.",
                    note: t.orphaned
                        ? "Needs Touch ID. The Core closes a terminal nobody attaches to once it has been idle past terminal.idle_secs."
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
            chip: .init(label: t.status, tone: .queue, symbol: "questionmark.circle"),
            banner: .init(tone: .queue, title: t.status, detail: "This app does not know that state yet."),
            info: t.status, controls: .endOnly, dim: true, showsCursor: false, screenVisible: false)
    }
}

/// What the app offers for the command running in a terminal (N21), in plain words. The protocol takes more signals; they stay
/// for `ainkradctl`. Stop and Pause do what Ctrl-C and Ctrl-Z do at the keyboard, so only Force quit asks for Touch ID.
enum RunningCommand: CaseIterable {
    case stop, pause, resume, forceQuit

    var signal: String {
        switch self {
        case .stop: "INT"
        case .pause: "TSTP"
        case .resume: "CONT"
        case .forceQuit: "KILL"
        }
    }
    var title: String {
        switch self {
        case .stop: "Stop it"
        case .pause: "Pause it"
        case .resume: "Resume it"
        case .forceQuit: "Force quit…"
        }
    }
    var help: String {
        switch self {
        case .stop: "Stops the command that is running, like Ctrl-C. The terminal stays open."
        case .pause: "Pauses the command. Resume continues it from the same point."
        case .resume: "Continues the paused command from the same point."
        case .forceQuit: "Use only when Stop does not work. The command ends at once and can lose unsaved work."
        }
    }
    var symbol: String {
        switch self {
        case .stop: "stop"
        case .pause: "pause"
        case .resume: "play"
        case .forceQuit: "xmark.octagon"
        }
    }
    var done: String {
        switch self {
        case .stop: "Stopped the running command"
        case .pause: "Paused the running command"
        case .resume: "Resumed the command"
        case .forceQuit: "Force quit the running command"
        }
    }
    var needsTouchID: Bool { self == .forceQuit }
}
