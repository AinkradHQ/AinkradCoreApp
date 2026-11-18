// QuickCapture — plan R6-05. A global shortcut opens a small glass panel over any app. Return adds the text to today's
// note under a time stamp (a T2 save from the head's rev: the Core merges if the note moved on); ⌘Return opens the
// advanced line, where Return makes a new note in a chosen project. Esc closes. Text that could not be sent comes back
// into the panel with the reason, never dropped.
//
// The global key is held only while Ainkrad is in the background: inside the app ⇧⌘N is a menu command, so a custom
// shortcut (or the ⌥⌘N fallback) never takes a key from the app's own panes.
import AppKit
import CoreKit
import CoreUI
import Observation
import Shell
import SwiftUI

@MainActor @Observable
public final class QuickCapture {
    /// Where the global key stands. `fallback`: the chosen one was taken, so ⌥⌘N is used. `taken`: neither could be had.
    enum Hold: Equatable { case chosen, fallback, taken }

    @ObservationIgnored unowned let lore: LoreModel
    var text = ""
    /// ⌘Return: a new note in `project` instead of today's note.
    var advanced = false
    /// The project id as text; "" = personal.
    var project = ""
    var error: String?
    private(set) var shown = false
    var shortcut: CaptureShortcut { didSet { if shortcut != oldValue { save() } } }
    private(set) var hold = Hold.chosen
    /// Counts opens, so the view focuses its field on each one.
    private(set) var opens = 0

    @ObservationIgnored var now: () -> Date = { Date() }
    /// Shows or hides the panel. Tests replace it.
    @ObservationIgnored var present: (Bool) -> Void = { _ in }
    @ObservationIgnored private var panel: CapturePanel?
    @ObservationIgnored private var hotKey: GlobalHotKey?
    @ObservationIgnored private var escape: Int?
    @ObservationIgnored private var tokens: [NSObjectProtocol] = []
    @ObservationIgnored private let defaults: UserDefaults
    static let shortcutKey = "lore.capture.shortcut"
    static let saidKey = "lore.capture.fallbackSaid"

    init(lore: LoreModel, defaults: UserDefaults = .standard) {
        self.lore = lore
        self.defaults = defaults
        shortcut =
            defaults.data(forKey: Self.shortcutKey).flatMap {
                try? JSONDecoder().decode(CaptureShortcut.self, from: $0)
            }
            ?? .standard
    }

    // MARK: the global key

