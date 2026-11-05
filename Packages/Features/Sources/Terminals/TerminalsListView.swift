import CoreUI
import SwiftUI

/// The Terminals pane: the filter, a tile per terminal, and a footer that counts what is open. No preview: the Core never
/// stores terminal output, so a tile cannot show what is on screen.
struct TerminalsListView: View {
    let model: TerminalsModel
    @Environment(\.corePalette) private var palette
    @FocusState private var listFocus: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.s2) {
                CoreSegmented(
                    "Filter terminals", segments: TerminalFilter.allCases.map { CoreSegment($0, $0.rawValue) },
                    selection: Binding(get: { model.filter }, set: { model.filter = $0 }))
                Spacer(minLength: Space.s2)
                AppearanceButton()
                Button {
                    model.quickNew()
                } label: {
                    Label("New", systemImage: "plus")
                }
                .buttonStyle(CoreButtonStyle(.prominent, size: .small))
                .keyboardShortcut("n", modifiers: [.command, .option])
                .help("New terminal with the defaults (⌥⌘N); ⌥⌘T for the advanced sheet")
            }
            .padding(.horizontal, Space.s4).padding(.bottom, Space.s2)
            content
            footer
        }
    }

    @ViewBuilder private var content: some View {
        switch model.load {
        case .failed(let message):
            ConnectionBanner(.error(message), retry: { Task { await model.reload() } }).padding(.horizontal, Space.s3)
            Spacer(minLength: 0)
        case .idle where model.items.isEmpty, .loading where model.items.isEmpty:
            BusyBar().padding(Space.s4)
            Spacer(minLength: 0)
        default:
            if model.shown.isEmpty {
                VStack(spacing: Space.s3) {
                    IconTile("terminal", hue: GlassInk.slate, size: 64)
                    Text("No terminals here").font(.system(size: MacTextSize.title, weight: .semibold))
                    Text("Open a shell on one of your runners.").foregroundStyle(GlassInk.secondary)
                    Button("New terminal") { model.quickNew() }.buttonStyle(CoreButtonStyle(.prominent))
                        .coreShortcut(.primary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .contain)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: Space.s8 * 10), spacing: Space.s3, alignment: .top)],
                            spacing: Space.s3
                        ) {
                            ForEach(Array(model.shown.enumerated()), id: \.element.id) { i, t in
                                TerminalTile(model: model, item: t, index: i).id(t.id)
                            }
                        }
                        .padding(.horizontal, Space.s3)
                    }
                    .focusable()
                    .focused($listFocus)
                    .focusEffectDisabled()
                    .onKeyPress(.downArrow) { move(1, proxy) }
                    .onKeyPress(.upArrow) { move(-1, proxy) }
                    .onKeyPress(.rightArrow) { move(1, proxy) }
                    .onKeyPress(.leftArrow) { move(-1, proxy) }
                    .onKeyPress(.return) {
                        guard let id = model.selected else { return .ignored }
                        model.openTerminal(id)
                        return .handled
                    }
                    .accessibilityLabel("Terminals")
                }
            }
        }
    }

    private func move(_ step: Int, _ proxy: ScrollViewProxy) -> KeyPress.Result {
        let rows = model.shown
        guard !rows.isEmpty else { return .ignored }
        let i = rows.firstIndex { $0.id == model.selected } ?? (step > 0 ? -1 : rows.count)
        let next = rows[min(max(i + step, 0), rows.count - 1)].id
        model.selected = next
        proxy.scrollTo(next)
        return .handled
    }

    private var footer: some View {
        let running = model.items.filter { !$0.isEnded }.count
        let ended = model.items.count - running
        return HStack(spacing: Space.s2) {
            stat("play.circle.fill", "\(running) running", GlassInk.green)
            if ended > 0 { stat("stop.circle", "\(ended) ended", GlassInk.slate) }
            ForEach(model.runners.filter { model.onRunner($0.id) > 0 }) { r in
                stat("server.rack", "\(r.name) \(model.onRunner(r.id))", GlassInk.blue)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
        .help("Terminals this device opened. The Core keeps no output, so a tile shows the shell, not its screen.")
    }

    private func stat(_ symbol: String, _ text: String, _ hue: Color) -> some View {
        HStack(spacing: Space.s1) {
            Image(systemName: symbol).foregroundStyle(hue)
            Text(text).monospacedDigit()
        }
        .font(.system(size: MacTextSize.meta, weight: .medium))
        .padding(.horizontal, Space.s2).frame(height: MacSize.controlSm + 2)
        .background(GlassInk.well, in: coreShape(Radius.chip))
    }
}

/// One terminal as a little terminal: a screen in your terminal theme and transparency with its prompt and a blinking
/// cursor, a live state glow, then its facts. Lifts on hover, rises in one after another.
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
        let rang = model.rang.contains(item.id)
        let hue: Color =
            rang
            ? GlassInk.orange
            : item.isEnded
                ? GlassInk.slate
                : chip.tone == .fail
                    ? GlassInk.red
                    : chip.tone == .warn ? GlassInk.orange : GlassInk.green
        Button {
            model.openTerminal(item.id)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                TileScreen(
                    runner: model.name(of: item.runner), label: chip.label, hue: hue, ended: item.isEnded,
                    lit: selected || hovering, blink: shown)
                // The facts.
                HStack(spacing: Space.s2) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Space.s1) {
                            Text(model.name(of: item.runner)).font(
                                .system(size: MacTextSize.headline, weight: .semibold))
                            if rang {
                                Image(systemName: "bell.fill").foregroundStyle(GlassInk.orange).symbolEffect(
                                    .bounce, value: rang)
                            }
                        }
                        Text(
                            [
                                item.cols > 0 ? "\(item.cols)×\(item.rows)" : nil,
                                item.isEnded ? "ended" : "open \(ago(item.createdAt))",
                                "\(item.attached) attached",
                            ].compactMap { $0 }.joined(separator: " · ")
                        )
                        .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary).monospacedDigit()
                    }
                    Spacer(minLength: 0)
                    if let session {
                        TimelineView(.periodic(from: .now, by: 60)) { ctx in
                            CoreHeat(session.heat(now: ctx.date))
                                .help("Output this Mac saw in the last hour, five minutes a cell")
                        }
                    }
                }
                .padding(.horizontal, Space.s1).padding(.top, Space.s2)
            }
            .foregroundStyle(GlassInk.primary)
            .padding(Space.s2)
            .background(
                selected ? .white.opacity(0.12) : hovering ? GlassInk.wellHover : GlassInk.well,
                in: coreShape(Radius.cardMac)
            )
            .overlay { if selected { coreShape(Radius.cardMac).strokeBorder(.white.opacity(0.3), lineWidth: 1) } }
            .contentShape(coreShape(Radius.cardMac))
            .opacity(item.isEnded ? 0.7 : 1)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .scaleEffect(hovering ? 1.02 : 1)
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.3, bounce: 0.25), value: hovering)
        .coreRise(shown, index)
        .onAppear { shown = true }
        .accessibilityLabel(
            "Terminal on \(model.name(of: item.runner)), \(chip.label), \(item.cols) by \(item.rows), \(item.attached) attached"
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
        .contextMenu {
            Button("Open") { model.openTerminal(item.id) }
        }
    }
}

