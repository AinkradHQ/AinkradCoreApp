import CoreUI
import Projects
import SwiftUI

/// A host in the gallery (mockup 14): its tile, name and system, how it is reached and whether it is a runner.
/// Same bones as a project card (well, hover lift, rise on arrival); a tap opens the host's space.
struct HostCard: View {
    let model: LeylineModel
    let host: HostItem
    let index: Int
    let settled: Bool
    @State private var hovering = false

    private var picked: Bool { model.selection.contains(host.id) }
    private var lit: Bool {
        #if DEBUG
        let forced = model.debugHover == host.id
        #else
        let forced = false
        #endif
        return hovering || model.cursor == host.id || forced
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s3) {
                IconTile("server.rack", hue: GlassInk.blue, size: Space.s8 + Space.s2)
                VStack(alignment: .leading, spacing: 0) {
                    Text(host.name).coreFont(size: MacTextSize.title, weight: .semibold).lineLimit(1)
                    Text(host.os ?? host.login).foregroundStyle(GlassInk.secondary).lineLimit(1)
                }
                Spacer(minLength: Space.s2)
                CoreCheckbox(
                    "", isOn: Binding(get: { picked }, set: { _ in model.toggle(host.id) }),
                    spoken: "Select \(host.name)"
                )
                .help("Select for a fleet run")
            }
            HStack(spacing: Space.s2) {
                Label(route, systemImage: "arrow.triangle.turn.up.right.diamond").foregroundStyle(GlassInk.secondary)
                    .lineLimit(1)
                Spacer(minLength: Space.s2)
                Text(host.runnerDevice == nil ? "No runner" : "Runner").foregroundStyle(GlassInk.secondary)
                if lit {
                    Button {
                        model.openHost(host.id)
                    } label: {
                        Label("Open", systemImage: "arrow.right")
                    }
                    .buttonStyle(CoreButtonStyle(.prominent, size: .small)).transition(.opacity)
                }
            }
            .frame(minHeight: MacSize.controlSm)
        }
        .padding(Space.s4)
        .coreWell(radius: Radius.pane, active: lit || picked)
        .contentShape(coreShape(Radius.pane))
        .onTapGesture { model.openHost(host.id) }
        .coreScaleEffect(lit ? 1.01 : 1)
        .coreRise(settled, index)
        .animation(Motion.out(Motion.hover), value: lit)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Open") { model.openHost(host.id) }
            Button(picked ? "Deselect" : "Select") { model.toggle(host.id) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(host.name), \(host.login)")
        .coreActivates { model.openHost(host.id) }
        .accessibilityIdentifier("host-card-\(host.name)")
    }

    private var route: String { "\(host.login) · via \(model.route(host).last ?? model.coreName)" }
}

/// A card on its way: soft wells in the card's shape.
struct HostCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            CoreSkeleton(coreShape(Radius.chip)).frame(width: Space.s8 * 4, height: Space.s4)
            CoreSkeleton(coreShape(Radius.chip)).frame(width: Space.s8 * 6, height: Space.s3)
            CoreSkeleton(coreShape(Radius.cardMac)).frame(height: Space.s8 * 2)
            CoreSkeleton(coreShape(Radius.chip)).frame(width: Space.s8 * 3, height: Space.s3)
        }
        .padding(Space.s4)
        .coreWell(radius: Radius.pane)
        .accessibilityHidden(true)
    }
}
