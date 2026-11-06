import CoreUI
import SwiftUI

/// One terminal as a little terminal: a screen in the user's theme and transparency (window dots, a state badge, the
/// prompt), the runner, and the facts. Hover lifts its fill and shows its actions as mini buttons with their keys; the
/// selected one shows them too. Tiles rise in one after another.
struct TerminalTile: View {
    let model: TerminalsModel
    let item: TerminalItem
    var index = 0
    @State private var hovering = false
    @State private var shown = false

    var body: some View {
        let session = model.sessions[item.id]
        let base =
            session?.view.chip
            ?? PaneView.make(item: item, runner: model.runner(item.runner), link: .none, note: nil).chip
        let selected = model.selected == item.id
        let runner = model.name(of: item.runner)
        let showActions = hovering || selected
        // A bell rang in it: same words, warn tone.
        let chip =
            model.rang.contains(item.id) ? PaneView.Chip(label: base.label, tone: .warn, symbol: "bell.fill") : base
        VStack(alignment: .leading, spacing: Space.s2) {
            TileScreen(runner: runner, chip: chip, ended: item.isEnded)
                .overlay(alignment: .bottomTrailing) {
                    actions.opacity(showActions ? 1 : 0).allowsHitTesting(showActions)
                        .accessibilityHidden(!showActions)
                }
            HStack(spacing: Space.s2) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.shell.tabNames["terminal-\(item.id)"] ?? "Terminal")
                        .font(.system(size: MacTextSize.headline, weight: .semibold)).lineLimit(1)
                    Text(
                        [
                            runner, item.cols > 0 ? "\(item.cols)×\(item.rows)" : nil,
                            item.isEnded ? "ended" : "opened \(ago(item.createdAt))", "\(item.attached) attached",
                        ].compactMap { $0 }.joined(separator: " · ")
                    )
                    .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary).monospacedDigit()
                    .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
                if let session {
                    TimelineView(.periodic(from: .now, by: 60)) { ctx in
                        CoreHeat(session.heat(now: ctx.date)).help("Output this Mac saw in the last hour")
                    }
                }
            }
            .padding(.horizontal, Space.s1)
        }
        .foregroundStyle(GlassInk.primary)
        .padding(Space.s2)
        .background(
            selected ? GlassInk.blue.opacity(0.16) : hovering ? GlassInk.wellHover : GlassInk.well,
            in: coreShape(Radius.cardMac)
        )
        .overlay {
            coreShape(Radius.cardMac).strokeBorder(
                selected ? GlassInk.blue.opacity(0.7) : GlassInk.wellEdge, lineWidth: 1)
        }
        .opacity(item.isEnded ? 0.7 : 1)
        .contentShape(coreShape(Radius.cardMac))
        .onTapGesture(count: 2) { TileAction.run(.open, item.id, model) }
        .onTapGesture { withAnimation(Motion.out(Motion.ui)) { model.selected = item.id } }
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
        .animation(Motion.out(Motion.ui), value: selected)
        .coreRise(shown, index)
        .onAppear { shown = true }
        .contextMenu {
            Button("Open") { TileAction.run(.open, item.id, model) }
            Button("Detach") { TileAction.run(.detach, item.id, model) }.disabled(session == nil)
            Button("Send Signal…") { TileAction.run(.signal, item.id, model) }.disabled(item.isEnded)
            Button("Rename…") { TileAction.run(.rename, item.id, model) }
            Button("End Terminal…", role: .destructive) { TileAction.run(.end, item.id, model) }.disabled(item.isEnded)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Terminal on \(runner), \(chip.label), \(item.cols) by \(item.rows), \(item.attached) attached"
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction(named: "Open") { TileAction.run(.open, item.id, model) }
    }

    /// The tile's actions: mini buttons, each with its key.
    private var actions: some View {
        HStack(spacing: Space.s1) {
            TileMiniButton("arrow.up.forward.app", key: "↩", label: "Open terminal") {
                TileAction.run(.open, item.id, model)
            }
            if !item.isEnded {
                TileMiniButton("eject", key: "D", label: "Detach terminal") { TileAction.run(.detach, item.id, model) }
                TileMiniButton("bolt", key: "S", label: "Send a signal") { TileAction.run(.signal, item.id, model) }
                TileMiniButton("stop.fill", key: "E", label: "End terminal", destructive: true) {
                    TileAction.run(.end, item.id, model)
                }
            }
        }
        .padding(Space.s2)
    }
}

/// The tile's screen in the user's terminal theme and transparency.
private struct TileScreen: View {
    let runner: String
    let chip: PaneView.Chip
    let ended: Bool
    @Bindable private var prefs = TerminalPrefs.shared

    var body: some View {
        let t = prefs.theme
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s1) {
                ForEach(0..<3, id: \.self) { _ in coreShape(2).fill(.white.opacity(0.16)).frame(width: 6, height: 6) }
                Spacer()
                StateBadge(chip.label, tone: chip.tone, symbol: chip.symbol)
            }
            HStack(spacing: 0) {
                Text(runner).foregroundStyle(GlassInk.blue)
                Text(" ~ ").foregroundStyle(Color(nsColor: t.foreground).opacity(0.7))
                Text("$ ").foregroundStyle(Color(nsColor: t.foreground))
                if ended {
                    Text("[exited]").foregroundStyle(Color(nsColor: t.foreground).opacity(0.5))
                } else {
                    coreShape(Radius.chip / 3).fill(Color(nsColor: t.caret)).frame(width: 7, height: 14)
                }
            }
            .font(Font(prefs.font).weight(.medium))
            .lineLimit(1)
            .padding(.top, Space.s2)
            // The prompt sits under the dots so the hover actions at the bottom never cover it.
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, minHeight: Space.s8 * 3 + Space.s2, alignment: .topLeading)
        .background {
            ZStack {
                if prefs.blur { coreShape(Radius.row).fill(.ultraThinMaterial).environment(\.colorScheme, .dark) }
                coreShape(Radius.row).fill(Color(nsColor: prefs.screenColor))
            }
        }
        .overlay { coreShape(Radius.row).strokeBorder(.white.opacity(0.12), lineWidth: 1) }
    }
}
