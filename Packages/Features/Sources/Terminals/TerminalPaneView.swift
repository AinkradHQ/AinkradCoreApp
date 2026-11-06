import CoreUI
import Shell
import SwiftUI

/// One terminal pane: banner and screen (or the card that stands in for it). Its actions (signal, detach, end) live in the
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
                    tone: b.tone, title: b.title, detail: b.detail, busy: b.busy, help: b.help,
                    actionTitle: b.action.map(PaneView.label)
                ) { b.action.map(perform) }
                .transition(reduce ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
            ZStack {
                if v.screenVisible {
                    TerminalScreen(surface: session.surface).opacity(v.dim ? 0.5 : 1)
                        // Settings, Terminal, Transparency: frost what shows through a see-through terminal.
                        .background {
                            if TerminalPrefs.shared.lookBlur { Rectangle().fill(.ultraThinMaterial) }
                        }
                        .animation(reduce ? nil : Motion.out(Motion.ui), value: v.dim)
                } else {
                    AppSurfaceFill(
                        style: TerminalPrefs.app(TerminalPrefs.shared.lookScreen),
                        opacity: TerminalPrefs.shared.lookOpacity, blur: TerminalPrefs.shared.lookBlur
                    )
                    .accessibilityHidden(true)
                }
                if let c = v.card {
                    ZStack {
                        coreShape(Radius.cardMac).fill(TerminalInk.veil)
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
        // The pane's drag grip rides over the top edge; keep the first line clear of it.
        .padding(.top, Space.s3)
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
