import CoreUI
import SwiftUI

// Shared pieces of the focused pages (details v2): a list left at 340 pt with the selected row marked, the detail in a plain
// well on the right, and the small blocks the detail is made of. Each page is one Island whose title row carries its tools.

/// 340 pt list left, plain well right. The detail crossfades when `key` changes (its row is picked).
struct PgSplit<List: View, Detail: View>: View {
    let key: AnyHashable
    @ViewBuilder var list: List
    @ViewBuilder var detail: Detail

    static var listWidth: CGFloat { 340 }

    var body: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s1) { list }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: Self.listWidth)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) { detail }.id(key).transition(.opacity).padding(Space.s4)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .coreCard(GlassInk.well, radius: Radius.cardMac)
            .animation(Motion.out(Motion.ui), value: key)
        }
        .frame(maxHeight: .infinity)
    }
}

/// A group title in a list: "Today", "Yesterday".
struct PgGroup: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title).coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(GlassInk.secondary)
            .padding(.top, Space.s3).padding(.bottom, Space.s1).padding(.horizontal, Space.s3)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The detail's head: a quiet line over the title, the tools on the right.
struct PgHead<Tools: View>: View {
    let kicker: String
    let title: String
    @ViewBuilder var tools: Tools
    var body: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(kicker).foregroundStyle(GlassInk.secondary).lineLimit(1)
                Text(title).coreFont(size: MacTextSize.title, weight: .semibold).lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            tools
        }
        .padding(.bottom, Space.s4)
    }
}

/// A block of the detail or of Settings: a small title (and tools), then its content.
struct PgBlock<Tools: View, Content: View>: View {
    let title: String
    @ViewBuilder var tools: Tools
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Text(title).coreFont(size: MacTextSize.body, weight: .semibold).foregroundStyle(GlassInk.secondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                tools
            }
            content
        }
        .padding(.top, Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension PgBlock where Tools == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, tools: { EmptyView() }, content: content)
    }
}

/// Label and value pairs, two columns.
struct PgFacts: View {
    let rows: [(String, String)]
    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.s4, verticalSpacing: Space.s2) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                GridRow {
                    Text(r.0).foregroundStyle(GlassInk.secondary).gridColumnAlignment(.leading)
                    Text(r.1).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.bottom, Space.s2)
    }
}

/// A quiet line: what is missing and when it will be there.
struct PgQuiet: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

/// A calm area chart with the latest value over it: no axes, the words say the rest.
struct PgChart: View {
    let title: String
    let values: [Double]
    let latest: String
    var tint: Color = GlassInk.blue
    var floor = 1.0
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text(title).foregroundStyle(GlassInk.secondary)
                Spacer(minLength: 0)
                Text(latest).monospacedDigit()
            }
            let points = Sparkline.normalized(values, floor: floor)
            Canvas { ctx, size in
                guard points.count > 1 else { return }
                let step = size.width / CGFloat(points.count - 1)
                func at(_ i: Int) -> CGPoint {
                    CGPoint(x: CGFloat(i) * step, y: size.height - 1 - CGFloat(points[i]) * (size.height - 2))
                }
                var line = Path()
                line.move(to: at(0))
                for i in 1..<points.count { line.addLine(to: at(i)) }
                var area = line
                area.addLine(to: CGPoint(x: size.width, y: size.height))
                area.addLine(to: CGPoint(x: 0, y: size.height))
                area.closeSubpath()
                ctx.fill(area, with: .color(tint.opacity(0.16)))
                ctx.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
            .frame(height: Space.s8 * 2)
            .overlay {
                if points.count < 2 { Text("No readings yet").foregroundStyle(GlassInk.secondary) }
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity)
        .coreCard(GlassInk.well, radius: Radius.row)
        .accessibilityElement(children: .combine)
    }
}
