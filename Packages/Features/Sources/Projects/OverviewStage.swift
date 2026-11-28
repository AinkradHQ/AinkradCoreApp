import CoreUI
import SwiftUI

/// The big island of the Overview: the project live, drawn per kind. With several kinds a switch on top picks which one the
/// stage shows (Web | App). Not running, the stage is blurred and dimmed under a cover that says where it stands.
struct OverviewStage: View {
    let model: ProjectsModel
    let project: ProjectItem
    @Binding var kind: ProjectKind?
    @State private var width = SiteWidth.desktop
    private var web: LiveWebModel { model.liveWeb(for: project.id) }

    private var kinds: [ProjectKind] { project.allKinds }
    private var view: ProjectKind { kind.flatMap { kinds.contains($0) ? $0 : nil } ?? kinds[0] }
    private var crashed: Bool { project.crash != nil && !project.stale }
    private var covered: Bool { view != .other && (project.tag != .running || crashed) }

    var body: some View {
        VStack(spacing: 0) {
            header.frame(height: Space.s8 + Space.s4).padding(.leading, Space.s4).padding(.trailing, Space.s2 + 2)
            ZStack {
                layer.id(view).transition(.opacity)
                    .blur(radius: covered ? 6 : 0).opacity(covered ? 0.9 : project.stale ? 0.6 : 1)
                if project.stale, !covered {
                    Text("Last known \(model.listAge() ?? "a while ago")").foregroundStyle(GlassInk.secondary)
                        .padding(.horizontal, Space.s3).padding(.vertical, Space.s1 + 1)
                        .coreCard(GlassInk.card, radius: Radius.control)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        // Centred and lifted: the preview's frame is inset, and a corner chip straddled its edge.
                        .padding(.bottom, Space.s6).allowsHitTesting(false)
                }
                if covered {
                    StageCover(model: model, project: project, kind: view).transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GlassInk.sunk(0.2))
            .clipShape(coreShape(Radius.cardMac))
            .padding([.horizontal, .bottom], Space.s2)
            .animation(Motion.out(Motion.ui), value: view)
            .animation(Motion.out(Motion.ui), value: covered)
            .animation(Motion.out(Motion.ui), value: project.tag)
        }
        .coreWell(radius: Radius.pane)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project-stage")
    }

    @ViewBuilder private var layer: some View {
        switch view {
        case .web: WebStage(model: model, project: project, width: width, web: web)
        case .app: AppStage(model: model, project: project)
        case .infra: InfraStage(project: project)
        case .other: DocsStageView(model: model, project: project)
        }
    }

    private var header: some View {
        HStack(spacing: Space.s3) {
            if kinds.count > 1 {
                CoreSegmented(
                    "Stage",
                    segments: kinds.map { CoreSegment($0, $0.chipName, symbol: $0.symbol) },
                    selection: Binding(get: { view }, set: { kind = $0 }))
            } else {
                Image(systemName: view.symbol).foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
                Text(title).coreFont(size: MacTextSize.headline, weight: .semibold)
            }
            Text(subtitle).foregroundStyle(GlassInk.secondary).lineLimit(1)
            Spacer(minLength: 0)
            tools
        }
    }

    private var title: String {
        switch view {
        case .web: "Live site"
        case .app: "Latest build"
        case .infra: "Service map"
        case .other: "Docs"
        }
    }

    private var subtitle: String {
        switch view {
        case .web:
            return project.expose ? "\(project.link) · public while running" : "\(project.link) · only your devices"
        case .infra:
            let s = project.live?.services ?? []
            return s.isEmpty
                ? "" : "\(s.filter { $0.state == .up && $0.health != "unhealthy" }.count) of \(s.count) healthy"
        default: return ""
        }
    }

    @ViewBuilder private var tools: some View {
        if view == .web {
            CoreSegmented(
                "Width", segments: SiteWidth.allCases.map { CoreSegment($0, $0.title) },
                selection: Binding(get: { width }, set: { width = $0 }))
            if project.expose {
                CoreIconButton(symbol: "doc.on.doc", label: "Copy the link") { model.copyLink(project) }
            }
            CoreIconButton(symbol: "arrow.up.forward.square", label: project.expose ? "Open in the browser" : "Open the live site") {
                model.openSite(project)
            }
            .disabled(project.tag != .running)
            .help(project.expose ? "Open the public link" : "Open the live site page, the private preview")
        }
    }
}