    /// The app's real wiring: the panel, the hot key, and holding the key only while the app is in the background.
    func start() {
        let panel = CapturePanel(model: self)
        self.panel = panel
        present = { [weak panel] on in on ? panel?.show() : panel?.orderOut(nil) }
        hotKey = GlobalHotKey { [weak self] in self?.toggle() }
        let center = NotificationCenter.default
        tokens = [
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.arm() }
            },
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.hotKey?.unregister() }
            },
        ]
        // Try now, so a taken shortcut is found (and said) at launch, then let go while the app is in front.
        arm()
        if NSApp?.isActive == true { hotKey?.unregister() }
    }

    private func arm() {
        guard let hotKey else { return }
        if hotKey.register(shortcut) {
            hold = .chosen
        } else if shortcut != .fallback, hotKey.register(.fallback) {
            hold = .fallback
            // Said once, ever: the Lore settings keep saying it.
            if !defaults.bool(forKey: Self.saidKey) {
                defaults.set(true, forKey: Self.saidKey)
                lore.host.shell.showToast(
                    "\(shortcut.keys) is taken by another app, so \(CaptureShortcut.fallback.keys) opens quick capture.",
                    kind: .info)
            }
        } else {
            hold = .taken
        }
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(shortcut), forKey: Self.shortcutKey)
        defaults.set(false, forKey: Self.saidKey)
        guard hotKey != nil else { return }
        arm()
        if NSApp?.isActive == true { hotKey?.unregister() }
    }

    // MARK: the panel

    public func toggle() { shown ? close() : open() }

    func open() {
        if NSApp?.isHidden == true { NSApp.unhideWithoutActivation() }
        shown = true
        opens += 1
        if escape == nil {
            escape = CoreEscape.shared.push { [weak self] in
                guard let self, self.shown else { return false }
                self.close()
                return true
            }
        }
        present(true)
    }

    /// Esc, a click elsewhere, or a send. What was typed stays for the next open until it is sent.
    func close() {
        guard shown else { return }
        shown = false
        if let escape { CoreEscape.shared.remove(escape) }
        escape = nil
        present(false)
    }

    func toggleAdvanced() {
        advanced.toggle()
        error = nil
    }

    var stamp: String { now().formatted(date: .omitted, time: .shortened) }

    var projects: [CoreSelectOption<String>] {
        [CoreSelectOption("", "Personal", symbol: "person")]
            + lore.projectNames.sorted { $0.value.localizedStandardCompare($1.value) == .orderedAscending }
            .map { CoreSelectOption($0.key, $0.value, symbol: "folder") }
    }

    // MARK: send

    /// Return. Closes at once and sends in the background; a failure reopens the panel with the text and why.
    func submit() async {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        guard let service = lore.service else {
            error = "Not connected to your Core. Your text stays here."
            return
        }
        let newNote = advanced
        let project = project.isEmpty ? nil : project
        let stamp = stamp
        text = ""
        advanced = false
        error = nil
        close()
        do {
            if newNote {
                _ = try await service.create(text: body + "\n", project: project)
            } else {
                let day = try await service.today(LoreModel.key(now()))
                _ = try await service.save(day.id, baseRev: day.rev, text: Self.appended(day.text, body, stamp: stamp))
            }
            if NSApp?.isActive == true {
                lore.host.shell.showToast(newNote ? "Note created" : "Added to today's note", kind: .ok)
            }
        } catch {
            text = text.isEmpty ? body : body + "\n" + text
            advanced = newNote
            self.error = "Unable to save: \(lore.words(error)) Your text is still here."
            open()
        }
    }

    /// Today's text with `body` added under a `### <time>` heading, a blank line before it.
    static func appended(_ note: String, _ body: String, stamp: String) -> String {
        var head = note
        while head.hasSuffix("\n") { head.removeLast() }
        return (head.isEmpty ? "" : head + "\n\n") + "### \(stamp)\n\n\(body)\n"
    }
}

/// A typing-only panel over any app: it takes the keyboard without bringing Ainkrad to the front, joins every Space
/// (full-screen apps too), and closes when it loses the keyboard.
@MainActor final class CapturePanel: NSPanel {
    /// The card (480, a sheet width) plus room for the frame's shadow, and below it room for the project menu.
    static let size = CGSize(width: Space.s8 * 15 + Space.s6 * 2, height: Space.s8 * 14)
    private weak var model: QuickCapture?

    init(model: QuickCapture) {
        self.model = model
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isReleasedWhenClosed = false
        let host = NSHostingView(rootView: QuickCaptureView(model: model))
        host.sizingOptions = []
        contentView = host
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: self, queue: .main
        ) { [weak model] _ in MainActor.assumeIsolated { model?.close() } }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func show() {
        // A quarter down the screen the pointer is on, centred. Not animated: it opens many times a day.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let f = screen?.visibleFrame {
            setFrameOrigin(NSPoint(x: f.midX - Self.size.width / 2, y: f.maxY - f.height / 4 - Self.size.height))
        }
        makeKeyAndOrderFront(nil)
        // The field takes the keyboard at once (a typing-only window).
        DispatchQueue.main.async { [weak self] in
            guard let self, let tv = Self.textView(in: self.contentView) else { return }
            self.makeFirstResponder(tv)
        }
    }

    private static func textView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let tv = view as? NSTextView, tv.isEditable { return tv }
        for v in view.subviews { if let tv = textView(in: v) { return tv } }
        return nil
    }

    /// Return sends (⇧/⌥Return add a line), ⌘Return opens or closes the advanced line. Input-method text keeps Return.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 36 || event.keyCode == 76, let model,
            !((firstResponder as? NSTextView)?.hasMarkedText() ?? false)
        {
            let f = event.modifierFlags.intersection([.command, .shift, .option, .control])
            if f == .command {
                model.toggleAdvanced()
                return
            }
            if f.isEmpty {
                Task { await model.submit() }
                return
            }
        }
        super.sendEvent(event)
    }
}
