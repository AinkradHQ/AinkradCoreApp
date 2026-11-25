import CoreUI
import SwiftUI

/// A host key the host offered but nobody trusted yet. Terminals and files refuse until it is trusted, so it shows here
/// with its full fingerprint, how to compare it on the server, and Trust (Touch ID when the Core asks).
struct SeenHostKey: View {
    let model: LeylineModel
    let host: HostItem
    let rule: String
    @State private var seen: String?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Group {
            if let fp = seen {
                VStack(alignment: .leading, spacing: Space.s2) {
                    HStack(alignment: .top, spacing: Space.s3) {
                        FingerprintPattern(fingerprint: fp)
                        VStack(alignment: .leading, spacing: Space.s1) {
                            Text("Waiting for you to trust it").coreFont(size: MacTextSize.body, weight: .medium)
                            Text(fp).coreFont(size: MacTextSize.meta, design: .monospaced).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Compare it on the server: ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub")
                                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let error { CoreFieldError(error) }
                    Button("Trust This Key") { Task { await trust(fp) } }
                        .buttonStyle(CoreButtonStyle(.prominent, size: .small, busy: busy))
                        .disabled(busy || model.readOnly)
                }
            } else {
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text("Not pinned yet").coreFont(size: MacTextSize.body, weight: .medium)
                    Text("Leyline keeps the host’s key the first time it connects. \(rule)")
                        .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .task(id: host.id) { await load() }
    }

    private func load() async {
        guard let service = model.service else { return }
        let keys = (try? await service.hostKeys(host: host.id)) ?? []
        seen = keys.contains { $0.state == "trusted" } ? nil : keys.first { $0.state == "seen" }?.fingerprint
    }

    private func trust(_ fp: String) async {
        guard let service = model.service else { return }
        busy = true
        defer { busy = false }
        do {
            try await model.host.elevated("Trust the host key of \(host.name).", done: "trusted", keepsEdit: true) {
                try await service.trustHostKey(host: host.id, fingerprint: fp)
            }
            error = nil
            seen = nil
            await model.reload()
        } catch {
            self.error = model.words(error)
        }
    }
}
