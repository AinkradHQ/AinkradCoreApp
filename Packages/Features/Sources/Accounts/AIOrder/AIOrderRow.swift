import CoreUI
import SwiftUI

/// The provider's mark: one letter on a flat well, as a stand-in until the real marks are dropped in (as the mockup says).
struct ProviderTile: View {
    @Environment(\.coreAccent) private var paneAccent
    let name: String
    var size: CGFloat = 36
    var body: some View {
        Group {
            if let mark = ProviderCatalog.mark(name) {
                Image(mark, bundle: .main).renderingMode(.template).resizable().scaledToFit()
                    .frame(width: size * 0.5, height: size * 0.5)
            } else {
                Text(ProviderCatalog.letter(name)).coreFont(size: size * 0.44, weight: .semibold)
            }
        }
        .foregroundStyle(GlassInk.ink(GlassInk.accent(paneAccent)))
        .frame(width: size, height: size)
        .background(GlassInk.well, in: coreShape(size > 40 ? Radius.cardMac : Radius.control))
        .accessibilityHidden(true)
    }
}

extension OrderChip {
    var badge: (label: String, tone: Tone, symbol: String) {
        switch self {
        case .ready: ("Ready", .run, "checkmark.circle")
        case .inUse: ("In use now", .done, "play.circle")
        case .limitHit: ("Limit hit", .warn, "exclamationmark.triangle")
        case .signingIn: ("Signing in", .queue, "person.crop.circle.badge.clock")
        case .off: ("Turned off", .queue, "pause.circle")
        case .needsLook(let w): (w, .fail, "exclamationmark.triangle")
        }
    }
}

/// One row of the AI order: grip, number, provider, name and sentence, type, state, meter and the More menu.
struct OrderRowView: View {
    static let height: CGFloat = 64
    let row: OrderRow
    let first: Bool
    let last: Bool
    let dragging: Bool
    let onDrag: (CGFloat) -> Void
    let onDrop: (CGFloat) -> Void
    let onKey: (Int) -> Void
    let onAction: (RowAction) -> Void
    @State private var more = false

    enum RowAction { case open, up, down, check, limits, remove }

    var body: some View {
        let b = row.chip.badge
        HStack(spacing: Space.s3) {
            grip
            Text("\(row.number)").coreFont(size: MacTextSize.title, weight: .semibold).monospacedDigit()
                .foregroundStyle(GlassInk.secondary).frame(width: Space.s5, alignment: .center)
            ProviderTile(name: row.title)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).coreFont(size: MacTextSize.headline, weight: .semibold).lineLimit(1)
                Text(row.sentence).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(row.chip == .limitHit ? 0.75 : 1)
            .contentShape(Rectangle())
            .onTapGesture { onAction(.open) }
            .help("Open \(row.title)")
            CoreChip(row.kind == .subscription ? "Subscription" : "API key", minWidth: 0)
            if let b = row.account.runnerBinding { CoreChip(b.words, minWidth: 0).help(b.detail) }
            StateBadge(b.label, tone: b.tone, symbol: b.symbol).frame(width: Space.s8 * 3, alignment: .leading)
            meter.frame(width: Space.s8 * 3)
            menu
        }
        .padding(.horizontal, Space.s3)
        .frame(height: Self.height)
        .coreWell(radius: Radius.row)
        .scaleEffect(dragging ? 1.01 : 1)
        .shadow(color: dragging ? GlassInk.shade(0.25) : .clear, radius: 12, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(row.number). \(row.title), \(b.label). \(row.sentence)")
        .accessibilityIdentifier("order-row-\(row.account.id)")
    }

    private var grip: some View {
        Image(systemName: "line.3.horizontal").coreFont(size: MacTextSize.title)
            .foregroundStyle(GlassInk.secondary).frame(width: Space.s6, height: Space.s6)
            .contentShape(Rectangle())
            .focusable().focusEffectDisabled()
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .global)
                    .onChanged { onDrag($0.translation.height) }
                    .onEnded { onDrop($0.translation.height) }
            )
            .onKeyPress(keys: [.upArrow, .downArrow]) { p in
                guard p.modifiers.contains(.option) else { return .ignored }
                onKey(p.key == .upArrow ? -1 : 1)
                return .handled
            }
            .help("Drag to change the order, or press ⌥↑ and ⌥↓")
            .accessibilityLabel("Reorder \(row.title)")
            .accessibilityHint("Press Option and an arrow key to move it")
            .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var meter: some View {
        if let m = row.meter {
            CoreMeter(m, low: m > 0.8 || row.chip == .limitHit, label: "Use of \(row.title)")
        } else {
            CoreBusyBar()
        }
    }

    private var menu: some View {
        CoreDropdown(
            items: [
                CoreDropdownItem("Move up", symbol: "chevron.up", enabled: !first) { onAction(.up) },
                CoreDropdownItem("Move down", symbol: "chevron.down", enabled: !last) { onAction(.down) },
                CoreDropdownItem(
                    row.chip == .signingIn ? "Finish signing in" : "Check it now", symbol: "arrow.clockwise"
                ) { onAction(.check) },
                CoreDropdownItem("Limits…", symbol: "gearshape") { onAction(.limits) },
                CoreDropdownItem("Remove", symbol: "trash", destructive: true) { onAction(.remove) },
            ], isPresented: $more
        ) {
            Image(systemName: "ellipsis").coreFont(size: MacTextSize.title)
                .foregroundStyle(GlassInk.secondary).frame(width: Space.s6, height: Space.s6)
                .contentShape(Rectangle())
        }
        .help("More")
        .accessibilityLabel("More for \(row.title)")
    }
}
