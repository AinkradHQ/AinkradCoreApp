import Admin
import CoreUI
import Shell
import SwiftUI

/// The glass card content sits in: a quiet well that lifts a touch on hover.
struct AccPanel<Content: View>: View {
    var spacing: CGFloat = Space.s3
    @ViewBuilder let content: Content
    @State private var hovering = false
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? GlassInk.wellHover : GlassInk.well, in: coreShape(Radius.cardMac))
            .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.2), value: hovering)
    }
}

/// A page heading: its icon tile bouncing in, the title and its line, and an optional action on the right.
struct AccHeader<Action: View>: View {
    let title: String
    let detail: String
    var symbol = "creditcard"
    var hue = GlassInk.blue
    @ViewBuilder let action: Action
    @State private var shown = false
    var body: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            IconTile(symbol, hue: hue, size: 48, bounce: shown).shadow(color: hue.opacity(0.45), radius: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: MacTextSize.large, weight: .bold)).accessibilityAddTraits(.isHeader)
                    .contentTransition(.numericText())
                Text(detail).foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s3)
            action
        }
        .onAppear { shown = true }
    }
}

/// The mark of an account: a rounded tile in its provider's colour and symbol.
struct AccTile: View {
    var symbol: String?
    var large = false
    var provider: String?
    var body: some View {
        let hue = provider.map(ProviderLook.hue) ?? GlassInk.slate
        let size = large ? 56.0 : 36.0
        Image(systemName: symbol ?? provider.map(ProviderLook.symbol) ?? "key.fill")
            .font(.system(size: large ? 24 : 15, weight: .semibold)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [hue, hue.opacity(0.55)], startPoint: .top, endPoint: .bottom),
                in: coreShape(large ? 13 : 9)
            )
            .overlay { coreShape(large ? 13 : 9).strokeBorder(.white.opacity(0.25), lineWidth: 1) }
            .shadow(color: hue.opacity(0.4), radius: large ? 14 : 6)
            .accessibilityHidden(true)
    }
}

/// The state badge for an account: a symbol and its word, never colour alone.
struct PhaseBadge: View {
    let phase: AccountPhase
    var body: some View { StateBadge(phase.label, tone: phase.tone, symbol: phase.symbol) }
}

