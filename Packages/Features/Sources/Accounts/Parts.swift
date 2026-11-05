import Admin
import CoreUI
import Shell
import SwiftUI

/// The glass card content sits in.
struct AccPanel<Content: View>: View {
    var spacing: CGFloat = Space.s3
    @ViewBuilder let content: Content
    @Environment(\.corePalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.glassCard, in: coreShape(Radius.cardMac))
            .overlay { coreShape(Radius.cardMac).strokeBorder(palette.glassCardEdge, lineWidth: 1) }
    }
}

/// A page heading with its line and an optional action on the right.
struct AccHeader<Action: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let action: Action
    @Environment(\.corePalette) private var palette
    var body: some View {
        HStack(alignment: .top, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(title).font(.system(size: MacTextSize.large, weight: .semibold)).accessibilityAddTraits(.isHeader)
                Text(detail).foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s3)
            action
        }
    }
}

/// The small rounded square that marks an account: every API account holds one key.
struct AccTile: View {
    var symbol = "key"
    var large = false
    @Environment(\.corePalette) private var palette
    var body: some View {
        Image(systemName: symbol).font(.system(size: large ? MacTextSize.large : MacTextSize.title))
            .foregroundStyle(palette.primary)
            .frame(
                width: large ? MacSize.controlLg + Space.s2 : MacSize.controlLg,
                height: large ? MacSize.controlLg + Space.s2 : MacSize.controlLg
            )
            .background(palette.uDim, in: coreShape(Radius.control))
            .accessibilityHidden(true)
    }
}

/// The state badge for an account: a symbol and its word, never colour alone.
struct PhaseBadge: View {
    let phase: AccountPhase
    var body: some View { StateBadge(phase.label, tone: phase.tone, symbol: phase.symbol) }
}

/// A text link in the primary colour with the one focus ring; a lock and a dim when a write is not possible.
struct AccLink: View {
    let title: String
    var symbol: String?
    var danger = false
    var help: String?
    let action: () -> Void
    @Environment(\.corePalette) private var palette
    @Environment(\.isEnabled) private var enabled
    @FocusState private var focused: Bool
    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s1) {
                if let symbol { Image(systemName: symbol).accessibilityHidden(true) }
                Text(title).font(.system(size: MacTextSize.body))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(danger ? palette.tone(.fail).ink : palette.primary)
        .focused($focused).focusEffectDisabled()
        .coreFocusRing(focused, radius: Radius.chip, palette: palette)
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

/// A state that replaces a page: a symbol tile, a title, the words and what to do about it.
struct AccStateCard<Actions: View>: View {
    let symbol: String
    let title: String
    let text: String
    var tone: Tone = .queue
    var code: String?
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
            if let code {
                Text(code).font(.system(size: MacTextSize.meta, design: .monospaced)).padding(.horizontal, Space.s2)
                    .frame(minHeight: MacSize.chip).background(palette.uDim, in: coreShape(Radius.chip))
            }
            HStack(spacing: Space.s2) { actions }.padding(.top, Space.s2)
        }
        .padding(Space.s6)
        .frame(maxWidth: .infinity)
        .background(palette.glassCard, in: coreShape(Radius.cardMac))
        .overlay { if tone == .fail { coreShape(Radius.cardMac).strokeBorder(c.ink.opacity(0.5), lineWidth: 1) } }
        .accessibilityElement(children: .contain)
    }
}

extension AccStateCard where Actions == EmptyView {
    init(symbol: String, title: String, text: String, tone: Tone = .queue, code: String? = nil) {
        self.init(symbol: symbol, title: title, text: text, tone: tone, code: code) { EmptyView() }
    }
}

/// A figure the Core does not report yet: a quiet card that says so, so nothing is ever estimated.
struct NotYetCard: View {
    let title: String
    var text = "Not available yet. Core does not report this."
    @Environment(\.corePalette) private var palette
    var body: some View {
        AccPanel(spacing: Space.s1) {
            Text(title).font(.system(size: MacTextSize.headline, weight: .semibold))
            Label(text, systemImage: "hourglass").foregroundStyle(palette.text2).labelStyle(.titleAndIcon)
                .fixedSize(horizontal: false, vertical: true)
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

/// Where the real-accounts gate stands, in words, with the way to change it.
struct GateBanner: View {
    let model: AccountsModel
    var body: some View {
        let g = model.gate
        if g.kind != .real {
            CoreNotice(symbol: g.symbol, title: g.title, text: g.detail, tone: g.tone) {
                Button("Feature switches") { model.openSwitches() }.buttonStyle(.coreSecondary)
                    .help("Open Settings, Core, Feature switches")
            }
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

/// Cancel and the one action of a dialog: Escape cancels, Return confirms.
struct AccDialogButtons: View {
    let confirm: String
    var danger = false
    var busy = false
    var enabled = true
    let cancel: () -> Void
    let run: () -> Void
    var body: some View {
        HStack(spacing: Space.s2) {
            Spacer(minLength: 0)
            Button("Cancel", action: cancel).buttonStyle(.coreSecondary).coreShortcut(.cancel)
            if danger {
                Button(confirm, action: run).buttonStyle(CoreButtonStyle(.danger)).disabled(!enabled || busy)
            } else {
                Button(confirm, action: run).buttonStyle(CoreButtonStyle(.prominent, busy: busy))
                    .coreShortcut(.primary).disabled(!enabled || busy)
            }
        }
    }
}

/// A short word in a rounded box: a model, a runner, a delivery. Neutral.
struct AccChip: View {
    let text: String
    var mono = false
    @Environment(\.corePalette) private var palette
    var body: some View {
        Text(text).font(.system(size: MacTextSize.meta, weight: .medium, design: mono ? .monospaced : .default))
            .padding(.horizontal, Space.s2).frame(minHeight: MacSize.chip)
            .background(palette.uDim, in: coreShape(Radius.chip))
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
