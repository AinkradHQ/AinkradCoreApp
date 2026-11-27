import CoreUI
import SwiftUI

/// Where a project may run: the value the Core keeps (`ProjectInfo.runner`), its words and its one line.
enum WizardRunner: String, CaseIterable {
    case auto, this_mac, home_server

    var title: String {
        switch self {
        case .auto: "Automatic"
        case .this_mac: "This Mac"
        case .home_server: "Home server"
        }
    }
    /// The line with what the Core has: "Runs here… · online" / "no Mac runner is online".
    func line(_ runners: [RunnerInfo]) -> String {
        guard self != .auto, !runners.isEmpty else { return line }
        let os = self == .this_mac ? "macos" : "linux"
        let mine = runners.filter { $0.os == os }
        let on = mine.filter(\.online)
        let kind = self == .this_mac ? "Mac" : "Linux"
        if let r = on.first { return "\(line) \(r.name) is online." }
        return mine.isEmpty ? "\(line) No \(kind) runner is paired yet." : "\(line) \(mine[0].name) is offline."
    }
    var line: String {
        switch self {
        case .auto: "Core picks the best runner each time."
        case .this_mac: "Runs here. Stops when the Mac sleeps."
        case .home_server: "Keeps running while you are away."
        }
    }
    var symbol: String {
        switch self {
        case .auto: "arrow.triangle.branch"
        case .this_mac: "laptopcomputer"
        case .home_server: "server.rack"
        }
    }
}

/// What the review step says while the Core copies the repos: one answer from the repos' own copy states.
struct WizardProgress: Equatable {
    var ready = 0
    var copying = 0
    var failed = 0
    /// Repos the Core has no copy of and is not making one: they wait for Fetch Now.
    var waiting = 0

    init(_ repos: [RepoItem]) {
        for r in repos {
            switch r.copy {
            case .ready: ready += 1
            case .fetching: copying += 1
            case .failed: failed += 1
            case .unknown: waiting += 1
            }
        }
    }

    /// Nothing is still copying: the project can be opened.
    var settled: Bool { copying == 0 }

    func title(name: String) -> String {
        if !settled { return "Creating \(name)" }
        return failed > 0 || waiting > 0 ? "Almost there" : "Your project is ready"
    }
}

extension RepoCopy {
    var isFailed: Bool { if case .failed = self { true } else { false } }
}

/// The wizard's right side: the project's card, built live from what is typed and picked. The part the current step
/// fills is lit; the rest waits a little dimmer. After Create it shows the copying.
struct WizardPreviewCard: View {
    let name: String
    let colour: ProjectColour
    let host: String?
    let repos: [String]
    let runner: WizardRunner
    let publicLink: Bool
    /// The existing Brain place picked; nil means a new one.
    let place: String?
    let kind: ProjectKind
    let step: WizardStep
    /// The repos' copy states once the project exists.
    let progress: WizardProgress?
    @Environment(\.corePalette) private var palette

    private var shownName: String {
        let t = name.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Your project" : t
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            ZStack(alignment: .bottomLeading) {
                PreviewIllustration(name: shownName, colour: colour)
                    .id(colour).transition(.opacity)
                StateBadge(
                    kind.hasPublicLink ? (publicLink ? "Public link" : "Private") : kind.short,
                    tone: kind.hasPublicLink && publicLink ? .run : .queue,
                    symbol: kind.hasPublicLink ? (publicLink ? "link" : "lock") : kind.symbol
                )
                .padding(.horizontal, Space.s2).frame(height: MacSize.controlMd)
                .coreCard(GlassInk.card, radius: Radius.control)
                .padding(Space.s2)
                .opacity(lit(.runs))
            }
            .frame(height: Space.s8 * 5)
            .clipShape(coreShape(Radius.control))
            HStack(spacing: Space.s3) {
                ProjectMark(name: shownName, colour: colour)
                VStack(alignment: .leading, spacing: 0) {
                    Text(shownName).coreFont(size: MacTextSize.title, weight: .semibold).lineLimit(1)
                        .contentTransition(.opacity)
                    Text(host ?? (kind.hasPublicLink ? "Link made from the name" : kind.title)).font(
                        .system(size: MacTextSize.meta, design: .monospaced)
                    )
                    .foregroundStyle(palette.text2).lineLimit(1).truncationMode(.middle)
                }
            }
            .opacity(lit(.name))
            section("Code", lit: lit(.code)) {
                if repos.isEmpty {
                    Text("No repos yet").foregroundStyle(palette.text2)
                } else {
                    ForEach(repos.prefix(4), id: \.self) { r in
                        Label(r, systemImage: "tray.full").lineLimit(1)
                            .transition(
                                .asymmetric(insertion: .offset(y: -6).combined(with: .opacity), removal: .opacity))
                    }
                    if repos.count > 4 { Text("and \(repos.count - 4) more").foregroundStyle(palette.text2) }
                }
            }
            section("Kind", lit: lit(.kind)) {
                Label(kind.title, systemImage: kind.symbol).lineLimit(1).contentTransition(.opacity)
            }
            section("Brain", lit: lit(.brain)) {
                Label(place ?? "New place “\(shownName)”", systemImage: place == nil ? "plus.square" : "square.stack")
                    .lineLimit(1).contentTransition(.opacity)
            }
            if kind.runs {
                section(kind == .app ? "Builds on" : "Runs on", lit: lit(.runs)) {
                    Label(runner.title, systemImage: runner.symbol).contentTransition(.opacity)
                }
            }
            if let progress, progress.ready + progress.copying + progress.failed + progress.waiting > 0 {
                let total = Double(progress.ready + progress.copying + progress.failed + progress.waiting)
                VStack(alignment: .leading, spacing: Space.s1) {
                    CoreMeter(Double(progress.ready) / total, label: "Copied")
                    Text("\(progress.ready) of \(Int(total)) repos copied").coreFont(size: MacTextSize.meta)
                        .foregroundStyle(palette.text2)
                }
                .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(width: Space.s8 * 9)
        .frame(maxHeight: .infinity, alignment: .top)
        .coreWell(radius: Radius.pane)
        .animation(Motion.out(Motion.ui), value: repos)
        .animation(Motion.out(Motion.ui), value: colour)
        .animation(Motion.out(Motion.ui), value: step)
        .animation(Motion.out(Motion.ui), value: runner)
        .animation(Motion.out(Motion.ui), value: kind)
        .animation(Motion.out(Motion.ui), value: progress)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview of \(shownName)")
    }

    /// The step being filled is full strength; review lights everything.
    private func lit(_ s: WizardStep) -> Double { step == s || step == .review ? 1 : 0.5 }

    private func section<C: View>(_ title: String, lit: Double, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(title).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
            c()
        }
        .padding(.horizontal, Space.s1)
        .opacity(lit)
    }
}