/// A small glass action: icon and words, lifting and lighting in its colour on hover (red when it removes something).
struct AccLink: View {
    let title: String
    var symbol: String?
    var danger = false
    var help: String?
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false
    var body: some View {
        let hue = danger ? GlassInk.red : GlassInk.blue
        Button(action: action) {
            HStack(spacing: Space.s1) {
                if let symbol {
                    Image(systemName: symbol).symbolEffect(.bounce, value: hovering).accessibilityHidden(true)
                }
                Text(title).font(.system(size: MacTextSize.meta, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(hovering ? .white : hue)
            .padding(.horizontal, Space.s2).frame(minHeight: 26)
            .background(hovering ? hue.opacity(0.7) : hue.opacity(0.12), in: coreShape(7))
            .overlay { coreShape(7).strokeBorder(hue.opacity(0.35), lineWidth: 1) }
            .contentShape(coreShape(7))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .scaleEffect(hovering ? 1.04 : 1)
        .onHover { hovering = $0 && enabled }
        .animation(.spring(duration: 0.25, bounce: 0.3), value: hovering)
        .coreDimWhenDisabled(enabled)
        .help(help ?? title)
    }
}

/// Progress with no end in sight: a rounded bar with a segment that slides. With Reduce Motion the segment rests.
struct AccBar: View {
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

/// A refusal from the Core under a control: the words, with the code the Core gave.
struct AccIssue: View {
    let text: String
    @Environment(\.corePalette) private var palette
    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.tone(.fail).ink)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
    }
}

/// A state that replaces a page: a bouncing icon tile in its tone, a title, the words and what to do about it.
struct AccStateCard<Actions: View>: View {
    let symbol: String
    let title: String
    let text: String
    var tone: Tone = .queue
    var code: String?
    @ViewBuilder let actions: Actions
    @State private var shown = false
    var body: some View {
        let hue = tone == .fail ? GlassInk.red : tone == .warn ? GlassInk.orange : GlassInk.blue
        VStack(spacing: Space.s3) {
            IconTile(symbol, hue: hue, size: 64, bounce: shown).shadow(color: hue.opacity(0.5), radius: 18)
                .scaleEffect(shown ? 1 : 0.6)
            Text(title).font(.system(size: MacTextSize.large, weight: .bold)).accessibilityAddTraits(.isHeader)
            Text(text).foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: Space.s8 * 16)
            if let code {
                Text(code).font(.system(size: MacTextSize.meta, design: .monospaced)).padding(.horizontal, Space.s2)
                    .frame(minHeight: 22).background(GlassInk.well, in: coreShape(6))
            }
            HStack(spacing: Space.s2) { actions }.padding(.top, Space.s2)
        }
        .padding(Space.s6)
        .frame(maxWidth: .infinity)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
        .overlay { coreShape(Radius.cardMac).strokeBorder(hue.opacity(tone == .queue ? 0.15 : 0.45), lineWidth: 1) }
        .animation(.spring(duration: 0.45, bounce: 0.3), value: shown)
        .onAppear { shown = true }
        .accessibilityElement(children: .contain)
    }
}

extension AccStateCard where Actions == EmptyView {
    init(symbol: String, title: String, text: String, tone: Tone = .queue, code: String? = nil) {
        self.init(symbol: symbol, title: title, text: text, tone: tone, code: code) { EmptyView() }
    }
}

/// A figure the Core does not report yet: a quiet card with an hourglass that turns, so nothing is ever estimated.
struct NotYetCard: View {
    let title: String
    var text = "Not available yet. Core does not report this."
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        AccPanel(spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Image(systemName: "hourglass").foregroundStyle(GlassInk.slate)
                    .symbolEffect(.pulse, options: .repeating, isActive: !reduce)
                Text(title).font(.system(size: MacTextSize.headline, weight: .semibold))
            }
            Text(text).foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The loading state: a bar, a word, and quiet cards where the content will be.
struct AccSkeleton: View {
    @Environment(\.corePalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            AccBar().frame(maxWidth: Space.s8 * 5)
            Text("Loading…").foregroundStyle(palette.text2)
            ForEach(0..<4, id: \.self) { _ in
                coreShape(Radius.cardMac).fill(palette.glassCard).frame(height: Space.s8 + Space.s6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// The inline outcome of a Touch ID that did not elevate, in the dialog or page that asked.
struct AccNotice: View {
    let notice: AdminNotice?
    var body: some View {
        if let n = notice {
            CoreNotice(symbol: n.symbol, title: n.title, text: n.detail, tone: n.warn ? .warn : .queue)
                .accessibilityIdentifier("stepup-notice")
        }
    }
}

/// Where your Core stands on keeping account keys, in plain words and as three steps (Off, Test keys, Real keys) with
/// the current one lit, and the way to change it. The settings' own names are in the hover help.
struct GateBanner: View {
    let model: AccountsModel
    @State private var shown = false

    var body: some View {
        let g = model.gate
        if g.kind != .real {
            let hue = g.kind == .off ? GlassInk.orange : g.kind == .throwaway ? GlassInk.blue : GlassInk.slate
            HStack(alignment: .center, spacing: Space.s4) {
                IconTile(
                    g.kind == .off ? "lock.fill" : g.kind == .throwaway ? "testtube.2" : "questionmark", hue: hue,
                    size: 44, bounce: shown
                )
                .shadow(color: hue.opacity(0.45), radius: 10)
                VStack(alignment: .leading, spacing: 3) {
                    Text(g.title).font(.system(size: MacTextSize.headline, weight: .semibold))
                    Text(g.detail).foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.s3)
                if let step = g.step { StepTrack(["Off", "Test keys", "Real keys"], at: step, hue: hue) }
                AppActionTile(title: "Change", symbol: "slider.horizontal.3", key: "", hue: hue) {
                    model.openSwitches()
                }
                .help("Settings → Core → Feature switches")
            }
            .padding(Space.s3)
            .background(hue.opacity(0.12), in: coreShape(Radius.cardMac))
            .overlay { coreShape(Radius.cardMac).strokeBorder(hue.opacity(0.4), lineWidth: 1) }
            .help(g.technical)
            .onAppear { shown = true }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("gate-banner")
        }
    }
}

/// The "can only read" notice, shown once a write came back `forbidden_scope`.
struct ReadOnlyBanner: View {
    let model: AccountsModel
    var body: some View {
        if model.readOnly {
            CoreNotice(
                symbol: "lock", title: "This device can only read",
                text: "Changes are refused (forbidden_scope). Use a device that holds the admin scope."
            )
            .accessibilityIdentifier("read-only-banner")
        }
    }
}

/// Cancel and the one action of a dialog, as glass tiles with their keys: Cancel at the left (esc), the action at the
/// right (↩, or ⌘↩ when it removes something, so Return alone never destroys).
struct AccDialogButtons: View {
    let confirm: String
    var cancelTitle = "Cancel"
    var danger = false
    var busy = false
    var enabled = true
    let cancel: () -> Void
    let run: () -> Void
    @State private var hovered: Int?
    var body: some View {
        HStack(spacing: Space.s2) {
            ChoiceTile(
                choice: ConfirmChoice(cancelTitle, symbol: cancelTitle == "Cancel" ? "arrow.uturn.backward" : "xmark"),
                on: hovered == 0, keys: "esc",
                run: cancel
            )
            .keyboardShortcut(.cancelAction)
            .onHover { hovered = $0 ? 0 : nil }
            .frame(maxWidth: Space.s8 * 5)
            Spacer(minLength: Space.s2)
            ChoiceTile(
                choice: ConfirmChoice(
                    busy ? "\(confirm)…" : confirm, symbol: danger ? "trash" : "checkmark", destructive: danger),
                on: hovered != 0 && enabled && !busy, keys: danger ? "⌘↩" : "↩", run: run
            )
            .keyboardShortcut(.return, modifiers: danger ? .command : [])
            .disabled(!enabled || busy)
            .opacity(enabled ? 1 : 0.5)
            .onHover { hovered = $0 ? 1 : nil }
            .frame(maxWidth: Space.s8 * 7)
        }
        .animation(.spring(duration: 0.25), value: hovered)
    }
}

/// A short word in a rounded glass box: a model, a runner, a delivery.
struct AccChip: View {
    let text: String
    var mono = false
    var body: some View {
        Text(text).font(.system(size: MacTextSize.meta, weight: .medium, design: mono ? .monospaced : .default))
            .padding(.horizontal, Space.s2).frame(minHeight: 22)
            .background(GlassInk.well, in: coreShape(6))
            .overlay { coreShape(6).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
    }
}

/// One fact: a quiet label and its value.
struct AccFact<Value: View>: View {
    let label: String
    @ViewBuilder let value: Value
    @Environment(\.corePalette) private var palette
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            Text(label).foregroundStyle(palette.text2).frame(width: Space.s8 * 4, alignment: .leading)
            value
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
