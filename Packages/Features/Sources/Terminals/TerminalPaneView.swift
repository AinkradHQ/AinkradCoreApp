import CoreUI
import Shell
import SwiftUI

/// One terminal pane: banner and screen (or the card that stands in for it). Its actions (signal, detach, end) live in the
/// pane's tab menu.
struct TerminalPaneView: View {
    let model: TerminalsModel
    let session: TerminalSession
    @State private var signals = false
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
                        .animation(reduce ? nil : Motion.out(Motion.ui), value: v.dim)
                } else {
                    coreShape(Radius.cardMac).fill(Color(red: 3 / 255, green: 8 / 255, blue: 16 / 255).opacity(0.78))
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

/// The signals a terminal's process group can be sent: a grid of names, each one a button.
struct SignalMenu: View {
    let session: TerminalSession
    let done: () -> Void
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Signal to send").font(.system(size: MacTextSize.meta, weight: .semibold)).foregroundStyle(
                palette.text2)
            LazyVGrid(columns: [GridItem(.fixed(Space.s8 * 2.5)), GridItem(.fixed(Space.s8 * 2.5))], spacing: Space.s1)
            {
                ForEach(TerminalSignals.all, id: \.self) { name in
                    Button {
                        done()
                        Task { _ = await session.signal(name) }
                    } label: {
                        Text(name).font(.system(size: MacTextSize.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Space.s2).frame(minHeight: MacSize.controlMd)
                            .contentShape(coreShape(Radius.chip))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Send SIG\(name)")
                }
            }
            Text("Needs Touch ID. Covers this action only.").font(.system(size: MacTextSize.meta))
                .foregroundStyle(palette.text2)
        }
        .padding(Space.s3)
        .coreTheme()
    }
}
