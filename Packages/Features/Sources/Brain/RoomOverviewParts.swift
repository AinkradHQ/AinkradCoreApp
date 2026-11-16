import CoreUI
import SwiftUI

/// Where the pane is at least this wide the summary and the rules sit side by side (5 to 6); below it they stack.
struct OverviewColumns: Layout {
    static let minWide = Space.s8 * 24
    static let gap = Space.s8 + Space.s4

    private func widths(_ total: CGFloat) -> (CGFloat, CGFloat) {
        let free = total - Self.gap
        return (free * 5 / 11, free * 6 / 11)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let w = proposal.width ?? Self.minWide
        if w >= Self.minWide {
            let (l, r) = widths(w)
            let hl = subviews[0].sizeThatFits(.init(width: l, height: nil)).height
            let hr = subviews[1].sizeThatFits(.init(width: r, height: nil)).height
            return CGSize(width: w, height: max(hl, hr))
        }
        let hl = subviews[0].sizeThatFits(.init(width: w, height: nil)).height
        let hr = subviews[1].sizeThatFits(.init(width: w, height: nil)).height
        return CGSize(width: w, height: hl + Space.s6 + hr)
    }

    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        if b.width >= Self.minWide {
            let (l, r) = widths(b.width)
            subviews[0].place(at: b.origin, anchor: .topLeading, proposal: .init(width: l, height: nil))
            subviews[1].place(
                at: CGPoint(x: b.minX + l + Self.gap, y: b.minY), anchor: .topLeading,
                proposal: .init(width: r, height: nil))
        } else {
            let hl = subviews[0].sizeThatFits(.init(width: b.width, height: nil)).height
            subviews[0].place(at: b.origin, anchor: .topLeading, proposal: .init(width: b.width, height: nil))
            subviews[1].place(
                at: CGPoint(x: b.minX, y: b.minY + hl + Space.s6), anchor: .topLeading,
                proposal: .init(width: b.width, height: nil))
        }
    }
}

