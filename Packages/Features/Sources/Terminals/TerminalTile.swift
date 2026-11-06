import CoreUI
import SwiftUI

/// One terminal as a little terminal: a screen in the user's theme and transparency (window dots, a state badge, the
/// prompt with a blinking cursor), the runner in its own colour, and the facts. Hover lifts it and shows its actions as
/// icon tiles with their keys; the selected one glows. Tiles rise in one after another.
struct TerminalTile: View {
    let model: TerminalsModel
    let item: TerminalItem
    var index = 0
    @State private var hovering = false
    @State private var shown = false

    var body: some View {
        let session = model.sessions[item.id]
        let chip =
            session?.view.chip
            ?? PaneView.make(item: item, runner: model.runner(item.runner), link: .none, note: nil).chip
        let selected = model.selected == item.id
        let runner = model.name(of: item.runner)
        let accent = RunnerHue.of(runner)
        let state: Color =
            model.rang.contains(item.id)
            ? GlassInk.orange
            : item.isEnded
                ? GlassInk.slate
                : chip.tone == .fail ? GlassInk.red : chip.tone == .warn ? GlassInk.orange : GlassInk.green
        VStack(alignment: .leading, spacing: Space.s2) {
            TileScreen(
                runner: runner, accent: accent, state: state, label: chip.label, ended: item.isEnded, blink: shown
            )
            .overlay(alignment: .bottomTrailing) {
                if hovering { actions.transition(.opacity.combined(with: .move(edge: .trailing))) }
            }
            HStack(spacing: Space.s2) {
                coreShape(2).fill(accent).frame(width: 3, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: Space.s1) {
                        Text(model.shell.tabNames["terminal-\(item.id)"] ?? runner)
                            .font(.system(size: MacTextSize.headline, weight: .semibold)).lineLimit(1)
                        if model.rang.contains(item.id) {
                            Image(systemName: "bell.fill").font(.system(size: 10)).foregroundStyle(GlassInk.orange)
                        }
                    }
                    Text(
                        [
                            item.cols > 0 ? "\(item.cols)×\(item.rows)" : nil,
                            item.isEnded ? "ended" : "open \(ago(item.createdAt))", "\(item.attached) attached",
                        ].compactMap { $0 }.joined(separator: " · ")
                    )
                    .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary).monospacedDigit()
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
            selected ? accent.opacity(0.16) : hovering ? GlassInk.wellHover : GlassInk.well,
            in: coreShape(Radius.cardMac)
        )
        .overlay {
            coreShape(Radius.cardMac).strokeBorder(
                selected ? accent.opacity(0.7) : GlassInk.wellEdge, lineWidth: selected ? 1.5 : 1)
        }
        .shadow(color: accent.opacity(selected ? 0.45 : hovering ? 0.25 : 0), radius: 16, y: 4)
        .opacity(item.isEnded ? 0.7 : 1)
        .scaleEffect(hovering ? 1.02 : selected ? 1.01 : 1)
        .contentShape(coreShape(Radius.cardMac))
        .onTapGesture(count: 2) { TileAction.run(.open, item.id, model) }
        .onTapGesture { withAnimation(.spring(duration: 0.25)) { model.selected = item.id } }
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.3, bounce: 0.25), value: hovering)
        .animation(.spring(duration: 0.3), value: selected)
        .coreRise(shown, index)
        .onAppear { shown = true }
        .contextMenu {
            Button("Open") { TileAction.run(.open, item.id, model) }
            Button("Detach") { TileAction.run(.detach, item.id, model) }.disabled(session == nil)
            Button("Send Signal…") { TileAction.run(.signal, item.id, model) }.disabled(item.isEnded)
            Button("Rename…") { TileAction.run(.rename, item.id, model) }
            Divider()
            Button("End Terminal…", role: .destructive) { TileAction.run(.end, item.id, model) }.disabled(item.isEnded)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Terminal on \(runner), \(chip.label), \(item.cols) by \(item.rows), \(item.attached) attached"
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction(named: "Open") { TileAction.run(.open, item.id, model) }
    }

    /// The tile's actions on hover: icon tiles that bounce in, each with its key.
    private var actions: some View {
        HStack(spacing: 6) {
            mini("arrow.up.forward.app", "↩", GlassInk.blue) { TileAction.run(.open, item.id, model) }
            if !item.isEnded {
                mini("eject", "D", GlassInk.slate) { TileAction.run(.detach, item.id, model) }
                mini("bolt", "S", GlassInk.orange) { TileAction.run(.signal, item.id, model) }
                mini("stop.fill", "E", GlassInk.red) { TileAction.run(.end, item.id, model) }
            }
        }
        .padding(8)
    }

    private func mini(_ symbol: String, _ key: String, _ hue: Color, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 1) {
                Image(systemName: symbol).font(.system(size: 12, weight: .bold)).symbolEffect(.bounce, value: hovering)
                Text(key).font(.system(size: 8, weight: .bold, design: .rounded)).opacity(0.85)
            }
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(
                LinearGradient(colors: [hue, hue.opacity(0.65)], startPoint: .top, endPoint: .bottom), in: coreShape(7)
            )
            .overlay { coreShape(7).strokeBorder(.white.opacity(0.25), lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }
}

/// The tile's screen in the user's terminal theme and transparency.
private struct TileScreen: View {
    let runner: String
    let accent: Color
    let state: Color
    let label: String
    let ended: Bool
    let blink: Bool
    @Bindable private var prefs = TerminalPrefs.shared

    var body: some View {
        let t = prefs.theme
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { _ in Circle().fill(.white.opacity(0.16)).frame(width: 6, height: 6) }
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(state).frame(width: 6, height: 6)
                        .opacity(!ended && blink ? 0.4 : 1)
                        .animation(ended ? nil : .easeInOut(duration: 1.1).repeatForever(), value: blink)
                    Text(label).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 7).frame(height: 18)
                .background(.black.opacity(0.35), in: coreShape(5))
            }
            Spacer(minLength: Space.s3)
            HStack(spacing: 0) {
                Text(runner).foregroundStyle(accent)
                Text(" ~ ").foregroundStyle(Color(nsColor: t.foreground).opacity(0.7))
                Text("$ ").foregroundStyle(Color(nsColor: t.foreground))
                if ended {
                    Text("[exited]").foregroundStyle(Color(nsColor: t.foreground).opacity(0.5))
                } else {
                    Rectangle().fill(Color(nsColor: t.caret)).frame(width: 7, height: 14)
                        .opacity(blink ? 0.15 : 1)
                        .animation(.easeInOut(duration: 0.6).repeatForever(), value: blink)
                }
            }
            .font(Font(prefs.font).weight(.medium))
            .lineLimit(1)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background {
            ZStack {
                if prefs.lookBlur { coreShape(Radius.row).fill(.ultraThinMaterial).environment(\.colorScheme, .dark) }
                coreShape(Radius.row).fill(Color(nsColor: prefs.screenColor))
            }
        }
        .overlay { coreShape(Radius.row).strokeBorder(.white.opacity(0.12), lineWidth: 1) }
    }
}
