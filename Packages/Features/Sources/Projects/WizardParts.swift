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
    func line(_ runners: [RunnerInfo], kind: ProjectKind = .web) -> String {
        guard self != .auto, !runners.isEmpty else { return line(kind) }
        let os = self == .this_mac ? "macos" : "linux"
        let mine = runners.filter { $0.os == os }
        let on = mine.filter(\.online)
        let name = self == .this_mac ? "Mac" : "Linux"
        if let r = on.first { return "\(line(kind)) \(r.name) is online." }
        return mine.isEmpty
            ? "\(line(kind)) No \(name) runner is paired yet." : "\(line(kind)) \(mine[0].name) is offline."
    }
    var line: String { line(.web) }
    /// One line in the words of the kind: an app is built, the rest run.
    func line(_ kind: ProjectKind) -> String {
        if kind == .app {
            switch self {
            case .auto: return "Core picks a machine that can build it."
            case .this_mac: return "Builds here. Stops when the Mac sleeps."
            case .home_server: return "Keeps building while you are away."
            }
        }
        switch self {
        case .auto: return "Core picks the best runner each time."
        case .this_mac: return "Runs here. Stops when the Mac sleeps."
        case .home_server: return "Keeps running while you are away."
        }
    }
    var symbol: String {
        switch self {
        case .auto: "arrow.triangle.branch"
        case .this_mac: "laptopcomputer"
        case .home_server: "server.rack"
        }
    }

    /// Why this choice cannot be made now; nil when it can. A runner the Core has not paired, an Apple app on Linux, a
    /// Core that keeps one place only.
    func unavailable(kind: ProjectKind, runners: [RunnerInfo], supported: Bool, appleCode: Bool) -> String? {
        guard self != .auto else { return nil }
        if !supported { return "This Core keeps one place for now." }
        if kind == .app, appleCode, self == .home_server { return "Apple apps are built on a Mac." }
        let os = self == .this_mac ? "macos" : "linux"
        if !runners.isEmpty, !runners.contains(where: { $0.os == os }) {
            return "No \(self == .this_mac ? "Mac" : "Linux") runner is paired yet."
        }
        // Paired but offline: it cannot take a project now, so it is not offered as a choice.
        if !runners.isEmpty, !runners.contains(where: { $0.os == os && $0.online }) {
            return "The \(self == .this_mac ? "Mac" : "Linux") runner is offline."
        }
        return nil
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

    /// The header line: "Setting up Tidepool" while it works, then what is left for the person.
    func title(name: String, missed: Int = 0) -> String {
        if !settled { return "Setting up \(name)" }
        let needs = failed + waiting + missed
        return needs > 0
            ? "\(name) is ready, \(ProjectItem.count(needs, "repo")) need\(needs == 1 ? "s" : "") you"
            : "\(name) is ready"
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
    @Environment(\.corePalette) private var palette

    private var shownName: String {
        let t = name.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Atlas notes" : t
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
                .fixedSize()
                .padding(.horizontal, Space.s2).frame(height: MacSize.controlMd)
                .coreCard(GlassInk.card, radius: Radius.control)
                .padding(Space.s2)
                .opacity(lit(.review))
            }
            .frame(height: Space.s8 * 4 + Space.s2)
            .clipShape(coreShape(Radius.control))
            HStack(spacing: Space.s3) {
                ProjectMark(name: shownName, colour: colour)
                VStack(alignment: .leading, spacing: 0) {
                    Text(shownName).coreFont(size: MacTextSize.title, weight: .semibold).lineLimit(1)
                        .contentTransition(.opacity)
                    Text(host ?? (kind.hasPublicLink ? "Link made from the name" : kind.title)).font(
                        .system(size: MacTextSize.meta, design: host == nil ? .default : .monospaced)
                    )
                    .foregroundStyle(palette.text2).lineLimit(1).truncationMode(.middle)
                }
            }
            .opacity(lit(.what))
            section("Kind", lit: lit(.what)) {
                Label(kind.title, systemImage: kind.symbol).lineLimit(1).contentTransition(.opacity)
            }
            section("Code", lit: lit(.code)) {
                if repos.isEmpty {
                    Text("No repos yet").foregroundStyle(palette.text2)
                } else {
                    ForEach(repos.prefix(repos.count > 3 ? 2 : 3), id: \.self) { r in
                        Label(r, systemImage: "tray.full").lineLimit(1)
                            .transition(
                                .asymmetric(insertion: .offset(y: -6).combined(with: .opacity), removal: .opacity))
                    }
                    if repos.count > 3 { Text("and \(repos.count - 2) more").foregroundStyle(palette.text2) }
                }
            }
            section("Brain", lit: lit(.review)) {
                Label(place ?? "New room “\(shownName)”", systemImage: place == nil ? "plus.square" : "square.stack")
                    .lineLimit(1).contentTransition(.opacity)
            }
            if kind.runs {
                section(kind == .app ? "Builds on" : "Runs on", lit: lit(.review)) {
                    Label(runner.title, systemImage: runner.symbol).contentTransition(.opacity)
                }
            }
            if kind.hasPublicLink {
                section("Link", lit: lit(.review)) {
                    Label(publicLink ? "Public" : "Private", systemImage: publicLink ? "link" : "lock")
                        .contentTransition(.opacity)
                }
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

/// A big choice: glyph tile, title and one line. The chosen one fills its glyph tile with the accent, shows a check and
/// takes the nav fill; a hovered one only lifts, so the two never look alike (V-7). `why` disables it and says why.
struct WizardChoiceTile: View {
    let symbol: String
    let title: String
    let line: String
    let selected: Bool
    var why: String?
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
                        .coreEnterBounce(hovering && why == nil)
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark").coreFont(size: MacTextSize.body, weight: .bold)
                            .foregroundStyle(palette.text).frame(width: Space.s5, height: Space.s5)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                Text(title).coreFont(size: MacTextSize.body, weight: .semibold)
                Text(why ?? line).foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                selected ? palette.navActive : hovering && why == nil ? GlassInk.wellHover : GlassInk.well,
                in: coreShape(Radius.cardMac)
            )
            .opacity(why == nil ? 1 : 0.55)
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(CoreQuietPressStyle())
        .disabled(why != nil)
        .help(why ?? "")
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
        .animation(Motion.out(Motion.ui), value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension View {
    /// Scrolling content fades out at the top and bottom edge instead of being cut (V-30). The content keeps `Space.s3`
    /// of its own padding at both ends, so a list at rest is not dimmed.
    func wizardEdgeFade() -> some View {
        mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: Space.s3)
                Rectangle().fill(.black)
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: Space.s3)
            }
        }
    }
}
