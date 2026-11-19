import AppKit
import CoreUI
import SwiftUI

/// Settings, Apps, Terminal, Options (E2-4): the three plain choices of the mockup. Text size and Cursor drive the same
/// `TerminalPrefs` the Look tab edits (font size and cursor shape), so the terminals change at once. "Ring the bell" plays a
/// soft sound when a terminal rings its bell.
@MainActor enum TerminalOptions {
    static var options: AppOptions { .shared("terminal") }
    static let bell = "bell"

    enum Size: String, CaseIterable {
        case small, medium, large
        var title: String { rawValue.capitalized }
        /// The font size in points a choice sets.
        var points: Double {
            switch self {
            case .small: 10
            case .medium: 12
            case .large: 15
            }
        }
        /// The nearest choice for any size the Look tab's slider left.
        init(points: Double) { self = points <= 11 ? .small : points <= 13 ? .medium : .large }
    }

    enum Cursor: String, CaseIterable {
        case block, line
        var title: String { rawValue.capitalized }
        var shape: TerminalPrefs.CursorShape { self == .block ? .block : .bar }
        /// The underline counts as a line.
        init(_ shape: TerminalPrefs.CursorShape) { self = shape == .block ? .block : .line }
    }

    /// The sound of a bell, when Ring the bell is on.
    @MainActor static func ring(on: Bool = options.bool(bell, false)) {
        guard on else { return }
        NSSound(named: "Tink")?.play()
    }
}

/// The group at the top of Terminal, Options.
struct TerminalBasicsSection: View {
    @Environment(\.coreAccent) private var paneAccent
    @Bindable var prefs: TerminalPrefs
    let options = TerminalOptions.options

    var body: some View {
        GlassSection("Basics", sub: "Size, cursor and sound", symbol: "terminal", hue: GlassInk.accent(paneAccent), index: 4) {
            VStack(spacing: Space.s2) {
                OptionSelectRow(
                    "Text size", symbol: "textformat.size",
                    selection: Binding(
                        get: { TerminalOptions.Size(points: prefs.fontSize).rawValue },
                        set: { prefs.fontSize = (TerminalOptions.Size(rawValue: $0) ?? .medium).points }),
                    options: TerminalOptions.Size.allCases.map { CoreSelectOption($0.rawValue, $0.title) })
                OptionSegmentRow(
                    "Cursor", symbol: "cursorarrow.rays",
                    selection: Binding(
                        get: { TerminalOptions.Cursor(prefs.cursor).rawValue },
                        set: { prefs.cursor = (TerminalOptions.Cursor(rawValue: $0) ?? .block).shape }),
                    segments: TerminalOptions.Cursor.allCases.map { CoreSegment($0.rawValue, $0.title) })
                OptionSwitchRow(
                    "Ring the bell", sub: "A soft sound when a terminal rings its bell", symbol: "bell",
                    isOn: options.flag(TerminalOptions.bell, false))
            }
        }
        .foregroundStyle(GlassInk.primary)
    }
}
