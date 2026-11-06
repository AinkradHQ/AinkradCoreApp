import AppKit
import CoreUI
import SwiftUI

/// The few fixed dark colours of the terminal screens, named once.
enum TerminalInk {
    /// Under the card laid over a terminal that shows no screen: deep blue at half strength, the same in night and day.
    static let veil = Color(red: 6 / 255, green: 12 / 255, blue: 24 / 255).opacity(0.5)
    /// Around a screen smaller than its pane (another device sized it).
    static let letterbox = NSColor(red: 2 / 255, green: 6 / 255, blue: 12 / 255, alpha: 0.92)
    /// The terminal's base for the solid look, before its opacity.
    static let solid = (red: 0.05, green: 0.06, blue: 0.09)
}

/// A CoreUI notice with the optional action button and a busy bar under it. The title says the state; the tone backs it up.
struct TermBanner: View {
    let tone: Tone
    let title: String
    let detail: String
    var busy = false
    var symbol: String?
    var help = ""
    var actionTitle: String?
    var action: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            CoreNotice(symbol: symbol ?? Self.symbol(tone), title: title, text: detail, tone: tone) {
                if let actionTitle {
                    Button(actionTitle, action: action).buttonStyle(CoreButtonStyle(.secondary, size: .small))
                }
            }
            if busy { BusyBar().padding(.horizontal, Space.s3).padding(.vertical, Space.s2) }
        }
        .help(help)
        .accessibilityAddTraits(busy ? .updatesFrequently : [])
    }

    static func symbol(_ tone: Tone) -> String {
        switch tone {
        case .run: "checkmark.square"
        case .done: "info.square"
        case .warn: "exclamationmark.triangle"
        case .fail: "xmark.octagon"
        case .queue: "square.dashed"
        }
    }
}

/// A moving bar for "working, length unknown". Reduce Motion: the bar rests in the middle.
struct BusyBar: View {
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        TimelineView(.animation(paused: reduce)) { context in
            let t = context.date.timeIntervalSinceReferenceDate / (Motion.tick * 1.5)
            let phase = reduce ? 0.5 : t - t.rounded(.down)
            GeometryReader { geo in
                let seg = geo.size.width * 0.3
                ZStack(alignment: .leading) {
                    coreShape(Space.s1 / 2).fill(palette.track)
                    coreShape(Space.s1 / 2).fill(palette.primary).frame(width: seg)
                        .offset(x: (geo.size.width - seg) * phase)  // grid: ok progress motion, not layout
                }
                .clipShape(coreShape(Space.s1 / 2))
            }
        }
        .frame(height: Space.s1)
        .accessibilityHidden(true)
    }
}

/// The card over a terminal that is not showing a screen: a title, what it means, the actions.
struct TermCard: View {
    let title: String
    let text: String
    var note: String?
    var actions: [(title: String, primary: Bool, run: @MainActor () -> Void)]

    /// The card's picture and colour, from what it says.
    private var look: (symbol: String, hue: Color) {
        let t = title.lowercased()
        if t.contains("verify") || t.contains("touch id") { return ("touchid", GlassInk.blue) }
        if t.contains("still running") || t.contains("detached") { return ("play.fill", GlassInk.blue) }
        if t.contains("exited") || t.contains("ended") || t.contains("gone") { return ("stop.fill", GlassInk.slate) }
        if t.contains("lost") || t.contains("offline") || t.contains("can't") || t.contains("not") {
            return ("wifi.exclamationmark", GlassInk.orange)
        }
        return ("terminal", GlassInk.blue)
    }

    var body: some View {
        ModalCard(
            title: title, message: text, note: note, symbol: look.symbol, hue: look.hue,
            choices: actions.map { a in
                (
                    ConfirmChoice(
                        a.title,
                        symbol: a.primary ? (look.symbol == "touchid" ? "touchid" : "arrow.right.square") : "xmark"
                    ) { a.run() },
                    a.primary
                )
            })
    }
}

/// The inline outcome of a Touch ID that did not elevate.
struct ElevationBanner: View {
    let notice: ElevationNotice
    var body: some View {
        TermBanner(tone: notice.tone, title: notice.title, detail: notice.detail, symbol: notice.symbol)
            .accessibilityIdentifier("stepup-notice")
    }
}

/// One time format for the whole app: "just now", "5 min ago", "2 h ago", "3 d ago" (the same words as the Agents list).
func ago(_ date: Date?, now: Date = Date()) -> String {
    guard let date else { return "just now" }
    let m = Int(now.timeIntervalSince(date) / 60)
    if m < 1 { return "just now" }
    if m < 60 { return "\(m) min ago" }
    if m < 1440 { return "\(m / 60) h ago" }
    return "\(m / 1440) d ago"
}
