import CoreUI
import SwiftUI

/// CN3: what agents may do with one connection, and which repositories or projects it reaches. No people list until the
/// Core has more than one member (KAN-294). Turning on a change warns in one line; Save then goes through Touch ID.
struct AccessSheet: View {
    let model: ConnectionsModel
    let item: ConnItem
    let close: () -> Void
    @State private var allowed: Set<String> = []
    @State private var limit = Scope.all
    @State private var chosen: Set<String> = []
    @State private var resources: [String] = []

    enum Scope: Hashable, Sendable { case all, some }

    var body: some View {
        let k = model.kind(item.kind)
        let res = k?.resource ?? "places"
        let writes = k?.capabilities.contains { $0.writes && allowed.contains($0.id) } ?? false
        CoreDialogPanel(item.name, width: Space.s8 * 17) {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("What your agents may do with \(item.identity).").foregroundStyle(GlassInk.secondary)
                CoreFieldLabel("What agents may do")
                ForEach(k?.capabilities ?? []) { c in
                    HStack(spacing: Space.s3) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(c.title).coreFont(size: MacTextSize.body, weight: .semibold)
                            Text(c.say).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                        }
                        Spacer()
                        GlassToggleTile(
                            allowed.contains(c.id) ? "On" : "Off", symbol: "togglepower", onSymbol: "power",
                            isOn: Binding(
                                get: { allowed.contains(c.id) },
                                set: { on in
                                    withAnimation(.smooth(duration: 0.2)) {
                                        if on { allowed.insert(c.id) } else { allowed.remove(c.id) }
                                    }
                                })
                        )
                        .frame(width: Space.s8 * 4)
                    }
                    .padding(Space.s3)
                    .background(GlassInk.well, in: coreShape(Radius.cardMac))
                    .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
                }
                if writes {
                    Label(
                        "Agents will be able to change things on \(k?.name ?? "it") as you. Saving needs Touch ID.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.orangeInk)
                    .transition(.opacity)
                }
                CoreSegmented(
                    "Which \(res)",
                    segments: [CoreSegment(Scope.all, "All \(res)"), CoreSegment(Scope.some, "Only these")],
                    selection: $limit)
                if limit == .some {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: Space.s1
                    ) {
                        ForEach(resources, id: \.self) { r in
                            CoreCheckbox(
                                r,
                                isOn: Binding(
                                    get: { chosen.contains(r) },
                                    set: { on in if on { chosen.insert(r) } else { chosen.remove(r) } }), mono: true)
                        }
                    }
                    .padding(Space.s3)
                    .background(GlassInk.well, in: coreShape(Radius.cardMac))
                    .transition(.opacity)
                }
                if let e = model.writeError["access-\(item.id)"] { AccIssue(text: e) }
                AccDialogButtons(confirm: "Save", busy: model.busy == "access-\(item.id)", cancel: close) {
                    let only = limit == .all ? nil : resources.filter(chosen.contains)
                    Task { if await model.setAccess(item, allowed: allowed, only: only) { close() } }
                }
            }
            .animation(.smooth(duration: 0.25), value: limit)
        }
        .task {
            allowed = item.allowed
            limit = item.only == nil ? .all : .some
            chosen = Set(item.only ?? [])
            resources = (try? await model.service?.resources(item.id)) ?? []
        }
        .accessibilityIdentifier("connection-access")
    }
}
