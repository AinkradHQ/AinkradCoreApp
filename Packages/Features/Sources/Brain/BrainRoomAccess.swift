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

/// The "AI sessions" section of a room's Settings.
struct RoomAISessions: View {
    let c: BrainCandidates
    let room: RoomSummary
    @State private var kind = AccessKind.project
    @State private var name = ""

    var body: some View {
        if let a = c.access[room.id] {
            VStack(alignment: .leading, spacing: Space.s1) {
                HStack {
                    Text("AI sessions").coreFont(size: MacTextSize.headline, weight: .semibold)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: Space.s3)
                    Text("Changing it asks for Touch ID").coreFont(size: MacTextSize.meta)
                        .foregroundStyle(GlassInk.secondary)
                }
                .padding(.horizontal, 2)
                Text("AI sessions see this room only when their project matches it.")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    .padding(.horizontal, 2).padding(.bottom, Space.s1)
                CoreRow("Matches project: \(room.name)", subtitle: "Always on", symbol: "folder") { EmptyView() }
                    .accessibilityIdentifier("room-ai-default")
                ForEach(a.entries, id: \.value) { e in
                    CoreRow(e.value, subtitle: "Also allowed · \(e.kind.title)", symbol: Self.symbol(e.kind)) {
                        Button("Remove") { Task { await c.removeAccess(room.id, e.kind, e.value) } }
                            .buttonStyle(CoreButtonStyle(.plain, size: .small))
                            .help("Stop letting \(e.kind.title.lowercased()) \(e.value) see this room.")
                    }
                    .accessibilityIdentifier("room-ai-allow-\(e.kind.rawValue)-\(e.value)")
                }
                .disabled(c.busy)
                HStack(alignment: .bottom, spacing: Space.s2) {
                    CoreSelect(
                        "Also allow", selection: $kind,
                        options: AccessKind.allCases.map { CoreSelectOption($0, $0.title) }
                    )
                    .frame(width: Space.s8 * 4)
                    CoreTextField("Name", placeholder: placeholder, text: $name) { add() }
                    Button("Add", action: add).buttonStyle(CoreButtonStyle(.secondary))
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .help("Let this \(kind.title.lowercased()) see this room.")
                }
                .padding(.top, Space.s2)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("room-ai-sessions")
        }
    }

    private var placeholder: String {
        switch kind {
        case .project: "A project, like shop-admin"
        case .runner: "A runner, like build-box"
        case .session: "An AI session id"
        }
    }

    private func add() {
        Task { if await c.addAccess(room.id, kind, name) { name = "" } }
    }

    private static func symbol(_ k: AccessKind) -> String {
        switch k {
        case .project: "folder"
        case .runner: "desktopcomputer"
        case .session: "sparkles"
        }
    }
}
