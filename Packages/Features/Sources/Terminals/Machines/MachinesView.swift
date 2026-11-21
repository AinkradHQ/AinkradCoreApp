import CoreUI
import SwiftUI

/// Machines (Machines review 2026-11-21, direction A): one list of every computer and phone of the Core. Two groups, Does
/// work and Signs in only; one plain line and one status per machine; a problem rises to one line on top. A machine's page
/// opens in place and Escape comes back. Keys: ↑ ↓ move, ⏎ opens (the problem when no row is picked), ⌘N Add machine.
struct MachinesView: View {
    @Bindable var model: TerminalsModel
    @FocusState private var listFocus: Bool
    @Environment(\.corePalette) private var palette
    @Environment(\.coreAccent) private var paneAccent

    /// One column, as wide as the mockup's, centred in a wide pane.
    static let column = Space.s8 * 33

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s6) {
                    if let id = model.machineDetail {
                        page(id)
                    } else {
                        list
                    }
                }
                .frame(maxWidth: Self.column, alignment: .leading)
                .padding(.horizontal, Space.s6).padding(.top, Space.s6).padding(.bottom, Space.s4)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.automatic)
            .focusable(model.machineDetail == nil)
            .focused($listFocus)
            .focusEffectDisabled()
            .onKeyPress(.downArrow) { move(1) }
            .onKeyPress(.upArrow) { move(-1) }
            .onKeyPress(.return) { openSelected() }
            footer
        }
        .onAppear { listFocus = true }
        .task {
            // Load and heartbeats move without events: look again while Machines is open (faster while a tool installs).
            await model.host.runnerHost?.reloadSignInMachines()
            while !Task.isCancelled {
                model.readLocalInstall()
                let installing = model.runners.contains { model.runningInstall($0.id) != nil }
                try? await Task.sleep(for: .seconds(installing ? 2 : 10))
                await model.reload()
                await model.host.runnerHost?.reloadSignInMachines()
            }
        }
        .onChange(of: model.runners) { old, now in
            // A machine that was removed closes its page.
            if let id = model.machineDetail, old.contains(where: { $0.id == id }), !now.contains(where: { $0.id == id })
            {
                model.machineDetail = nil
            }
        }
        .accessibilityIdentifier("machines")
    }

    private func page(_ id: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            back
            if let r = model.runner(id) {
                MachinePage(model: model, runner: r)
            } else {
                model.host.runnerHost?.signInPage(id) { model.machineDetail = nil } ?? AnyView(EmptyView())
            }
        }
    }

    private var back: some View {
        Button {
            model.machineDetail = nil
        } label: {
            Label("Machines", systemImage: "chevron.left")
        }
        .buttonStyle(CoreButtonStyle(.plain, size: .small))
        .keyboardShortcut(.cancelAction).environment(\.coreKeycap, "esc")
        .help("Back to every machine (esc)")
    }

    // MARK: the list

    private var signIns: [SignInMachine] { model.signInMachines ?? [] }
    private var rowIDs: [String] { model.workingMachines.map(\.id) + signIns.map(\.id) }

    @ViewBuilder private var list: some View {
        header
        switch model.load {
        case .failed(let message):
            CoreStateCard(
                symbol: "wifi.slash", title: "Your Core is not answering",
                line:
                    "Machines come from your Core. Nothing was lost; the list comes back when the Core does.",
                primary: CoreAction("Try again", key: .primary) { Task { await model.reload() } }
            )
            .frame(maxWidth: .infinity)
            .help(message)
        case .idle where model.runners.isEmpty, .loading where model.runners.isEmpty:
            CoreBusyBar().frame(maxWidth: Space.s8 * 5)
        default:
            if model.runners.isEmpty && signIns.isEmpty {
                empty
            } else {
                if let p = model.problem { problemLine(p) }
                group("Does work") {
                    if model.workingMachines.isEmpty {
                        Text("Nothing does work yet. Add machine (⌘N) and pick This Mac or a server.")
                            .foregroundStyle(palette.text2).padding(.horizontal, Space.s4)
                    }
                    ForEach(model.workingMachines) { r in runnerRow(r) }
                }
                if !signIns.isEmpty {
                    group("Signs in only") { ForEach(signIns) { d in signInRow(d) } }
                }
                if model.pool?.decisionsOff == true {
                    Text("Smart job routing is off until a Google account is in the AI order.")
                        .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                        .help("Until then, a command no rule knows runs where you typed it.")
                }
            }
        }
    }

    /// "Machines", one sentence of what is going on, and Add machine.
    private var header: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Machines").coreFont(size: MacTextSize.large + 8, weight: .bold).accessibilityAddTraits(.isHeader)
                Text(summary).foregroundStyle(palette.text2)
            }
            Spacer(minLength: Space.s3)
            Button {
                model.host.runnerHost?.addMachine(.pick)
            } label: {
                Label("Add machine", systemImage: "plus")
            }
            .buttonStyle(CoreButtonStyle(.prominent))
            .keyboardShortcut("n", modifiers: .command).environment(\.coreKeycap, "⌘N")
            .help("Add a computer that does work, or a phone that signs in (⌘N)")
        }
    }

    private var summary: String {
        if case .failed = model.load { return "Not connected to your Core right now." }
        return Machines.summary(model.runners, signIns: signIns.count)
    }

    private func problemLine(_ p: MachineProblem) -> some View {
        CoreNotice(symbol: "exclamationmark.triangle", title: p.title, text: p.text, tone: .fail) {
            Button("See why") { model.machineDetail = p.machine }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                .environment(\.coreKeycap, model.machineSelected == nil ? "⏎" : nil)
                .help("Open \(p.title.components(separatedBy: " is ").first ?? "the machine") to see what to do")
        }
        .accessibilityIdentifier("machines-problem")
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ rows: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(title).coreFont(size: MacTextSize.body, weight: .semibold).foregroundStyle(palette.text2)
                .padding(.bottom, Space.s2).accessibilityAddTraits(.isHeader)
            rows()
        }
    }

    private func runnerRow(_ r: RunnerItem) -> some View {
        let status = MachineStatus(r)
        let busy = model.busy(r)
        return MachineRow(
            symbol: model.icon(r), hue: MachineHue.of(status, palette, accent: GlassInk.accent(paneAccent)),
            name: model.machineName(r), line: model.line(r),
            status: status, busy: busy, warn: (busy ?? 0) >= 0.85, selected: model.machineSelected == r.id
        ) { open(r.id) }
        .help("Open \(model.machineName(r))")
    }

    private func signInRow(_ d: SignInMachine) -> some View {
        let seen = d.lastSeen.map { "Last seen " + $0.formatted(.relative(presentation: .named)) } ?? "Not seen yet"
        return MachineRow(
            symbol: d.symbol, hue: MachineHue.of(.signedIn, palette, accent: GlassInk.accent(paneAccent)),
            name: d.isThisMac ? "This Mac" : d.name,
            line: d.isThisMac ? "Signs in here · does no work" : seen, status: .signedIn, busy: nil, warn: false,
            selected: model.machineSelected == d.id
        ) { open(d.id) }
        .help("Open \(d.name)")
    }

    private var empty: some View {
        CoreStateCard(
            symbol: "desktopcomputer", title: "Add your first machine",
            line:
                "A machine does work for your Core, like this Mac or a server, or signs in to it, like your phone. Ainkrad installs the AI tools on it for you.",
            primary: CoreAction("Add machine", key: .primary) { model.host.runnerHost?.addMachine(.pick) }
        )
        .frame(maxWidth: .infinity).padding(.top, Space.s8 * 2)
        .accessibilityIdentifier("machines-empty")
    }

    private var footer: some View {
        HStack(spacing: Space.s4) {
            if model.machineDetail == nil {
                hint("↑ ↓", "Move")
                hint("⏎", "Open")
            } else {
                hint("esc", "Back")
            }
            hint("⌘N", "Add machine")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
    }

    private func hint(_ keys: String, _ what: String) -> some View {
        HStack(spacing: Space.s2) {
            CoreKeycap(keys)
            Text(what).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: keys

    private func open(_ id: String) {
        model.machineSelected = id
        model.machineDetail = id
    }

    private func move(_ step: Int) -> KeyPress.Result {
        guard model.machineDetail == nil, !rowIDs.isEmpty else { return .ignored }
        let i = rowIDs.firstIndex { $0 == model.machineSelected } ?? (step > 0 ? -1 : rowIDs.count)
        model.machineSelected = rowIDs[min(max(i + step, 0), rowIDs.count - 1)]
        return .handled
    }

    private func openSelected() -> KeyPress.Result {
        guard model.machineDetail == nil else { return .ignored }
        guard let id = model.machineSelected ?? model.problem?.machine else { return .ignored }
        model.machineDetail = id
        return .handled
    }
}

/// The colour of a machine's tile, from its one status.
enum MachineHue {
    static func of(_ s: MachineStatus, _ palette: Palette, accent: Color) -> Color {
        switch s {
        case .working: palette.tone(.run).ink
        case .idle: GlassInk.slate
        case .notAnswering: palette.tone(.warn).ink
        case .offline: palette.tone(.fail).ink
        case .signedIn: accent
        }
    }
}

extension TerminalsModel {
    /// A Mac's laptop, a server's chip, this Core's own runner a diamond.
    func icon(_ r: RunnerItem) -> String {
        if r.builtIn { return "diamond" }
        let mac = r.id == thisMacID || (r.os ?? "").lowercased().contains("mac")
        return mac ? "laptopcomputer" : "cpu"
    }
}

/// One machine on one line: tile, name and what it is doing, how busy it is, the status, a chevron. No well at rest; hover
/// and the picked row get the quiet row fill.
struct MachineRow: View {
    let symbol: String
    let hue: Color
    let name: String
    let line: String
    let status: MachineStatus
    let busy: Double?
    let warn: Bool
    let selected: Bool
    let open: () -> Void
    @State private var hovering = false
    @Environment(\.corePalette) private var palette

    var body: some View {
        Button(action: open) {
            HStack(spacing: Space.s4) {
                IconTile(symbol, hue: hue, size: Space.s8 + Space.s1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                    Text(line).coreFont(size: MacTextSize.body).foregroundStyle(palette.text2).lineLimit(1)
                        .truncationMode(.tail).help(line)
                }
                Spacer(minLength: Space.s4)
                if let busy {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        CoreMeter(busy, low: warn, label: "\(name) busy")
                        Text("\(Int((busy * 100).rounded()))% busy").coreFont(size: MacTextSize.meta)
                            .foregroundStyle(palette.text2).monospacedDigit().contentTransition(.numericText())
                    }
                    .frame(width: Space.s8 * 4)
                }
                StateBadge(status.rawValue, tone: status.tone, symbol: "circle")
                    .frame(width: Space.s8 * 3, alignment: .trailing)
                Image(systemName: "chevron.right").imageScale(.small).foregroundStyle(palette.text2)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected ? palette.navActive : hovering ? palette.rowHover : .clear, in: coreShape(Radius.row)
            )
            .opacity(status == .offline && !hovering ? 0.8 : 1)
            .contentShape(coreShape(Radius.row))
        }
        .buttonStyle(.coreQuietPress)
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
        .accessibilityLabel("\(name), \(status.rawValue). \(line)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
