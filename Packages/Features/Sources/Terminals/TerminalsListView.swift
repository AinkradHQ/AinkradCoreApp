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
                Button("New terminal") { model.openNew() }.buttonStyle(CoreButtonStyle(.prominent, size: .small))
                    .keyboardShortcut("n", modifiers: [.command, .option])
                    .help("Open a shell on a runner (⌥⌘N)")
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
                VStack(spacing: Space.s2) {
                    Text("No terminals here").font(.system(size: MacTextSize.title, weight: .semibold))
                    Text("Open a shell on one of your runners.").foregroundStyle(palette.text2)
                    Button("New terminal") { model.openNew() }.buttonStyle(CoreButtonStyle(.prominent))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .contain)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: Space.s8 * 11), spacing: Space.s2, alignment: .top)],
                            spacing: Space.s2
                        ) {
                            ForEach(model.shown) { t in
                                TerminalTile(model: model, item: t).id(t.id)
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
        VStack(alignment: .leading, spacing: Space.s1) {
            Text("\(model.openCount) open").font(.system(size: MacTextSize.body, weight: .medium))
            let per = model.runners.filter { model.onRunner($0.id) > 0 }.map { "\($0.name) \(model.onRunner($0.id))" }
            Text(
                (per.isEmpty ? [] : [per.joined(separator: " · ") + "."]).joined()
                    + " Lists the terminals this device opened."
            )
            .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
            .fixedSize(horizontal: false, vertical: true)
            Text("No preview: the Core never stores terminal output, so a tile cannot show what is on screen.")
                .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One terminal: its runner, id, size, how long, who is attached, and the state as a badge.
struct TerminalTile: View {
    let model: TerminalsModel
    let item: TerminalItem
    @Environment(\.corePalette) private var palette
    @State private var hovering = false

    var body: some View {
        let session = model.sessions[item.id]
        let chip =
            session?.view.chip
            ?? PaneView.make(item: item, runner: model.runner(item.runner), link: .none, note: nil).chip
        let selected = model.selected == item.id
        Button {
            model.openTerminal(item.id)
        } label: {
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: "terminal").font(.system(size: MacTextSize.title))
                    .foregroundStyle(selected ? palette.navActiveInk : palette.primary)
                    .frame(width: MacSize.controlMd, height: MacSize.controlMd)
                    .background(palette.uDim, in: coreShape(Radius.control))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.s1) {
                    HStack(spacing: Space.s2) {
                        Text(model.name(of: item.runner)).font(.system(size: MacTextSize.headline, weight: .semibold))
                            .lineLimit(1)
                        if model.rang.contains(item.id) {
                            StateBadge("Bell", tone: .warn, symbol: "bell")
                        }
                        Spacer(minLength: Space.s2)
                        StateBadge(chip.label, tone: chip.tone, symbol: chip.symbol)
                    }
                    Text(item.id).font(.system(size: MacTextSize.meta, design: .monospaced))
                        .foregroundStyle(palette.text2).lineLimit(1).truncationMode(.middle)
                    HStack(spacing: Space.s2) {
                        if item.cols > 0 {
                            // The screen's shape, drawn to scale: wide terminals read wide.
                            coreShape(Radius.chip / 2).strokeBorder(palette.text2.opacity(0.6), lineWidth: 1)
                                .frame(
                                    width: Space.s5,
                                    height: Space.s5 * CGFloat(item.rows) / CGFloat(max(item.cols, 1)) * 1.6
                                )
                                .accessibilityHidden(true)
                            Text("\(item.cols)×\(item.rows)").monospacedDigit()
                        }
                        Text(item.isEnded ? "ended" : "open \(ago(item.createdAt))")
                    }
                    .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                    HStack(spacing: Space.s2) {
                        CoreSlots(used: item.attached, capacity: max(item.attached, 1))
                        Text("\(item.attached) attached").monospacedDigit()
                        Spacer(minLength: Space.s2)
                        if let session {
                            // Only terminals this Mac attached to have a strip: it is output this Mac saw.
                            TimelineView(.periodic(from: .now, by: 60)) { ctx in
                                CoreHeat(session.heat(now: ctx.date))
                                    .help("Output this Mac saw in the last hour, five minutes a cell")
                            }
                        }
                    }
                    .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected ? palette.navActive : hovering ? palette.rowHover : palette.glassCard,
                in: coreShape(Radius.row)
            )
            .overlay {
                if model.rang.contains(item.id) {
                    coreShape(Radius.row).strokeBorder(palette.tone(.warn).ink, lineWidth: 1)
                } else if selected {
                    coreShape(Radius.row).strokeBorder(palette.navActiveEdge, lineWidth: 1)
                }
            }
            .contentShape(coreShape(Radius.row))
            .opacity(item.isEnded ? 0.75 : 1)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
        .accessibilityLabel(
            "Terminal on \(model.name(of: item.runner)), \(chip.label), \(item.cols) by \(item.rows), \(item.attached) attached"
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
        .contextMenu {
            Button("Open") { model.openTerminal(item.id) }
        }
    }
}
