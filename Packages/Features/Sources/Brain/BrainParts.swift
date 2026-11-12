import CoreUI
import SwiftUI

/// A small tag on the CoreUI state tones (no hand-mixed tint): blue informs, green and red are real status, amber is
/// "needs you", slate is quiet. Same height, radius and type as `StateBadge`, without the symbol a tag does not need.
struct BrainChip: View {
    let text: String
    let hue: Color
    var help: String?
    @Environment(\.corePalette) private var palette
    init(_ text: String, _ hue: Color, help: String? = nil) {
        self.text = text
        self.hue = hue
        self.help = help
    }
    private var tone: Tone {
        hue == GlassInk.green
            ? .done
            : hue == GlassInk.red
                ? .fail
                : hue == GlassInk.amber
                    ? .warn
                    : hue == GlassInk.blue ? .run : .queue
    }
    var body: some View {
        let c = palette.tone(tone)
        Text(text).coreFont(size: MacTextSize.meta, weight: .medium).lineLimit(1)
            .foregroundStyle(c.ink)
            .padding(.horizontal, Space.s2).frame(minHeight: MacSize.chip)
            .background(c.fill, in: coreShape(Radius.chip))
            // A tag keeps its whole word: its neighbours shrink first (same rule as StateBadge and CoreChip).
            .fixedSize().layoutPriority(2)
            .help(help ?? text)
    }
}

/// The chips every Brain screen shows for a room: its mode, provider policy and, for employer and client rooms, who it is for.
struct RoomChips: View {
    let room: RoomSummary
    var body: some View {
        ChipFlow(spacing: Space.s2) {
            BrainChip(room.mode.label, GlassInk.slate, help: room.mode.story)
            BrainChip(
                room.provider.label, room.provider == .approvedCloud ? GlassInk.blue : GlassInk.slate,
                help: room.provider.help)
            if let k = room.kind.chipLabel {
                BrainChip(k, GlassInk.blue, help: "\(k) room: kept apart from every other.")
            }
        }
    }
}

/// A titled inner card: a plain well, never a glass frame (the frame is for outer surfaces).
struct BrainCard<Content: View>: View {
    let title: String?
    let sub: String?
    @ViewBuilder var content: Content
    init(_ title: String? = nil, sub: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.sub = sub
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if let title {
                Text(title).coreFont(size: MacTextSize.headline, weight: .semibold)
                    .accessibilityAddTraits(.isHeader)
            }
            if let sub {
                Text(sub).coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .coreWell()
    }
}

/// A bar that fills to a fraction: the CoreUI meter, amber when the hue says it is running out.
struct BrainBar: View {
    let fraction: Double
    var hue: Color = GlassInk.blue
    var height: CGFloat = 6
    var body: some View {
        CoreMeter(fraction, low: hue == GlassInk.amber || hue == GlassInk.red, height: height, label: "")
            .accessibilityHidden(true)
    }
}

/// A full-width state (empty, offline, unavailable, error): the one CoreUI state card, centred, with the way back on the
/// left and the one next step on the right. A failed load has only "Try again": a Cancel there does nothing.
struct BrainStateCard: View {
    let symbol: String
    let title: String
    let text: String
    var secondary: CoreAction?
    var primary: CoreAction?
    var body: some View {
        CoreStateCard(symbol: symbol, title: title, line: text, secondary: secondary, primary: primary)
            .frame(maxWidth: .infinity, minHeight: Space.s8 * 7)
            // Centred in the pane instead of a card with an empty band under it.
            .containerRelativeFrame(.vertical, alignment: .center) { h, _ in max(h * 0.7, Space.s8 * 7) }
    }
}

/// What a screen looks like while it loads: soft blocks in the shape of the content that is coming.
struct BrainSkeleton: View {
    enum Shape { case page, list }
    let shape: Shape
    private let card = coreShape(Radius.cardMac)
    var body: some View {
        VStack(spacing: Space.s3) {
            switch shape {
            case .page:
                CoreSkeleton(card).frame(height: Space.s8 * 2)
                HStack(spacing: Space.s3) {
                    ForEach(0..<4, id: \.self) { _ in CoreSkeleton(card).frame(height: Space.s8 * 3) }
                }
                HStack(spacing: Space.s3) {
                    ForEach(0..<2, id: \.self) { _ in CoreSkeleton(card).frame(height: Space.s8 * 5) }
                }
            case .list:
                ForEach(0..<4, id: \.self) { _ in CoreSkeleton(card).frame(height: Space.s8 * 2) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

/// A section title in sentence case.
struct BrainTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).coreFont(size: MacTextSize.title, weight: .semibold).accessibilityAddTraits(.isHeader)
    }
}

/// The condition notices every tab shows (offline, index rebuilding, embeddings down), one plain sentence each.
struct BrainConditions: View {
    let model: BrainModel
    var body: some View {
        if let f = model.overview?.flags {
            VStack(spacing: Space.s2) {
                if let q = f.offlineQueued {
                    CoreNotice(
                        symbol: "wifi.slash", title: "Offline, \(q) queued",
                        text: "This Mac's own Core answers. Changes wait and go when the remote Core is reachable.")
                }
                if f.indexRebuilding {
                    CoreNotice(
                        symbol: "arrow.triangle.2.circlepath", title: "The search index is rebuilding",
                        text: "Results can be incomplete until it finishes. Nothing is lost.", tone: .warn)
                }
                if f.embeddingDown {
                    CoreNotice(
                        symbol: "text.magnifyingglass", title: "Meaning search is off",
                        text: "Exact search still works.", tone: .warn)
                }
            }
        }
    }
}
