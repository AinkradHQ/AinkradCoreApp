import CoreUI
import Shell
import SwiftUI

/// What an unconnected Mac shows instead of data: never a made-up list.
struct NotConnectedNote: View {
    let what: String
    @Environment(\.corePalette) private var palette
    var body: some View {
        Label("\(what) come from your Core. This Mac is not connected to one right now.", systemImage: "wifi.slash")
            .foregroundStyle(palette.text2)
    }
}

struct LoadNote: View {
    let state: LoadState
    let retry: () -> Void
    @Environment(\.corePalette) private var palette
    var body: some View {
        switch state {
        case .loading:
            VStack(alignment: .leading, spacing: Space.s1) {
                CoreBusyBar().frame(maxWidth: Space.s8 * 5)
                Text("Loading…").foregroundStyle(palette.text2)
            }
            .accessibilityElement(children: .combine)
        case .failed(let m):
            ConnectionBanner(.error(m), retry: retry)
        default: EmptyView()
        }
    }
}

struct OnlyAdminWarning: View {
    @Environment(\.coreAccent) private var paneAccent
    let app: AppModel
    let device: DeviceInfo
    /// The device that could become the second admin; nil when none can.
    let next: DeviceInfo?

    var body: some View {
        CoreNotice(
            symbol: "shield", title: "Only one device can approve things",
            text: "Make a second device an admin so you are never locked out.", tone: .warn
        ) {
            if let next {
                AppActionTile(
                    title: "Make \(next.name) an admin", symbol: "shield", key: "", hue: GlassInk.accent(paneAccent)
                ) {
                    Task { _ = await app.devices.setScopes(next, DeviceRole.withAdmin(next.scopes)) }
                }
            } else {
                AppActionTile(title: "Add an admin device", symbol: "plus", key: "", hue: GlassInk.accent(paneAccent)) {
                    app.openAddDevice(admin: true)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("only-admin")
    }
}

/// What a device may do, in one sentence (mockup 12): Admin, Member or Viewer, from the scopes it holds.
struct DeviceRole: Equatable {
    let title: String
    let line: String
    let symbol: String

    init(scopes: [String]) {
        if scopes.contains("admin") {
            self = DeviceRole(
                title: "Admin", line: "Can approve things, use your accounts and manage devices", symbol: "shield")
        } else if scopes.contains(where: { ["approve", "terminal", "agent", "runner"].contains($0) }) {
            self = DeviceRole(title: "Member", line: Self.memberLine(scopes), symbol: "person")
        } else {
            self = DeviceRole(title: "Viewer", line: "Can only look. It can't change anything", symbol: "eye")
        }
    }

    private init(title: String, line: String, symbol: String) {
        self.title = title
        self.line = line
        self.symbol = symbol
    }

    private static func memberLine(_ scopes: [String]) -> String {
        var does: [String] = []
        if scopes.contains("approve") { does.append("approve AI actions") }
        if scopes.contains("agent") { does.append("use your accounts") }
        if scopes.contains("terminal") { does.append("open terminals") }
        if scopes.contains("runner") { does.append("run work") }
        let first = does.joined(separator: ", ")
        return "Can " + (first.isEmpty ? "chat and see projects" : first)
    }

    /// The scopes with `admin` added, in the order the app lists them.
    static func withAdmin(_ scopes: [String]) -> [String] {
        scopes.contains("admin") ? scopes : scopes + ["admin"]
    }
}

/// A small rounded-rect tag: a kind, a scope.
struct Chip: View {
    let text: String
    var tint: Tone?
    var body: some View { CoreChip(text) }
}

/// The scopes a device holds: all five as one word, else the first two and how many more.
struct AccessChips: View {
    let scopes: [String]
    var body: some View {
        let ordered = ScopeText.all.filter(scopes.contains) + scopes.filter { !ScopeText.all.contains($0) }
        HStack(spacing: Space.s1) {
            if ScopeText.all.allSatisfy(scopes.contains) {
                Chip(text: "all five")
            } else {
                ForEach(ordered.prefix(2), id: \.self) { Chip(text: $0) }
                if ordered.count > 2 { Chip(text: "+\(ordered.count - 2)") }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(scopes.joined(separator: ", "))
    }
}

/// Rename in place: a field with Save and Cancel. A Touch ID that does not go through leaves the edit where it is.
struct InlineRename: View {
    let app: AppModel
    let device: DeviceInfo
    @State private var name: String

    init(app: AppModel, device: DeviceInfo) {
        self.app = app
        self.device = device
        _name = State(initialValue: device.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            CoreTextField("Name", placeholder: "1 to 64 characters", text: $name, autofocus: true) { go() }
            StepUpBanner(app: app)
            ErrorLine(text: app.devices.dialogError)
            HStack(spacing: Space.s2) {
                Button("Save") { go() }.buttonStyle(CoreButtonStyle(.prominent, busy: app.devices.busy))
                    .disabled(name.isEmpty || name == device.name).coreShortcut(.primary)
                Button("Cancel") { stop() }.buttonStyle(.coreSecondary).coreShortcut(.cancel)
            }
        }
        .onAppear {
            app.devices.dialogError = nil
            app.stepUpNotice = nil
        }
    }

    private func go() {
        Task { if await app.devices.rename(device, to: name) { stop() } }
    }

    private func stop() {
        app.stepUpNotice = nil
        app.devices.renaming = false
    }
}
