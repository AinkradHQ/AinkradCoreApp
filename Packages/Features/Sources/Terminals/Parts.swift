import CoreUI
import SwiftUI

/// A CoreUI notice with the optional action button and a busy bar under it. The title says the state; the tone backs it up.
struct TermBanner: View {
    let tone: Tone
    let title: String
    let detail: String
    var busy = false
    var symbol: String?
    var actionTitle: String?
    var action: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            CoreNotice(symbol: symbol ?? Self.symbol(tone), title: title, text: detail, tone: tone) {
                if let actionTitle {
                    Button(actionTitle, action: action).buttonStyle(CoreButtonStyle(.secondary, size: .small))
                }
            }
            if busy { CoreBusyBar().padding(.horizontal, Space.s3).padding(.vertical, Space.s2) }
        }
        .accessibilityAddTraits(busy ? .updatesFrequently : [])
    }

    static func symbol(_ tone: Tone) -> String {
        switch tone {
        case .run: "checkmark.circle"
        case .done: "info.circle"
        case .warn: "exclamationmark.triangle"
        case .fail: "xmark.octagon"
        case .queue: "circle.dashed"
        }
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
        if t.contains("still running") || t.contains("detached") { return ("play.circle", GlassInk.green) }
        if t.contains("exited") || t.contains("ended") || t.contains("gone") { return ("stop.circle", GlassInk.slate) }
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
                        symbol: a.primary ? (look.symbol == "touchid" ? "touchid" : "arrow.right.circle") : "xmark"
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

func ago(_ date: Date?, now: Date = Date()) -> String {
    guard let date else { return "just now" }
    let m = Int(now.timeIntervalSince(date) / 60)
    if m < 1 { return "just now" }
    if m < 60 { return "\(m) min" }
    if m < 1440 { return "\(m / 60) h" }
    return "\(m / 1440) d"
}
