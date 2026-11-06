import CoreUI
import SwiftUI

/// A titled group the way Settings groups things: a heading and a line under it, then the panel.
struct AdminSection<Content: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder let content: Content
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            VStack(alignment: .leading, spacing: Space.s1 / 2) {
                Text(title).font(.system(size: MacTextSize.title, weight: .semibold)).accessibilityAddTraits(.isHeader)
                if let detail {
                    Text(detail).foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
        .font(.system(size: MacTextSize.body))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The glass card rows sit in.
struct AdminPanel<Content: View>: View {
    var spacing: CGFloat = Space.s3
    @ViewBuilder let content: Content
    @Environment(\.corePalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .coreFrame(radius: Radius.cardMac + Space.s1, rim: Space.s1)
    }
}

/// A short word in a rounded box: a delivery, a version, a runner. Neutral; never the only carrier of a state.
struct MetaChip: View {
    let text: String
    var mono = false
    @Environment(\.corePalette) private var palette
    var body: some View {
        Text(text).font(.system(size: MacTextSize.meta, weight: .medium, design: mono ? .monospaced : .default))
            .padding(.horizontal, Space.s2).frame(minHeight: MacSize.chip)
            .background(palette.uDim, in: coreShape(Radius.chip))
    }
}

/// "Needs Touch ID", "Weakens security": a lock or a warning, then the words.
struct GateTag: View {
    let text: String
    var warn = false
    @Environment(\.corePalette) private var palette
    var body: some View {
        Label(text, systemImage: warn ? "exclamationmark.triangle" : "lock")
            .font(.system(size: MacTextSize.meta)).foregroundStyle(warn ? palette.tone(.warn).ink : palette.text2)
            .labelStyle(.titleAndIcon)
    }
}

/// Progress with no end in sight: a rounded bar with a segment that slides. With Reduce Motion the segment rests in the middle.
struct AdminBar: View {
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

/// The inline outcome of a Touch ID that did not elevate, in the panel that asked.
struct AdminNoticeBanner: View {
    let notice: AdminNotice?
    var body: some View {
        if let n = notice {
            CoreNotice(symbol: n.symbol, title: n.title, text: n.detail, tone: n.warn ? .warn : .queue)
                .accessibilityIdentifier("stepup-notice")
        }
    }
}

/// A refusal from the Core under a field or a row, in words.
struct IssueLine: View {
    let code: String?
    let text: String
    @Environment(\.corePalette) private var palette
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle").accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true).help(code ?? "")
        }
        .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.tone(.fail).ink)
        .accessibilityElement(children: .combine)
    }
}

/// A state that replaces a section: a symbol tile, a title, the words and what to do about it.
struct StateCard<Actions: View>: View {
    let symbol: String
    let title: String
    let text: String
    var tone: Tone = .queue
    @ViewBuilder let actions: Actions
    @Environment(\.corePalette) private var palette

    var body: some View {
        let c = palette.tone(tone)
        VStack(spacing: Space.s2) {
            Image(systemName: symbol).font(.system(size: MacTextSize.large)).foregroundStyle(c.ink)
                .frame(width: MacSize.controlLg + Space.s3, height: MacSize.controlLg + Space.s3)
                .background(c.fill, in: coreShape(Radius.cardMac)).accessibilityHidden(true)
            Text(title).font(.system(size: MacTextSize.title, weight: .semibold)).accessibilityAddTraits(.isHeader)
            Text(text).foregroundStyle(palette.text2).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: Space.s8 * 16)
            HStack(spacing: Space.s2) { actions }.padding(.top, Space.s2)
        }
        .padding(Space.s6)
        .frame(maxWidth: .infinity)
        .coreFrame(radius: Radius.cardMac + Space.s1, rim: Space.s1)
        .accessibilityElement(children: .contain)
    }
}

extension StateCard where Actions == EmptyView {
    init(symbol: String, title: String, text: String, tone: Tone = .queue) {
        self.init(symbol: symbol, title: title, text: text, tone: tone) { EmptyView() }
    }
}

/// The loading state: a bar, a word, and quiet rows where the content will be.
struct SectionSkeleton: View {
    @Environment(\.corePalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            AdminBar().frame(maxWidth: Space.s8 * 5)
            Text("Loading…").foregroundStyle(palette.text2)
            ForEach(0..<5, id: \.self) { i in
                coreShape(Radius.cardMac).fill(palette.glassCard).frame(height: i == 0 ? Space.s8 : Space.s8 + Space.s5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// What one admin section shows: the page when the Core answered, else the one state that fits. While changes are paused
/// (the Core is unreachable or rate limiting) the page stays but is dimmed and cannot be used.
struct AdminScreen<Content: View>: View {
    let admin: AdminModel
    let what: String
    let intro: String
    let state: SectionState
    var empty: (title: String, text: String, symbol: String) = ("Nothing here", "", "tray")
    var emptyAction: (title: String, run: () -> Void)?
    let retry: () -> Void
    @ViewBuilder let content: Content
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            Text(intro).foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
            if !admin.isConnected {
                StateCard(
                    symbol: "wifi.slash", title: "Not connected",
                    text: "\(what) come from your Core. This Mac is not connected to one right now.")
            } else {
                switch state {
                case .loading: SectionSkeleton()
                case .ready:
                    content.opacity(admin.host.pausedReason == nil ? 1 : 0.55).disabled(admin.host.pausedReason != nil)
                case .empty:
                    StateCard(
                        symbol: empty.symbol, title: empty.title,
                        text: empty.text
                    ) {
                        if let emptyAction {
                            Button(emptyAction.title, action: emptyAction.run).buttonStyle(.coreProminent)
                        }
                    }
                case .failed(let code, let message, let id):
                    StateCard(
                        symbol: "exclamationmark.triangle", title: "Could not load this",
                        text: "Your Core couldn't answer that. Nothing was changed.", tone: .fail
                    ) { Button("Try again", action: retry).buttonStyle(.coreProminent) }
                    .help([message, code, id].compactMap { $0 }.joined(separator: " · "))
                case .forbidden:
                    StateCard(
                        symbol: "lock", title: "This device is not allowed to do that",
                        text: "Reading and changing this needs an admin device. Use one that can manage this Core."
                    )
                    .help("forbidden_scope")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

enum AdminWords {
    /// `Nov 3, 06:27`: the form a list uses, no seconds.
    static func when(_ d: Date) -> String {
        d.formatted(.dateTime.month(.abbreviated).day().hour(.twoDigits(amPM: .omitted)).minute())
    }
    /// `Nov 3, 06:27:17`: for one row's details.
    static func whenExact(_ d: Date) -> String {
        d.formatted(.dateTime.month(.abbreviated).day().hour(.twoDigits(amPM: .omitted)).minute().second())
    }
    static func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .standard) }
    static func bytes(_ n: Int64) -> String { "\(n) B" }
    static func number(_ n: Int64) -> String { n.formatted(.number.grouping(.never)) }
}
