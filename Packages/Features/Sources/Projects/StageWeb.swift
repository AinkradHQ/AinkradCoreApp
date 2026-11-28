import AppKit
import CoreUI
import SwiftUI

/// How wide the live site is drawn in the browser frame of the stage.
enum SiteWidth: String, CaseIterable, Sendable {
    case desktop, tablet, phone
    var title: String { rawValue.capitalized }
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
                site.frame(maxWidth: .infinity, maxHeight: .infinity)
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
            Image(systemName: "arrow.clockwise").coreFont(size: 10)
        }
        .coreFont(size: MacTextSize.meta)
        .foregroundStyle(Color(red: 0.37, green: 0.35, blue: 0.32))
        .padding(.horizontal, Space.s3 - 2).frame(height: 30)
        .background(Color(red: 0.945, green: 0.937, blue: 0.918))
    }

    /// The running site (the live view, the demo page), else its last picture; a note in the corner when it cannot be opened.
    @ViewBuilder private var site: some View {
        ZStack(alignment: .bottomLeading) {
            #if DEBUG
            if running, model.demoPage {
                DemoSitePage(name: project.name, colour: model.colour(project))
            } else {
                live
            }
            #else
            live
            #endif
            if running { note }
        }
    }

    @ViewBuilder private var live: some View {
        ZStack {
            ProjectPicture(project: project, colour: model.colour(project), illustrate: false)
            if let url = previewURL {
                LiveWebView(
                    url: url, model: web, preview: model.previewFetch.map { (project.id, model.previewCoreHost, $0) }
                ).opacity(web.state == .live ? 1 : 0)
                    .animation(Motion.out(Motion.ui), value: web.state)
                    .task(id: url) { await keepSnapshot() }
            }
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
