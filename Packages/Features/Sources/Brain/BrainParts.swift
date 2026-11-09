import CoreUI
import SwiftUI

/// A small rounded status chip: sentence case, a solid tint, never a pill or a glow.
struct BrainChip: View {
    let text: String
    let hue: Color
    var help: String?
    init(_ text: String, _ hue: Color, help: String? = nil) {
        self.text = text
        self.hue = hue
        self.help = help
    }
    var body: some View {
        Text(text).font(.system(size: MacTextSize.meta, weight: .medium)).lineLimit(1)
            .foregroundStyle(GlassInk.primary)
            .padding(.horizontal, Space.s2).frame(height: MacSize.chip)
            .background(hue.opacity(0.28), in: coreShape(Radius.chip))
            .help(help ?? "")
    }
}

/// The chips every Brain screen shows for a room: its mode, provider policy and, for employer and client rooms, who it is for.
struct RoomChips: View {
    let room: RoomSummary
    var body: some View {
        HStack(spacing: Space.s2) {
            BrainChip(room.mode.label, room.mode == .localOnly ? GlassInk.blue : GlassInk.slate, help: room.mode.story)
            BrainChip(room.provider.label, room.provider == .approvedCloud ? GlassInk.blue : GlassInk.slate)
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
                Text(title).font(.system(size: MacTextSize.headline, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
            }
            if let sub {
                Text(sub).font(.system(size: MacTextSize.body)).foregroundStyle(GlassInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .coreWell()
    }
}

/// A bar that fills to a fraction. Instant under Reduce Motion; the value is always printed beside it.
struct BrainBar: View {
    let fraction: Double
    var hue: Color = GlassInk.blue
    var height: CGFloat = 6
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown = false
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                coreShape(height / 2).fill(GlassInk.well)
                coreShape(height / 2).fill(hue)
                    .frame(width: g.size.width * min(max(fraction, 0), 1) * (shown || reduce ? 1 : 0))
            }
        }
        .frame(height: height)
        .onAppear { withAnimation(reduce ? nil : Motion.out(Motion.reveal)) { shown = true } }
        .accessibilityHidden(true)
    }
}

/// A full-width state: a symbol, a plain sentence, and the next step. Used for loading, empty, unavailable, error.
struct BrainStateCard<Actions: View>: View {
    let symbol: String
    let title: String
    let text: String
    var tone: Tone = .queue
    @ViewBuilder var actions: Actions
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            CoreNotice(symbol: symbol, title: title, text: text, tone: tone)
            HStack(spacing: Space.s2) { actions }.frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

extension BrainStateCard where Actions == EmptyView {
    init(symbol: String, title: String, text: String, tone: Tone = .queue) {
        self.init(symbol: symbol, title: title, text: text, tone: tone) { EmptyView() }
    }
}

/// A section title in sentence case.
struct BrainTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: MacTextSize.title, weight: .semibold)).accessibilityAddTraits(.isHeader)
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
