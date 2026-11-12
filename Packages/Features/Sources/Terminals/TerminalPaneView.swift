import CoreUI
import Shell
import SwiftUI

/// One terminal pane: banner and screen (or the card that stands in for it). Its actions (running command, detach, end) live in the
/// pane's tab menu.
struct TerminalPaneView: View {
    let model: TerminalsModel
    let session: TerminalSession
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let v = session.view
        VStack(spacing: Space.s2) {
            if let b = v.banner {
                TermBanner(
                    tone: b.tone, title: b.title, detail: b.detail, busy: b.busy,
                    actionTitle: b.action.map(PaneView.label)
                ) { b.action.map(perform) }
                .transition(reduce ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
            ZStack {
                if v.screenVisible {
                    TerminalScreen(surface: session.surface).opacity(v.dim ? 0.5 : 1)
                        // Settings, Terminal, Transparency: frost what shows through a see-through terminal.
                        .background {
                            if TerminalPrefs.shared.lookBlur {
                                // Dark frost in both themes: the terminal stays dark by day.
                                Rectangle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                            }
                        }
                        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: v.dim)
                } else {
                    // The terminal stays dark by day: the night surface, at least 0.85 so the light glass under it
                    // does not wash it grey.
                    AppSurfaceFill(
                        style: TerminalPrefs.app(TerminalPrefs.shared.lookScreen),
                        opacity: palette.isDay
                            ? max(0.85, TerminalPrefs.shared.lookOpacity) : TerminalPrefs.shared.lookOpacity,
                        blur: TerminalPrefs.shared.lookBlur
                    )
                    .environment(\.corePalette, .night)
                    .accessibilityHidden(true)
                }
                if let c = v.card {
                    ZStack {
                        // The prototype's veil: deep blue at half strength, the same in night and day.
                        coreShape(Radius.cardMac).fill(
                            Color(red: 6 / 255, green: 12 / 255, blue: 24 / 255).opacity(0.5))
                        TermCard(
                            title: c.title, text: c.body, note: c.note,
                            actions: c.actions.map { a in
                                (
                                    title: PaneView.label(a), primary: a != .closePane && a != .dismiss,
                                    run: { perform(a) }
                                )
                            }
                        )
                        .padding(Space.s5)
                    }
                    .background(.ultraThinMaterial, in: coreShape(Radius.cardMac))
                    .environment(\.colorScheme, .dark)
                    .transition(.opacity)
                }
            }
            .clipShape(coreShape(Radius.cardMac))
            .accessibilityElement(children: .contain)
        }
        // No margin of its own: the pane frame gives the same space on every side.
        .coreAnimation(Motion.out(Motion.move), value: v)
        .onDisappear { model.paneClosed(session.id) }
        .accessibilityIdentifier("terminal-pane-\(session.id)")
    }

    private func perform(_ a: PaneAction) {
        switch a {
        case .attach, .verify: Task { await session.attach() }
        case .retry:
            Task {
                await model.reload()
                await session.attach()
            }
        case .runner: model.openRunners(session.item.runner)
        case .dismiss: session.dismissNote()
        case .closePane: model.closePane(session.id)
        case .newTerminal: model.openNew(runner: session.item.runner)
        }
    }
}
