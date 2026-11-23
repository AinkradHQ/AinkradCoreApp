import CoreUI
import SwiftUI

/// The small pieces every redesigned Brain page shares (Designs/core/0-10/review/brain): the icon tile, the page head, how
/// sure, a place, the 14-day bars, a section head and a "learned" line with Forget.

/// A rounded-rect icon tile; `lit` tints it with the accent (the page's own icon, the one that is live).
struct BrainTile: View {
    let symbol: String
    var lit = false
    var size: CGFloat = Space.s6 + Space.s1
    var tint: Color?
    @Environment(\.coreAccent) private var accent
    @Environment(\.corePalette) private var palette

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .medium))
            .foregroundStyle(tint ?? (lit ? palette.primary : GlassInk.primary))
            .frame(width: size, height: size)
            .background(
                tint.map { $0.opacity(0.18) } ?? (lit ? GlassInk.accent(accent).opacity(0.2) : GlassInk.well),
                in: coreShape(size > Space.s8 ? Radius.cardMac : Radius.control)
            )
            .accessibilityHidden(true)
    }
}

/// "Rules 270" over "What Brain follows when it works for you · +6 today", with the page's tile and its actions.
struct BrainHead<Actions: View>: View {
    let symbol: String
    let title: String
    var crumb: String?
    var count: Int?
    let sub: String
    var today = 0
    var back: (() -> Void)?
    @ViewBuilder var actions: Actions
    @Environment(\.corePalette) private var palette

    var body: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            BrainTile(symbol: symbol, lit: true, size: Space.s8 + Space.s3)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                    if let crumb, let back {
                        Button(crumb, action: back).buttonStyle(.plain).foregroundStyle(GlassInk.secondary)
                            .help("Back to \(crumb) (⌘[)").keyboardShortcut("[", modifiers: .command)
                        Image(systemName: "chevron.right").coreFont(size: MacTextSize.body)
                            .foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
                    }
                    Text(title)
                    if let count {
                        Text(count.formatted()).fontWeight(.regular).foregroundStyle(GlassInk.secondary)
                            .monospacedDigit().contentTransition(.numericText())
                    }
                }
                .coreFont(size: MacTextSize.large, weight: .semibold)
                .accessibilityAddTraits(.isHeader)
                (Text(sub).foregroundColor(GlassInk.secondary)
                    + Text(today > 0 ? " · " : "").foregroundColor(GlassInk.secondary)
                    + Text(today > 0 ? "+\(today.formatted()) today" : "").fontWeight(.semibold)
                    .foregroundColor(palette.success))
                    .coreFont(size: MacTextSize.body)
            }
            Spacer(minLength: Space.s3)
            actions
        }
    }
}

extension BrainHead where Actions == EmptyView {
    init(symbol: String, title: String, count: Int? = nil, sub: String, today: Int = 0) {
        self.init(symbol: symbol, title: title, count: count, sub: sub, today: today) { EmptyView() }
    }
}

/// How sure Brain is: five short bars, lit up to the level. The words go beside it or in its help.
struct SureBars: View {
    let support: Int
    @Environment(\.corePalette) private var palette

    var body: some View {
        let n = BrainSure.level(support)
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                coreShape(1).fill(i <= n ? palette.primary : palette.track).frame(width: Space.s2 + 1, height: 4)
            }
        }
        .help("Seen in \(BrainWords.plural(support, "session", "sessions")): \(BrainSure.words(support))")
        .accessibilityElement()
        .accessibilityLabel("How sure: \(BrainSure.words(support))")
    }
}

/// A place, or Everywhere, as a small chip.
struct PlaceChip: View {
    let name: String
    var everywhere = false

    var body: some View {
        HStack(spacing: Space.s1) {
            Image(systemName: everywhere ? "globe" : "folder").accessibilityHidden(true)
            Text(everywhere ? "Everywhere" : name).lineLimit(1)
        }
        .coreFont(size: MacTextSize.meta)
        .modifier(PlaceInk(everywhere: everywhere))
        .padding(.horizontal, Space.s2).padding(.vertical, 2)
        .background(GlassInk.well, in: coreShape(Radius.chip))
    }
}

/// Fourteen days as bars, oldest first, today in full accent. A series of less than two days draws nothing.
struct DayBars: View {
    let series: [Int]
    var height: CGFloat = Space.s6
    @Environment(\.coreAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown = false

    var body: some View {
        let top = Double(max(series.max() ?? 0, 1))
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(series.enumerated()), id: \.offset) { i, v in
                coreShape(2)
                    .fill(GlassInk.accent(accent).opacity(i == series.count - 1 ? 1 : 0.55))
                    .frame(height: max(3, height * CGFloat(Double(v) / top) * (shown ? 1 : 0.15)))
                    .animation(Motion.calm(Motion.out(Motion.move), reduce).delay(Double(i) * 0.02), value: shown)
            }
        }
        .frame(height: height, alignment: .bottom)
        .opacity(series.count >= 2 ? 1 : 0)
        .onAppear { shown = true }
        .accessibilityHidden(true)
    }
}

/// "Learned today" and the other cards' title line: the name, and what sits on the right.
struct BrainCardHead<Right: View>: View {
    let title: String
    @ViewBuilder var right: Right

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).coreFont(size: MacTextSize.body, weight: .semibold).foregroundStyle(GlassInk.secondary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Space.s2)
            right.coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
        }
    }
}

/// One thing Brain learned: its icon, the sentence, where and when, and Forget (Undo in the toast).
struct LearnedLine: View {
    let symbol: String
    let line: String
    let meta: String
    let forget: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            BrainTile(symbol: symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(line).coreFont(size: MacTextSize.body).lineLimit(1)
                Text(meta).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let forget {
                Button("Forget", action: forget).buttonStyle(CoreButtonStyle(.plain, size: .small))
                    .help("Forget this. It is kept in the archive, and Undo brings it back.")
            }
        }
        .accessibilityElement(children: .contain)
        .transition(.opacity)
    }
}

/// "Search rules": a search field that narrows the list as you type (after a short pause) and on Return.
struct FilterField: View {
    let placeholder: String
    @Binding var text: String
    let run: () async -> Void
    @FocusState private var focused: Bool
    @State private var armed = false

    var body: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "magnifyingglass").foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
            TextField(placeholder, text: $text).textFieldStyle(.plain).focused($focused)
                .onSubmit { Task { await run() } }
                .onKeyPress(.escape) {
                    guard !text.isEmpty else { return .ignored }
                    text = ""
                    return .handled
                }
                .accessibilityLabel(placeholder)
        }
        .padding(.horizontal, Space.s3)
        .frame(height: MacSize.controlMd)
        .coreFieldSurface(focused: focused)
        .task(id: text) {
            // The page loaded its list already; only a change of words reads again.
            guard armed else {
                armed = true
                return
            }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await run()
        }
    }
}

/// The pane's accent as ink: links, the ask box's sparkle, Everywhere.
private struct AccentInk: ViewModifier {
    @Environment(\.coreAccent) private var accent
    func body(content: Content) -> some View { content.foregroundStyle(GlassInk.accentInk(accent)) }
}

extension View {
    func brainAccentInk() -> some View { modifier(AccentInk()) }
}

private struct PlaceInk: ViewModifier {
    let everywhere: Bool
    @Environment(\.coreAccent) private var accent
    func body(content: Content) -> some View {
        content.foregroundStyle(everywhere ? GlassInk.accentInk(accent) : GlassInk.primary)
    }
}