/// A big choice: glyph tile, title and one line; the chosen one fills its glyph tile with the accent and shows a check.
struct WizardChoiceTile: View {
    let symbol: String
    let title: String
    let line: String
    let selected: Bool
    let pick: () -> Void
    @Environment(\.coreAccent) private var accent
    @Environment(\.corePalette) private var palette
    @State private var hovering = false

    var body: some View {
        Button(action: pick) {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(alignment: .top) {
                    Image(systemName: symbol).coreFont(size: MacTextSize.title, weight: .semibold)
                        .foregroundStyle(selected ? .white : palette.text)
                        .frame(width: Space.s8 + Space.s1, height: Space.s8 + Space.s1)
                        .background(selected ? GlassInk.accent(accent) : GlassInk.well, in: coreShape(Radius.control))
                        .coreEnterBounce(hovering)
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark").coreFont(size: MacTextSize.meta, weight: .bold)
                            .foregroundStyle(GlassInk.accent(accent)).transition(.scale.combined(with: .opacity))
                    }
                }
                Text(title).coreFont(size: MacTextSize.body, weight: .semibold)
                Text(line).foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .coreWell(radius: Radius.cardMac, active: selected || hovering)
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(CoreQuietPressStyle())
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
        .animation(Motion.out(Motion.ui), value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The create, told as it happens: the project, its repos one by one, the Brain place and settings, then the Core copying
/// the code. Done steps show a check, the running one pulses with its own bar, later ones wait dimmed.
struct WizardSetupList: View {
    let creating: CreateProgress?
    let made: ProjectItem?
    let copy: WizardProgress?
    @Environment(\.coreAccent) private var accent
    @Environment(\.corePalette) private var palette

    private enum State { case waiting, running, done }

    var body: some View {
        let stage = creating?.stage
        let total = creating?.total ?? made?.repos.count ?? 0
        let copied = copy?.ready ?? 0
        let copyTotal = made?.repos.count ?? 0
        VStack(alignment: .leading, spacing: Space.s2) {
            row(
                "Create the project", nil, state: stage == .project ? .running : .done, value: nil,
                symbol: "square.grid.2x2")
            if total > 0 {
                let added = creating?.added ?? total
                row(
                    "Add the repos", "\(added) of \(total)",
                    state: stage == .project ? .waiting : stage == .repos ? .running : .done,
                    value: Double(added) / Double(total), symbol: "tray.full")
            }
            row(
                "Brain place and settings", nil,
                state: stage == .finishing ? .running : made != nil && creating == nil ? .done : .waiting,
                value: nil, symbol: "brain")
            if copyTotal > 0 {
                row(
                    "Copy the code", "\(copied) of \(copyTotal)",
                    state: creating != nil ? .waiting : copy?.settled == true ? .done : .running,
                    value: Double(copied) / Double(copyTotal), symbol: "arrow.down.doc")
            }
        }
        .padding(Space.s3)
        .coreWell(radius: Radius.cardMac)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Setup progress")
    }

    private func row(_ title: String, _ count: String?, state: State, value: Double?, symbol: String) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                switch state {
                case .done:
                    Image(systemName: "checkmark").coreFont(size: MacTextSize.meta, weight: .bold).foregroundStyle(
                        .white
                    )
                    .transition(.scale.combined(with: .opacity))
                case .running, .waiting:
                    Image(systemName: symbol).coreFont(size: MacTextSize.meta, weight: .semibold)
                        .foregroundStyle(state == .running ? .white : palette.text2)
                }
            }
            .frame(width: Space.s6, height: Space.s6)
            .background(
                state == .waiting ? GlassInk.well : state == .done ? palette.success : GlassInk.accent(accent),
                in: coreShape(Radius.chip)
            )
            .corePulse(state == .running)
            VStack(alignment: .leading, spacing: Space.s1) {
                HStack {
                    Text(title).coreFont(size: MacTextSize.body, weight: state == .running ? .semibold : .regular)
                    Spacer()
                    if let count {
                        Text(count).monospacedDigit().foregroundStyle(palette.text2).contentTransition(.numericText())
                    }
                }
                if state == .running, let value { CoreMeter(value, label: title).transition(.opacity) }
            }
        }
        .opacity(state == .waiting ? 0.5 : 1)
    }
}
