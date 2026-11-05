import CoreKit
import CoreUI
import Foundation
import Observation

/// One terminal pane: the terminal's state from the Core, this window's link to it, and the screen. All decisions about
/// attach, detach, reconnect and resize live here; the views only read it.
@MainActor @Observable
final class TerminalSession {
    let id: String
    private(set) var item: TerminalItem
    private(set) var runner: RunnerItem?
    private(set) var link: Link = .none
    private(set) var note: ResumeNote?
    /// Set when a refetch found the terminal gone from the list.
    var signalsOpen = false
    let surface: TerminalSurface

    @ObservationIgnored private let service: any TerminalService
    @ObservationIgnored private let host: any TerminalHost
    @ObservationIgnored private var attachment: (any TerminalLink)?
    @ObservationIgnored private var pump: Task<Void, Never>?
    @ObservationIgnored private var reattach: Task<Void, Never>?
    @ObservationIgnored private var cursor: UInt64?
    @ObservationIgnored private var lastLetterbox = false
    @ObservationIgnored private var firstOutputAfterReattach = false
    /// When output arrived, at most one stamp a second, newest last: the "output this Mac has seen" the tile's strip is drawn from.
    /// The Core stores no output, so this is the only history there is, and it starts when this Mac attaches.
    @ObservationIgnored private(set) var outputTimes: [Date] = []
    @ObservationIgnored var onBell: (() -> Void)?
    @ObservationIgnored var onChange: (() -> Void)?

    init(item: TerminalItem, runner: RunnerItem?, service: any TerminalService, host: any TerminalHost) {
        self.id = item.id
        self.item = item
        self.runner = runner
        self.service = service
        self.host = host
        surface = TerminalSurface()
        surface.onInput = { [weak self] in self?.typed($0) }
        surface.onFit = { [weak self] cols, rows in self?.fit(cols, rows) }
        surface.onBell = { [weak self] in self?.onBell?() }
    }

    var view: PaneView { PaneView.make(item: item, runner: runner, link: link, note: note) }
    var isAttached: Bool { if case .attached = link { true } else { false } }
    var machine: String { runner?.name ?? item.runner }

    func apply(item new: TerminalItem, runner: RunnerItem?) {
        // Only a real change is a change: a refetch that found nothing new must not redraw the pane.
        guard item != new || self.runner != runner else { return }
        item = new
        self.runner = runner
        onChange?()
    }

    func dismissNote() { note = nil }

    func noteOutput(at now: Date = Date()) {
        if let last = outputTimes.last, now.timeIntervalSince(last) < 1 { return }
        outputTimes.append(now)
        if outputTimes.count > 4000 { outputTimes.removeFirst(1000) }
    }

    /// Twelve slices of five minutes, oldest first, 0...1.
    func heat(now: Date = Date()) -> [Double] { heatBuckets(outputTimes, now: now, slice: 300, count: 12) }

    // MARK: attach

    /// Attaches (Touch ID when the session is not elevated). `prompt: false` never asks: a lapsed elevation is `.stepUp`.
    func attach(prompt: Bool = true) async {
        guard !isAttached, link != .attaching else { return }
        reattach?.cancel()
        link = .attaching
        note = nil
        host.clearElevationNotice()
        let after = cursor ?? 0
        do {
            let l: any TerminalLink
            if prompt {
                l = try await host.elevated("Attach to the terminal on \(machine).", done: "attached") {
                    try await self.service.attach(self.id, after: after)
                }
            } else {
                guard host.isElevated else {
                    link = .stepUp
                    return
                }
                l = try await service.attach(id, after: after)
            }
            begin(l, after: after)
        } catch is ElevationDeclined {
            link = .stepUp
        } catch { failed(error) }
    }

    private func begin(_ l: any TerminalLink, after: UInt64) {
        attachment = l
        let resuming = link == .reconnecting
        let others = item.attached
        let opened = l.opened
        item.status = opened.state == "exited" ? "exited" : item.status
        // Someone else is attached: the terminal keeps their size and this window shows it inside, until we type.
        // A reconnect keeps the mode it had: the Core may still count the socket that just dropped.
        let letterbox = resuming ? lastLetterbox : others > 0 && opened.cols > 0 && opened.rows > 0
        lastLetterbox = letterbox
        if letterbox {
            surface.layoutMode(.letterbox(cols: opened.cols, rows: opened.rows))
            item.cols = opened.cols
            item.rows = opened.rows
        } else {
            surface.layoutMode(.fill)
            let size = surface.size
            if size.cols > 0, (size.cols, size.rows) != (opened.cols, opened.rows) {
                l.resize(rows: size.rows, cols: size.cols)
                item.cols = size.cols
                item.rows = size.rows
            }
        }
        firstOutputAfterReattach = after > 0 && opened.seq > after
        link = .attached(letterbox: letterbox)
        pump = Task { [weak self] in
            for await update in l.updates {
                guard let self else { return }
                self.handle(update, from: l, after: after)
            }
        }
        surface.focus()
        onChange?()
    }

    private func handle(_ update: TerminalUpdate, from l: any TerminalLink, after: UInt64) {
        guard attachment != nil else { return }
        switch update {
        case .output(let d):
            if firstOutputAfterReattach {
                firstOutputAfterReattach = false
                note = .resumed(from: after, to: l.opened.seq)
            }
            noteOutput()
            surface.feed(d)
            l.drawn(d.count)
        case .snapshot(let d):
            if after > 0 { note = .repainted }
            firstOutputAfterReattach = false
            surface.feed(d, repaint: true)
            l.drawn(d.count)
        case .exited(let code, let signal):
            item.status = "exited"
            item.exitCode = code
            item.exitSignal = signal
            cursor = l.cursor
            end(l)
            onChange?()
        case .failed(let code, let message):
            link = .failed(code: code, message: message)
        case .closed(let why):
            cursor = l.cursor
            attachment = nil
            switch why {
            case .dropped: reconnect()
            case .stepUpExpired, .scopeChanged: link = .stepUp
            case .revoked: link = .failed(code: "revoked", message: "This device was revoked.")
            case .detached: if link != .stepUp { link = .none }
            }
            onChange?()
        }
    }