/// Two columns that stack when narrow: the left content and the right content, each from the top.
struct Columns<L: View, R: View>: View {
    @ViewBuilder var left: L
    @ViewBuilder var right: R
    init(@ViewBuilder _ left: () -> L, @ViewBuilder right: () -> R) {
        self.left = left()
        self.right = right()
    }
    var body: some View {
        OverviewColumns {
            VStack(alignment: .leading, spacing: Space.s5) { left }.frame(maxWidth: .infinity, alignment: .topLeading)
            VStack(alignment: .leading, spacing: Space.s5) { right }.frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

/// Soft lines where the text will be while it is written; a 0 is a gap between blocks.
struct Placeholder: View {
    let widths: [Double]
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            ForEach(Array(widths.enumerated()), id: \.offset) { _, w in
                if w == 0 {
                    Color.clear.frame(height: Space.s2)
                } else {
                    Color.clear.frame(height: Space.s4).frame(maxWidth: .infinity)
                        .overlay(alignment: .leading) {
                            GeometryReader { g in CoreSkeleton().frame(width: g.size.width * w) }
                        }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Writing")
    }
}

/// The summary: first paragraph, the facts, then the rest.
struct OverviewSummary: View {
    let overview: OverviewBody

    var body: some View {
        let ps = overview.paragraphs
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Summary").coreFont(size: MacTextSize.title, weight: .semibold).accessibilityAddTraits(.isHeader)
            if let first = ps.first { paragraph(first) }
            if !overview.facts.rows.isEmpty {
                Grid(alignment: .topLeading, horizontalSpacing: Space.s4, verticalSpacing: Space.s2) {
                    ForEach(overview.facts.rows, id: \.label) { r in
                        GridRow {
                            Text(r.label).foregroundStyle(GlassInk.secondary)
                                .frame(width: Space.s8 * 3, alignment: .leading)
                            Text(r.value).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .coreFont(size: MacTextSize.body)
            }
            ForEach(Array(ps.dropFirst().enumerated()), id: \.offset) { _, p in paragraph(p) }
        }
    }

    private func paragraph(_ s: String) -> some View {
        Text(s).coreFont(size: MacTextSize.body).fixedSize(horizontal: false, vertical: true)
    }
}

/// The instructions AI sessions read for this room: a draft until approved, then in use. Edit changes the text and Save
/// approves it; Approve takes it as written.
struct InstructionsCard: View {
    let o: RoomOverviewModel
    let room: String
    let overview: OverviewBody
    let approved: Bool
    let text: String
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                Text("Instructions for AI sessions").coreFont(size: MacTextSize.title, weight: .semibold)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Space.s3)
                if approved {
                    StateBadge("In use in this room", tone: .run, symbol: "checkmark")
                } else {
                    BrainChip(
                        "Not in use yet", GlassInk.slate, help: "AI sessions do not read these until you approve them.")
                }
            }
            if o.editing {
                CoreTextArea(
                    nil, placeholder: "Tell AI sessions how to work in this room", text: Bindable(o).draft,
                    minHeight: Space.s8 * 4, focus: $focused
                )
                .task { focused = true }
            } else {
                Text(text).coreFont(size: MacTextSize.body)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            HStack(spacing: Space.s2) {
                Spacer(minLength: Space.s3)
                if o.editing {
                    Button("Cancel") { o.cancelEdit() }.buttonStyle(CoreButtonStyle(.secondary))
                        .keyboardShortcut(.cancelAction)
                    Button("Save") { Task { await o.save(room) } }.buttonStyle(CoreButtonStyle(.prominent))
                        .disabled(!o.canSave)
                } else {
                    Button("Edit") { o.startEdit() }.buttonStyle(CoreButtonStyle(.secondary))
                    if !approved {
                        Button("Approve") { Task { await o.approve(room) } }
                            .buttonStyle(CoreButtonStyle(.prominent)).disabled(o.busy)
                    }
                }
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .coreWell()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("room-instructions")
    }
}

/// Workflow, Code, Design, Never do: each rule on one line with a quiet "from N items".
struct OverviewRulesColumn: View {
    let o: RoomOverviewModel
    let room: String
    let rules: OverviewRules

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            ForEach(rules.groups, id: \.title) { g in
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(g.title).coreFont(size: MacTextSize.headline, weight: .semibold)
                        .foregroundStyle(GlassInk.secondary).accessibilityAddTraits(.isHeader)
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(g.rules) { RuleLine(o: o, room: room, group: g.title, rule: $0, never: g.never) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RuleLine: View {
    let o: RoomOverviewModel
    let room: String
    let group: String
    let rule: OverviewRule
    let never: Bool
    private var key: String { group + "/" + rule.id }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            if never {
                coreShape(Space.s1 / 2).fill(GlassInk.red).frame(width: Space.s1 * 1.5, height: Space.s1 * 1.5)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
                    .accessibilityHidden(true)
            }
            Text(rule.text).coreFont(size: MacTextSize.body).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !rule.sources.isEmpty {
                Button {
                    o.openRule = o.openRule == key ? nil : key
                } label: {
                    Text("from \(BrainWords.plural(rule.sources.count, "item", "items"))")
                        .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
                        .padding(.horizontal, Space.s1).frame(minHeight: MacSize.controlSm)
                }
                .buttonStyle(CoreQuietPressStyle(radius: Radius.chip, scale: 1, hoverFill: true))
                .fixedSize()
                .help("Show the items this rule was read from")
                .popover(
                    isPresented: Binding(
                        get: { o.openRule == key }, set: { if !$0, o.openRule == key { o.openRule = nil } }),
                    arrowEdge: .bottom
                ) { SourcesList(o: o, room: room, rule: rule) }
            }
        }
        .padding(.horizontal, Space.s2).padding(.vertical, Space.s1 * 1.5)
        .modifier(BrainRowHover())
        .padding(.horizontal, -Space.s2)
        .accessibilityElement(children: .contain)
    }
}

/// The items behind one rule: up to four titles and how many more there are.
private struct SourcesList: View {
    let o: RoomOverviewModel
    let room: String
    let rule: OverviewRule
    @State private var items: [OverviewSource]?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Sources · \(BrainWords.plural(rule.sources.count, "item", "items"))")
                .coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(GlassInk.secondary)
            if let items {
                if items.isEmpty {
                    Text("Item titles are not available.").foregroundStyle(GlassInk.secondary)
                }
                ForEach(items.prefix(4)) { s in
                    HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                        Text(s.title).lineLimit(1)
                        Spacer(minLength: Space.s3)
                        Text(s.type).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    }
                }
                if rule.sources.count > 4 {
                    Text("and \(rule.sources.count - 4) more").coreFont(size: MacTextSize.meta)
                        .foregroundStyle(GlassInk.secondary)
                }
            } else {
                ForEach(0..<3, id: \.self) { _ in CoreSkeleton().frame(height: Space.s4) }
            }
        }
        .coreFont(size: MacTextSize.body)
        .padding(Space.s3).frame(width: Space.s8 * 10)
        .task { items = await o.sources(Array(rule.sources.prefix(4)), room: room) }
    }
}
