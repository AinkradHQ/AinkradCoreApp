import AppKit
import CoreUI
import SwiftUI

/// The Live site focused page (details v2): the live web view full size at Desktop, Tablet or Phone width, and an inspector
/// island on the right with the link, the public switch and the idle stop. A project that is not running shows the same
/// state cover idea as the Overview: one start button, or the real reason and what to do.
struct ModuleLiveSite: View {
    let model: ProjectsModel
    let project: ProjectItem
    private var web: LiveWebModel { model.liveWeb(for: project.id) }
    @State private var device = Device.desktop
    @State private var stageKind: ProjectKind? = .web
    @Environment(\.accessibilityReduceMotion) private var reduce

    enum Device: String, CaseIterable, Hashable {
        case desktop = "Desktop"
        case tablet = "Tablet"
        case phone = "Phone"
        var width: CGFloat? {
            switch self {
            case .desktop: nil
            case .tablet: 820
            case .phone: 390
            }
        }
    }

    private var running: Bool { project.tag == .running }
    private var previewURL: URL? { model.previewURL(for: project) }
    private var isDemo: Bool {
        #if DEBUG
        model.demoPage
        #else
        false
        #endif
    }
    private var problem: String? {
        #if DEBUG
        if let d = model.demoPreviewProblem { return d }
        #endif
        if case .failed(let why) = web.state { return why }
        return nil
    }
    private var can: Bool { model.canControl(project) && project.startBlock == nil }

    var body: some View {
        // The approved details v2 page: the Overview's stage, full height (browser frame, widths, covers), and the inspector.
        HStack(alignment: .top, spacing: Space.s4) {
            OverviewStage(model: model, project: project, kind: $stageKind)
            inspector.frame(width: 340)
        }
        .accessibilityIdentifier("project-page-Live site")
    }

    // MARK: stage

