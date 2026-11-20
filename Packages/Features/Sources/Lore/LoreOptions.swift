import CoreUI
import SwiftUI

/// Settings, Apps, Lore, Options (E2-4): what opens at the start and how big the page text is. Both are read by the app:
/// `LoreModel.show` picks the note to open, and `LoreView` hands the size to the editor.
@MainActor enum LoreOptions {
    static let app = "lore"
    static var options: AppOptions { .shared(app) }
    static let openLast = "openLast"
    static let textSize = "textSize"
    /// The id of the last note opened by hand; empty while the last page was a day.
    static let lastNote = "lastNote"

    /// The text size choices: the factor on the page's writing sizes.
    static let sizes: [(id: String, title: String, scale: CGFloat)] = [
        ("small", "Small", 0.9), ("medium", "Medium", 1), ("large", "Large", 1.15),
    ]

    static func scale(_ id: String) -> CGFloat { sizes.first { $0.id == id }?.scale ?? 1 }

    /// The note to open when the space opens: the last one when it is kept and set, else today's (nil).
    static func noteAtStart(openLast: Bool, last: String) -> String? {
        openLast && !last.isEmpty ? last : nil
    }
}

struct LoreWritingSection: View {
    @Environment(\.coreAccent) private var paneAccent
    let options = LoreOptions.options

    var body: some View {
        GlassSection("Writing", symbol: "text.alignleft", hue: GlassInk.accent(paneAccent)) {
            VStack(spacing: Space.s2) {
                OptionSwitchRow(
                    "Open last note at start", sub: "Otherwise Lore opens today's note",
                    symbol: "clock.arrow.circlepath",
                    isOn: options.flag(LoreOptions.openLast, true))
                OptionSelectRow(
                    "Text size", symbol: "textformat.size", selection: options.text(LoreOptions.textSize, "medium"),
                    options: LoreOptions.sizes.map { CoreSelectOption($0.id, $0.title) })
            }
        }
        .foregroundStyle(GlassInk.primary)
    }
}