/// The terminals' look from the Terminals screen: theme swatches, transparency, blur and font size, live on every open
/// terminal (the full set is in Settings, Terminal).
private struct AppearanceButton: View {
    @Bindable private var prefs = TerminalPrefs.shared
    @State private var open = false
    var body: some View {
        Button {
            open.toggle()
        } label: {
            Label("Appearance", systemImage: "paintpalette")
        }
        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
        .help("Theme, transparency and font of every terminal")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("Terminal appearance").font(.system(size: MacTextSize.headline, weight: .semibold))
                HStack(spacing: Space.s2) {
                    ForEach(TermTheme.all) { t in
                        Button {
                            prefs.themeID = t.id
                        } label: {
                            VStack(spacing: 4) {
                                coreShape(6).fill(Color(nsColor: t.background))
                                    .overlay(alignment: .bottomLeading) {
                                        HStack(spacing: 2) {
                                            ForEach(1..<5, id: \.self) { i in
                                                coreShape(1).fill(Color(nsColor: t.ansi[i])).frame(width: 6, height: 4)
                                            }
                                        }
                                        .padding(5)
                                    }
                                    .overlay {
                                        coreShape(6).strokeBorder(
                                            prefs.themeID == t.id ? GlassInk.blue : .white.opacity(0.2),
                                            lineWidth: prefs.themeID == t.id ? 2 : 1)
                                    }
                                    .frame(width: 54, height: 36)
                                Text(t.title).font(.system(size: 10))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                LabeledContent("Transparency") {
                    HStack {
                        Slider(
                            value: Binding(get: { 1 - prefs.opacity }, set: { prefs.opacity = 1 - $0 }), in: 0...0.6,
                            step: 0.05
                        )
                        .frame(width: 160)
                        Text("\(Int(((1 - prefs.opacity) * 100).rounded()))%").monospacedDigit().frame(
                            width: 36, alignment: .trailing)
                    }
                }
                Toggle("Blur what's behind", isOn: $prefs.blur).toggleStyle(.switch)
                LabeledContent("Font size") {
                    Stepper("\(Int(prefs.fontSize)) pt", value: $prefs.fontSize, in: 9...24)
                }
            }
            .padding(Space.s4)
            .frame(width: 360)
        }
    }
}

/// The tile's little screen: window dots, the state, and the prompt with a blinking cursor, in the terminal theme.
private struct TileScreen: View {
    let runner: String
    let label: String
    let hue: Color
    let ended: Bool
    let lit: Bool
    let blink: Bool
    @Bindable private var prefs = TerminalPrefs.shared

    var body: some View {
        let t = prefs.theme
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { _ in Circle().fill(.white.opacity(0.18)).frame(width: 7, height: 7) }
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(hue).frame(width: 7, height: 7).opacity(!ended && blink ? 0.45 : 1)
                        .animation(ended ? nil : .easeInOut(duration: 1.1).repeatForever(), value: blink)
                    Text(label).font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(hue)
            }
            Spacer(minLength: 2)
            prompt(t)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(Color(nsColor: t.background).opacity(prefs.opacity), in: coreShape(Radius.row))
        .overlay { coreShape(Radius.row).strokeBorder(hue.opacity(lit ? 0.6 : 0.25), lineWidth: 1) }
        .shadow(color: hue.opacity(lit ? 0.35 : 0.12), radius: lit ? 14 : 6)
    }

    private func prompt(_ t: TermTheme) -> some View {
        HStack(spacing: 0) {
            Text("\(runner) ").foregroundStyle(Color(nsColor: t.ansi[2]))
            Text("~ $ ").foregroundStyle(Color(nsColor: t.ansi[4]))
            if ended {
                Text("[exited]").foregroundStyle(Color(nsColor: t.foreground).opacity(0.6))
            } else {
                Rectangle().fill(Color(nsColor: t.caret)).frame(width: 7, height: 13)
                    .opacity(blink ? 0.15 : 1)
                    .animation(.easeInOut(duration: 0.6).repeatForever(), value: blink)
            }
        }
        .font(.system(size: 12, design: .monospaced))
    }
}