    private var stageIsland: some View {
        ModulePage(
            title: project.link, sub: project.expose ? "public" : "only your devices",
            tools: {
                CoreSegmented(
                    "Width", segments: Device.allCases.map { CoreSegment($0, $0.rawValue) },
                    selection: Binding(get: { device }, set: { device = $0 })
                )
                .disabled(!showsSite).help("Show the site at the width of a desktop, a tablet or a phone")
                CoreIconButton(symbol: "doc.on.doc", label: "Copy the link") { model.copyLink(project) }
                    .disabled(!project.expose).help(
                        project.expose ? "Copy the link" : "Turn the public link on to copy it")
                CoreIconButton(symbol: "arrow.up.forward.square", label: "Open in the browser") {
                    if let u = URL(string: "https://\(project.link)") { NSWorkspace.shared.open(u) }
                }
                .disabled(!running || !project.expose)
                .help(project.expose ? "Open the public link" : "Turn the public link on to open it in the browser")
            }
        ) {
            GeometryReader { geo in
                ZStack {
                    Color.clear.coreCard(GlassInk.well, radius: Radius.cardMac)
                    if showsSite {
                        site.frame(width: min(geo.size.width, device.width ?? geo.size.width))
                            .clipShape(coreShape(Radius.cardMac))
                            .padding(.vertical, Space.s2)
                            .animation(reduce ? .none : Motion.out(Motion.move), value: device)
                    }
                    cover.id(coverKey).transition(.opacity)
                }
                .animation(Motion.out(Motion.ui), value: coverKey)
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(maxHeight: .infinity).padding(.horizontal, Space.s2).padding(.bottom, Space.s2)
        }
        .animation(Motion.out(Motion.ui), value: device)
    }

    /// The live page is behind the cover only while it runs and can be opened from here.
    private var showsSite: Bool { running && (previewURL != nil || isDemo) && problem == nil }

    @ViewBuilder private var site: some View {
        #if DEBUG
        if isDemo {
            DemoSitePage(name: project.name, colour: model.colour(project))
        } else {
            live
        }
        #else
        live
        #endif
    }

    @ViewBuilder private var live: some View {
        if let url = previewURL {
            LiveWebView(
                url: url, model: web, preview: model.previewFetch.map { (project.id, model.previewCoreHost, $0) }
            )
            .opacity(web.state == .live ? 1 : 0)
            .animation(Motion.out(Motion.ui), value: web.state)
        }
    }

    private var coverKey: String { "\(project.tag) \(problem != nil) \(previewURL == nil) \(web.state == .loading)" }

    // MARK: state cover

    @ViewBuilder private var cover: some View {
        if running {
            if let why = problem {
                card(
                    "exclamationmark.triangle", "Could not open \(project.name)", why, "Try Again", true
                ) {
                    web.state = .loading
                    web.web?.reload()
                }
            } else if previewURL == nil && !isDemo {
                card(
                    "eye.slash", "\(project.name) is running", "Turn on the public link to see it live here.",
                    model.readOnly ? nil : "Turn On Public Link", true
                ) { Task { await model.setExpose(project, true) } }
            } else if web.state == .loading && !isDemo {
                Text("Opening \(project.link)…").foregroundStyle(GlassInk.secondary)
            }
        } else {
            switch project.tag {
            case .starting: starting
            case .failed: failed
            case .stopped: stopped
            default: setup
            }
        }
    }

    private func card(
        _ symbol: String, _ title: String, _ line: String, _ button: String?, _ prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: symbol).coreFont(size: MacTextSize.large, weight: .semibold)
                .foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
            Text(title).coreFont(size: MacTextSize.title, weight: .semibold).multilineTextAlignment(.center)
            Text(line).foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: Space.s8 * 11)
            if let button {
                Button(button, action: action).buttonStyle(CoreButtonStyle(prominent ? .prominent : .secondary))
                    .padding(.top, Space.s1)
            }
        }
        .padding(Space.s5)
    }

    private var stopped: some View {
        VStack(spacing: Space.s2) {
            Text("\(project.name) is stopped").coreFont(size: MacTextSize.large, weight: .semibold)
            if let why = project.live?.stopWords { PgQuiet(why).multilineTextAlignment(.center) }
            PgQuiet("Start it to open it at \(project.link).")
            Button {
                model.control(.start, project)
            } label: {
                Label(project.mainAction().title, systemImage: "play")
            }
            .buttonStyle(CoreButtonStyle(.prominent)).disabled(!can)
            .help(can ? "Start \(project.name)" : project.startBlock ?? ProjectSpaceCopy.cannot)
            .padding(.top, Space.s1)
        }
        .frame(maxWidth: Space.s8 * 12)
    }

    private var starting: some View {
        VStack(spacing: Space.s3) {
            Text("Starting \(project.name)").coreFont(size: MacTextSize.large, weight: .semibold)
            if let p = project.live?.progress {
                CoreMeter(p, label: "Starting \(project.name)").frame(width: Space.s8 * 13)
            } else {
                CoreWorkingBar(width: Space.s8 * 13)
            }
            PgQuiet(project.live?.progressLine ?? "Starting…")
            StartStepsList(steps: project.live?.steps ?? [])
        }
    }

    private var failed: some View {
        VStack(spacing: Space.s4) {
            CoreNotice(
                symbol: "exclamationmark.triangle", title: project.live?.failure ?? "The last start failed.",
                text: project.live?.failureFix ?? "", tone: .fail
            )
            .frame(maxWidth: Space.s8 * 14)
            StartStepsList(steps: project.live?.steps ?? [])
            HStack(spacing: Space.s2) {
                Button {
                    model.go(.logs, in: project.id)
                } label: {
                    Label("Show Log", systemImage: "text.alignleft")
                }
                .buttonStyle(CoreButtonStyle(.secondary)).help("Open the log of the last run")
                Button {
                    model.control(.start, project)
                } label: {
                    Label("Start Again", systemImage: "play")
                }
                .buttonStyle(CoreButtonStyle(.prominent)).disabled(!can)
                .help(can ? "Start \(project.name) again" : project.startBlock ?? ProjectSpaceCopy.cannot)
            }
        }
    }

    private var setup: some View {
        card(
            "square.stack.3d.up", "\(project.name) is not set up to run yet",
            "Add its repos and a setup from the Overview, then start it here.", "Go to Overview", false
        ) { model.go(.overview, in: project.id) }
    }

    // MARK: inspector

    private var inspector: some View {
        ModulePage(title: "Live site", tools: { EmptyView() }) {
            VStack(alignment: .leading, spacing: 0) {
                PgBlock("Link") {
                    HStack(spacing: Space.s2) {
                        runsMono(project.link)
                        Spacer(minLength: 0)
                        CoreIconButton(symbol: "doc.on.doc", label: "Copy the link") { model.copyLink(project) }
                            .disabled(!project.expose).help(
                                project.expose ? "Copy the link" : "Turn the public link on to copy it")
                    }
                    HStack(alignment: .center, spacing: Space.s2) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Public")
                            Text(
                                project.expose
                                    ? "Anyone with the link can open it while it runs"
                                    : "Off: only your devices can open it"
                            )
                            .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        CoreSwitch(
                            "",
                            isOn: Binding(
                                get: { project.expose }, set: { on in Task { await model.setExpose(project, on) } })
                        )
                        .disabled(model.readOnly || model.exposing.contains(project.id)).accessibilityLabel("Public")
                    }
                }
                PgBlock("Stops by itself") { idle }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.s5).frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder private var idle: some View {
        let l = project.limits
        if l.idleNever {
            PgQuiet("Never. It runs until you stop it.")
        } else if running, let i = BuildWords.idle(project.live?.idle) {
            PgQuiet("After \(l.idleMinutes) idle minutes · idle \(i.now) min now")
            CoreMeter(Double(i.now) / Double(max(i.of, 1)), label: "Idle time until it stops")
        } else {
            PgQuiet("After \(l.idleMinutes) idle minutes with no visits.")
        }
    }
}

/// Words shared by the pages of details v2.
enum ProjectSpaceCopy {
    static let cannot = "Not available while this device cannot change projects or the Core is unreachable"
}
