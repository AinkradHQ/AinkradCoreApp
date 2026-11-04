import SwiftUI

/// A small area chart of a series drawn from samples the app took itself. Fewer than two samples draws nothing: a chart never
/// shows a line the data does not support. `rawValue` scales to the series' own maximum unless `ceiling` is given.
public struct CoreSpark: View {
    let values: [Double]
    let tone: Tone
    let ceiling: Double?
    @Environment(\.corePalette) private var palette

    public init(_ values: [Double], tone: Tone = .run, ceiling: Double? = nil) {
        self.values = values
        self.tone = tone
        self.ceiling = ceiling
    }

    public var body: some View {
        let ink = tone == .run ? palette.primary : palette.tone(tone).ink
        Canvas { ctx, size in
            guard values.count >= 2 else { return }
            let top = max(ceiling ?? (values.max() ?? 1), 0.000_001)
            let step = size.width / CGFloat(values.count - 1)
            func point(_ i: Int) -> CGPoint {
                CGPoint(
                    x: CGFloat(i) * step,
                    y: size.height - CGFloat(min(1, max(0, values[i] / top))) * (size.height - 2) - 1)
            }
            var line = Path()
            line.move(to: point(0))
            for i in 1..<values.count { line.addLine(to: point(i)) }
            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()
            ctx.fill(area, with: .color(ink.opacity(0.18)))
            ctx.stroke(line, with: .color(ink), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .frame(height: Space.s6 + Space.s2)
        .accessibilityHidden(true)
    }
}

/// Equal cells 0...1, oldest first: how much happened in each slice of time. The strip is a picture; put the numbers in words
/// beside it.
public struct CoreHeat: View {
    let values: [Double]
    @Environment(\.corePalette) private var palette

    public init(_ values: [Double]) { self.values = values }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                coreShape(1).fill(v <= 0 ? palette.track : palette.primary.opacity(0.25 + 0.75 * min(1, v)))
                    .frame(width: Space.s1, height: Space.s3)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Buckets timestamps into `count` slices ending at `now`, `slice` seconds each, scaled 0...1 by the busiest slice. Pure so a
/// test can pin it.
public func heatBuckets(_ times: [Date], now: Date, slice: TimeInterval, count: Int) -> [Double] {
    guard count > 0, slice > 0 else { return [] }
    var cells = [Double](repeating: 0, count: count)
    for t in times {
        let ago = now.timeIntervalSince(t)
        guard ago >= 0 else { continue }
        let i = count - 1 - Int(ago / slice)
        if i >= 0 && i < count { cells[i] += 1 }
    }
    let top = cells.max() ?? 0
    return top > 0 ? cells.map { $0 / top } : cells
}

/// Filled squares for "n of capacity" (work slots, attachments). The number always sits beside it.
public struct CoreSlots: View {
    let used: Int
    let capacity: Int
    @Environment(\.corePalette) private var palette

    public init(used: Int, capacity: Int) {
        self.used = used
        self.capacity = capacity
    }

    public var body: some View {
        HStack(spacing: Space.s1 / 2) {
            ForEach(0..<max(1, min(capacity, 16)), id: \.self) { i in
                coreShape(Space.s1 / 2).fill(i < used ? palette.primary : palette.track)
                    .frame(width: Space.s2, height: Space.s2)
            }
        }
        .accessibilityHidden(true)
    }
}