    private func end(_ l: any TerminalLink) {
        l.detach()
        attachment = nil
        pump?.cancel()
        link = .none
    }

    /// The socket dropped: ask again after the last byte, never prompting for Touch ID by itself.
    private func reconnect() {
        guard item.status != "exited" else {
            link = .none
            return
        }
        link = .reconnecting
        reattach?.cancel()
        reattach = Task { [weak self] in
            var wait = 0.5
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(wait))
                guard let self, !Task.isCancelled else { return }
                if await self.tryReattach() { return }
                wait = min(wait * 2, 8)
            }
        }
    }

    /// True when the loop is over (attached, or the reason is final).
    private func tryReattach() async -> Bool {
        guard host.isElevated else {
            link = .stepUp
            return true
        }
        let after = cursor ?? 0
        do {
            let l = try await service.attach(id, after: after)
            begin(l, after: after)
            return true
        } catch let e as CoreError {
            switch e {
            case .offline, .coreUnproven, .sessionExpired, .rateLimited: return false
            case .stepUpRequired:
                link = .stepUp
                return true
            default:
                failed(e)
                return true
            }
        } catch { return false }
    }

    private func failed(_ error: any Error) {
        let e = CoreError.unwrapping(error) ?? error
        switch e as? CoreError {
        case .stepUpRequired?: link = .stepUp
        case .http(_, let code, let message)?: link = .failed(code: code, message: message)
        case .forbiddenScope?:
            link = .failed(code: "forbidden_scope", message: "This device may not use terminals.")
        case .rateLimited?: link = .failed(code: "rate_limited", message: "Too many requests. Try again shortly.")
        case let c?: link = .failed(code: "error", message: c.localizedDescription)
        case nil: link = .failed(code: "error", message: error.localizedDescription)
        }
        Task { await refresh() }
    }

    /// Detach: the socket closes, the terminal keeps running.
    func detach() {
        reattach?.cancel()
        pump?.cancel()
        if let l = attachment {
            cursor = l.cursor
            l.detach()
        }
        attachment = nil
        if case .attached = link, item.attached > 0 { item.attached -= 1 }
        link = .none
        onChange?()
    }

    /// The pane closed: detach, never stop the terminal.
    func shutDown() {
        detach()
        surface.onInput = nil
        surface.onFit = nil
    }

    func refresh() async {
        if let t = try? await service.terminal(id) { item = t }
    }

    #if DEBUG
    /// Debug only: puts the session in a state without a Core, for the demo.
    func debugForce(link: Link, note: ResumeNote?) {
        self.link = link
        self.note = note
        onChange?()
    }
    #endif

    // MARK: typing and size

    private func typed(_ bytes: Data) {
        guard let l = attachment, case .attached(let letterbox) = link else { return }
        if letterbox {
            // The window takes the terminal back: it fills the pane, reports its size, and the Core applies it because
            // this client is now the one that typed (spec §4.4).
            link = .attached(letterbox: false)
            surface.layoutMode(.fill)
            surface.container.layoutSubtreeIfNeeded()
            let s = surface.size
            if s.cols > 0 { l.resize(rows: s.rows, cols: s.cols) }
        }
        l.input(bytes)
    }

    /// The size is sent once it settles: a pane animating open, closed or into a new tile resizes every frame, and each
    /// resize makes the shell redraw its prompt (Powerlevel10k printed one line per frame).
    private var settle: Task<Void, Never>?
    private func fit(_ cols: Int, _ rows: Int) {
        guard cols > 0, rows > 0 else { return }
        settle?.cancel()
        settle = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self, let l = self.attachment, case .attached(false) = self.link else {
                return
            }
            guard (cols, rows) != (self.item.cols, self.item.rows) else { return }
            self.item.cols = cols
            self.item.rows = rows
            l.resize(rows: rows, cols: cols)
        }
    }

    /// Waiting on "Verify to reattach" (the elevation lapsed).
    var waitsForVerify: Bool { link == .stepUp }

    // MARK: actions

    func signal(_ name: String) async -> Bool {
        do {
            try await host.elevated(
                "Send SIG\(name) to the terminal on \(machine). This covers this action only.", done: "sent"
            ) {
                try await self.service.signal(self.id, name)
            }
            host.shell.showToast("Sent SIG\(name) to the terminal on \(machine)")
            return true
        } catch is ElevationDeclined { return false } catch {
            host.shell.showToast(CoreError.unwrapping(error)?.localizedDescription ?? error.localizedDescription)
            return false
        }
    }

    /// Ends the terminal and everything running in it.
    func end() async -> Bool {
        do {
            let t = try await host.elevated(
                "End the terminal on \(machine) and everything running in it.", done: "ended"
            ) {
                try await self.service.close(self.id)
            }
            item = t
            detach()
            host.shell.showToast("The terminal on \(machine) was ended")
            onChange?()
            return true
        } catch is ElevationDeclined { return false } catch {
            host.shell.showToast(CoreError.unwrapping(error)?.localizedDescription ?? error.localizedDescription)
            return false
        }
    }
}
