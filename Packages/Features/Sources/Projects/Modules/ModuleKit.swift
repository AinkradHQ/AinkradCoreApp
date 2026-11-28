import CoreUI
import SwiftUI

/// The shared frame of a focused page (details v2): one island with a title row (the title and its tools), then either one
/// body or a split, a grouped list (340 pt) on the left and the picked item in a plain well on the right.
struct ModulePage<Tools: View, Body: View>: View {
    let title: String
    var sub: String?
    @ViewBuilder let tools: Tools
    @ViewBuilder let content: Body
    @Environment(\.spaceSettled) private var settled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s2) {
                Text(title).coreFont(size: MacTextSize.title + 2, weight: .semibold).lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                if let sub { Text(sub).foregroundStyle(GlassInk.secondary).lineLimit(1) }
                Spacer(minLength: Space.s2)
                tools
            }
            .frame(height: ModuleMetric.head).padding(.leading, Space.s5).padding(.trailing, Space.s3)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .coreWell(radius: Radius.pane)
        .coreRise(settled, 0)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project-page-\(title)")
    }
}

/// The split under a title row: the list, and the picked item's detail in a plain well that cross-fades as the pick changes.
struct ModuleSplit<ListContent: View, Detail: View>: View {
    var pickID: String?
    @ViewBuilder let list: ListContent
    @ViewBuilder let detail: Detail

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            list.frame(width: ModuleMetric.list).padding(.leading, Space.s5)
                .padding(.trailing, Space.s3).padding(.bottom, Space.s3)
            ScrollView {
                detail.padding(.horizontal, Space.s5).padding(.vertical, Space.s4 + 2)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .id(pickID).transition(.opacity)
            }
            .animation(Motion.out(Motion.ui), value: pickID)
            .coreCard(GlassInk.well, radius: Radius.cardMac)
            .padding(.horizontal, Space.s2).padding(.bottom, Space.s2)
        }
        .frame(maxHeight: .infinity)
    }
}

enum ModuleMetric {
    static let list: CGFloat = 340
    static let head: CGFloat = 56
}

/// Moving the pick with the arrow keys, over what the list shows.
enum ModuleNav {
    /// The id `by` steps from `current` (clamped to the ends); the first id when nothing is picked.
    static func step(_ ids: [String], from current: String?, by n: Int) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let current, let i = ids.firstIndex(of: current) else { return ids.first }
        return ids[min(max(i + n, 0), ids.count - 1)]
    }

    /// The pick if it is still in the list, else the first row.
    static func effective(_ pick: String?, in ids: [String]) -> String? {
        pick.flatMap { ids.contains($0) ? $0 : nil } ?? ids.first
    }
}

/// The scrolling list of a split: the arrow keys move the pick and Return opens it. No focus ring; the filled row is the mark.
struct ModuleList<Rows: View>: View {
    let ids: [String]
    @Binding var pick: String?
    var onOpen: () -> Void = {}
    @ViewBuilder let rows: Rows

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s1) { rows }
                    .animation(Motion.out(Motion.ui), value: ids)
            }
            .focusable().focusEffectDisabled()
            .onKeyPress(.downArrow) { move(1) }
            .onKeyPress(.upArrow) { move(-1) }
            .onKeyPress(.return) {
                onOpen()
                return .handled
            }
            .onChange(of: pick) { _, id in if let id { withAnimation(Motion.out(Motion.ui)) { proxy.scrollTo(id) } } }
        }
    }

    private func move(_ n: Int) -> KeyPress.Result {
        pick = ModuleNav.step(ids, from: ModuleNav.effective(pick, in: ids), by: n)
        return .handled
    }
}

/// A group title in a list ("Needs you", "Today").
struct ModuleGroup: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title).coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(GlassInk.secondary)
            .padding(.top, Space.s3).padding(.leading, Space.s3).frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A list row: title, one line under it and a state square at the end; the picked one carries the fill.
struct ModuleRow<Trailing: View>: View {
    let id: String
    let title: String
    var sub: String?
    var symbol: String?
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let trailing: Trailing

    var body: some View {
        CoreRow(title, subtitle: sub, symbol: symbol, selected: selected, action: action) { trailing }
            .id(id)
            .transition(.opacity)
    }
}

/// The small rounded square that says a state (never a circle).
struct ModuleDot: View {
    let tone: Tone
    @Environment(\.corePalette) private var palette
    var body: some View {
        coreShape(2).fill(palette.tone(tone).ink).frame(width: 8, height: 8).accessibilityHidden(true)
    }
}

/// The detail's head: a quiet caption, the title and the actions at the end.
struct ModuleHead<Actions: View>: View {
    let caption: String
    let title: String
    @ViewBuilder let actions: Actions
    var body: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(caption).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
                Text(title).coreFont(size: MacTextSize.large, weight: .semibold)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s2)
            actions
        }
        .padding(.bottom, Space.s4 - 2)
    }
}

/// Label and value pairs under a head.
struct ModuleFacts: View {
    let facts: [(String, String)]
    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.s4, verticalSpacing: Space.s2) {
            ForEach(Array(facts.enumerated()), id: \.offset) { _, f in
                GridRow {
                    Text(f.0).foregroundStyle(GlassInk.secondary).gridColumnAlignment(.leading)
                    Text(f.1).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.bottom, Space.s4)
    }
}

/// A titled block of a detail.
struct ModuleSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title).coreFont(size: MacTextSize.meta + 1, weight: .semibold).foregroundStyle(GlassInk.secondary)
            content
        }
        .padding(.top, Space.s4).frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A quiet empty or error state that fills a well: a symbol, a title and one line.
struct ModuleQuiet<Actions: View>: View {
    let symbol: String
    let title: String
    let line: String
    @ViewBuilder let actions: Actions
    var body: some View {
        VStack(spacing: Space.s2) {
            Image(systemName: symbol).coreFont(size: MacTextSize.large).foregroundStyle(GlassInk.secondary)
                .accessibilityHidden(true)
            Text(title).coreFont(size: MacTextSize.title, weight: .semibold)
            Text(line).foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            actions.padding(.top, Space.s1)
        }
        .frame(maxWidth: Space.s8 * 11).padding(Space.s6).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension ModuleQuiet where Actions == EmptyView {
    init(symbol: String, title: String, line: String) {
        self.init(symbol: symbol, title: title, line: line) { EmptyView() }
    }
}

/// The search box of a title row.
struct ModuleSearch: View {
    let placeholder: String
    @Binding var text: String
    var body: some View {
        CoreTextField("", placeholder: placeholder, text: $text).frame(width: Space.s8 * 6)
            .accessibilityLabel(placeholder)
    }
}

/// The plain well of a page that has no list: the body under the title row.
struct ModuleWell<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .coreCard(GlassInk.well, radius: Radius.cardMac)
            .padding(.horizontal, Space.s2).padding(.bottom, Space.s2)
    }
}
