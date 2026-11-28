import AppKit
import CoreUI
import SwiftUI

/// How wide the live site is drawn in the browser frame of the stage.
enum SiteWidth: String, CaseIterable, Sendable {
    case desktop, tablet, phone
    var title: String { rawValue.capitalized }
    /// The width the site is laid out at, as on that kind of device; the frame shrinks it to fit.
    var layoutWidth: CGFloat {
        switch self {
        case .desktop: 1920
        case .tablet: 1024
        case .phone: 390
        }
    }
    /// Share of the stage the browser takes.
    var share: CGFloat {
        switch self {
        case .desktop: 0.86
        case .tablet: 0.52
        case .phone: 0.28
        }
    }
}

/// The web stage: the live site in a browser frame whose width follows Desktop, Tablet and Phone (it glides). Not running, the
/// frame shows the last picture of the site; the stage's cover says why.
struct WebStage: View {
    let model: ProjectsModel
    let project: ProjectItem
    let width: SiteWidth
    let web: LiveWebModel
    @Environment(\.accessibilityReduceMotion) private var reduce

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

    var body: some View {
        GeometryReader { g in
            VStack(spacing: 0) {
                bar
                // Laid out at the device's width, then shrunk to the frame: a preview, not a stretched page.
                GeometryReader { f in
                    let zoom = f.size.width / width.layoutWidth
                    ZStack(alignment: .bottomLeading) {
                        // Pictures and the demo page are drawn at the device width and shrunk; the live page itself
                        // lays out at that width through its page zoom, so clicks land where they look.
                        still
                            .frame(width: width.layoutWidth, height: f.size.height / zoom, alignment: .top)
                            .scaleEffect(zoom, anchor: .topLeading)
                            .frame(width: f.size.width, height: f.size.height, alignment: .topLeading)
                        liveView(zoom: zoom)
                        if running { note }
                    }
                }
                .clipped()
            }
            .frame(width: g.size.width * width.share)
            .background(Color(red: 0.984, green: 0.98, blue: 0.965))
            .clipShape(coreShape(10))
            .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
            .padding(.vertical, Space.s3 + 2)
            .frame(maxWidth: .infinity)
            .animation(reduce ? nil : Motion.out(Motion.move), value: width)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Live site of \(project.name), \(width.title) width")
    }

    private var bar: some View {
        HStack(spacing: Space.s2) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in coreShape(2).fill(.black.opacity(0.18)).frame(width: 7, height: 7) }
            }
            HStack(spacing: 6) {
                Image(systemName: "lock").coreFont(size: 9)
                Text("\(project.link)/").lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.s2).frame(height: 20)
            .background(Color(red: 0.9, green: 0.886, blue: 0.855), in: coreShape(6))
            Button {
                web.state = .loading
                web.web?.reload()
            } label: {
                Image(systemName: "arrow.clockwise").coreFont(size: 10).frame(width: 20, height: 20).contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(previewURL == nil || isDemo).help("Reload the page")
            .accessibilityLabel("Reload the page")
        }
        .coreFont(size: MacTextSize.meta)
        .foregroundStyle(Color(red: 0.37, green: 0.35, blue: 0.32))
        .padding(.horizontal, Space.s3 - 2).frame(height: 30)
        .background(Color(red: 0.945, green: 0.937, blue: 0.918))
    }

    /// What is drawn at the device width: the demo page while it runs (Debug), else the last picture of the site.
    @ViewBuilder private var still: some View {
        #if DEBUG
        if running, model.demoPage {
            DemoSitePage(name: project.name, colour: model.colour(project))
        } else {
            ProjectPicture(project: project, colour: model.colour(project), illustrate: false)
        }
        #else
        ProjectPicture(project: project, colour: model.colour(project), illustrate: false)
        #endif
    }

    /// The live page over the picture, once it has loaded.
    @ViewBuilder private func liveView(zoom: CGFloat) -> some View {
        if let url = previewURL, !isDemo {
            LiveWebView(
                url: url, model: web, preview: model.previewFetch.map { (project.id, model.previewCoreHost, $0) },
                zoom: zoom
            ).opacity(web.state == .live ? 1 : 0)
                .animation(Motion.out(Motion.ui), value: web.state)
                .task(id: url) { await keepSnapshot() }
        }
    }

    private func keepSnapshot() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(web.state == .live ? 60 : 3))
            if web.state == .live { web.snapshot(into: project.id) }
        }
    }

    @ViewBuilder private var note: some View {
        if previewURL == nil, !isDemo {
            corner(
                "Turn on the public link to see \(project.name) live here.",
                button: model.readOnly ? nil : "Turn On Public Link"
            ) { Task { await model.setExpose(project, true) } }
        } else if let why = problem {
            corner(why, button: "Try Again") {
                web.state = .loading
                web.web?.reload()
            }
        } else if web.state == .loading, !isDemo, previewURL != nil {
            corner("Opening \(project.link)…", button: nil) {}
        }
    }

    private func corner(_ text: String, button: String?, action: @escaping () -> Void) -> some View {
        HStack(spacing: Space.s2) {
            Text(text).foregroundStyle(GlassInk.secondary).lineLimit(2)
            if let button { Button(button, action: action).buttonStyle(CoreButtonStyle(.secondary, size: .small)) }
        }
        .padding(.horizontal, Space.s3).frame(minHeight: MacSize.controlMd + Space.s1)
        .background(.background, in: coreShape(Radius.control)).padding(Space.s2)
    }
}
