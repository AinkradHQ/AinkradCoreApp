import Admin
import CoreUI
import SwiftUI

/// A room's AI access: the Core lets an AI session see a room only when the session's project matches it, plus whatever
/// extra allows the person names here. Changing the list asks for Touch ID.
extension BrainCandidates {
    public func loadAccess(_ room: String) async {
        guard let service, let a = try? await service.roomAccess(room: room) else { return }
        access[room] = a
    }

    @discardableResult
    func changeAccess(_ room: String, _ kind: AccessKind, to values: [String], reason: String) async -> Bool {
        guard let service, let host = brain?.host else { return false }
        do {
            let a = try await host.elevated(reason, done: "changed", keepsEdit: false) {
                try await service.setRoomAccess(room: room, kind: kind, values: values)
            }
            access[room] = a
            return true
        } catch is AdminDeclined {
            return false
        } catch {
            notice = BrainWords.failure(error)
            return false
        }
    }

    /// False when the name is empty or already there.
    public func addAccess(_ room: String, _ kind: AccessKind, _ name: String) async -> Bool {
        let v = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let a = access[room], !v.isEmpty, !a[kind].contains(v) else { return false }
        return await changeAccess(
            room, kind, to: a[kind] + [v], reason: "Let an AI session see this room: \(kind.title.lowercased()) \(v).")
    }

    public func removeAccess(_ room: String, _ kind: AccessKind, _ name: String) async {
        guard let a = access[room] else { return }
        await changeAccess(
            room, kind, to: a[kind].filter { $0 != name },
            reason: "Stop letting \(kind.title.lowercased()) \(name) see this room.")
    }
}

/// "Which AI sessions can use it?": the place's own project, the extra allows with Remove, and Allow Another Project…
/// which opens the add row. Every change asks for Touch ID.
struct RoomAISessions: View {
    let c: BrainCandidates
    let room: RoomSummary
    @State private var kind = AccessKind.project
    @State private var name = ""
    @State private var adding = false

    var body: some View {
        if let a = c.access[room.id] {
            VStack(alignment: .leading, spacing: Space.s2) {
                entry("folder", "Project “\(room.name)”", "Always, it is this place’s own project", lit: true) {
                    EmptyView()
                }
                .accessibilityIdentifier("room-ai-default")
                ForEach(a.entries, id: \.value) { e in
                    entry(Self.symbol(e.kind), "\(e.kind.title) “\(e.value)”", "Also allowed by you") {
                        Button("Remove") { Task { await c.removeAccess(room.id, e.kind, e.value) } }
                            .buttonStyle(CoreButtonStyle(.plain, size: .small))
                            .help("Stop letting \(e.kind.title.lowercased()) \(e.value) see this place.")
                    }
                    .accessibilityIdentifier("room-ai-allow-\(e.kind.rawValue)-\(e.value)")
                }
                .disabled(c.busy)
                if adding {
                    HStack(alignment: .bottom, spacing: Space.s2) {
                        CoreSelect(
                            "Also allow", selection: $kind,
                            options: AccessKind.allCases.map { CoreSelectOption($0, $0.title) }
                        )
                        .frame(width: Space.s8 * 4)
                        CoreTextField("Name", placeholder: placeholder, text: $name) { add() }
                        Button("Add", action: add).buttonStyle(CoreButtonStyle(.secondary))
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                            .help("Let this \(kind.title.lowercased()) see this place. Asks for Touch ID.")
                    }
                    .padding(.top, Space.s1)
                    .transition(.opacity)
                } else {
                    Button {
                        adding = true
                    } label: {
                        Label("Allow Another Project…", systemImage: "plus")
                    }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                    .padding(.top, Space.s1)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("room-ai-sessions")
        }
    }

    private func entry<T: View>(
        _ symbol: String, _ title: String, _ sub: String, lit: Bool = false, @ViewBuilder trailing: () -> T
    ) -> some View {
        HStack(spacing: Space.s3) {
            BrainTile(symbol: symbol, lit: lit)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).coreFont(size: MacTextSize.body).lineLimit(1)
                Text(sub).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            }
            Spacer(minLength: Space.s2)
            trailing()
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .background(GlassInk.well, in: coreShape(Radius.control + 2))
    }

    private var placeholder: String {
        switch kind {
        case .project: "A project, like shop-admin"
        case .runner: "A runner, like build-box"
        case .session: "An AI session id"
        }
    }

    private func add() {
        Task {
            if await c.addAccess(room.id, kind, name) {
                name = ""
                adding = false
            }
        }
    }

    private static func symbol(_ k: AccessKind) -> String {
        switch k {
        case .project: "folder"
        case .runner: "desktopcomputer"
        case .session: "sparkles"
        }
    }
}
