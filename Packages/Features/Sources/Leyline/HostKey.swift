import Admin
import CoreUI
import SwiftUI

/// Where a host's key stands, from the Core's own list (`GET /hosts/{h}/host-keys`): nothing yet, waiting for a person to
/// trust what the host offered, trusted, or changed (a trusted key and a different one offered since).
enum HostKeyStatus: Equatable {
    case unknown, none
    case waiting(String)
    case trusted(String, since: Date?)
    case changed(old: String, new: String)

    init(_ keys: [HostKeyItem]) {
        let trusted = keys.first { $0.state == "trusted" }
        let seen = keys.last { $0.state == "seen" }
        switch (trusted, seen) {
        case (let t?, let s?): self = .changed(old: t.fingerprint, new: s.fingerprint)
        case (let t?, nil): self = .trusted(t.fingerprint, since: t.trustedAt.flatMap(HostWire.date))
        case (nil, let s?): self = .waiting(s.fingerprint)
        default: self = .none
        }
    }

    /// The key a person is asked about (a new one, or the one that replaced the pin).
    var asked: String? {
        switch self {
        case .waiting(let fp), .changed(_, let fp): fp
        default: nil
        }
    }
}

extension HostPageState {
    func loadHostKeys() async {
        guard let service else { return }
        // A Core that cannot list them reads as "none": the terminal still opens, and says why if it stops.
        hostKeys = (try? await service.hostKeys(host: hostID)).map(HostKeyStatus.init) ?? HostKeyStatus.none
    }

    /// Trusts the key the host offered, or replaces a changed pin with it (Touch ID; replace is a step-up route).
    func trustHostKey() async {
        guard let service, let fp = hostKeys.asked, !trusting, model.mayWrite() else { return }
        let changed = if case .changed = hostKeys { true } else { false }
        let name = host?.name ?? "the host"
        trusting = true
        defer { trusting = false }
        do {
            try await model.host.elevated(
                changed ? "Replace the host key of \(name)." : "Trust the host key of \(name).",
                done: "trusted", keepsEdit: false
            ) {
                if changed {
                    try await service.replaceHostKey(host: hostID, fingerprint: fp)
                } else {
                    try await service.trustHostKey(host: hostID, fingerprint: fp)
                }
            }
            model.hostTerminals[hostID] = nil  // the one that ended on the unpinned key; the next opens fresh
            await loadHostKeys()
        } catch is AdminDeclined {
        } catch { shell.showToast(words(error), kind: .warn) }
    }
}

/// The host key in Access: its pattern and when it was trusted, or what the host offered with Trust.
struct HostKeySection: View {
    let state: HostPageState

    var body: some View {
        let rule = "If it ever changes, Leyline stops before signing in and asks you."
        switch state.hostKeys {
        case .trusted(let fp, let since):
            row(
                fp, since.map { "Trusted on \($0.formatted(.dateTime.day().month(.abbreviated)))" } ?? "Trusted",
                FingerprintPattern.short(fp), rule)
        case .waiting(let fp), .changed(_, let fp):
            let changed = if case .changed = state.hostKeys { true } else { false }
            VStack(alignment: .leading, spacing: Space.s2) {
                row(
                    fp, changed ? "Changed · review it" : "Waiting for you to trust it", fp,
                    "Compare it on the server: ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub")
                Button(changed ? "Replace the Key" : "Trust This Key") { Task { await state.trustHostKey() } }
                    .buttonStyle(
                        CoreButtonStyle(changed ? .quietDanger : .prominent, size: .small, busy: state.trusting)
                    )
                    .disabled(state.trusting || state.model.readOnly)
                    .accessibilityIdentifier("host-key-trust")
            }
        case .none, .unknown:
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Not pinned yet").coreFont(size: MacTextSize.body, weight: .medium)
                Text("Leyline keeps the host’s key the first time it connects. \(rule)")
                    .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(_ fp: String, _ title: String, _ text: String, _ line: String) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            FingerprintPattern(fingerprint: fp)
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(title).coreFont(size: MacTextSize.body, weight: .medium)
                Text(text).coreFont(size: MacTextSize.meta, design: .monospaced).foregroundStyle(GlassInk.secondary)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Text(line).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The one line at the top of a host page (and in place of its terminal) while its key waits for a person: terminals and
/// files refuse until then. Same action as Access.
struct HostKeyPrompt: View {
    let state: HostPageState

    var body: some View {
        if let fp = state.hostKeys.asked {
            let changed = if case .changed = state.hostKeys { true } else { false }
            CoreNotice(
                symbol: changed ? "exclamationmark.shield" : "checkmark.shield",
                title: changed
                    ? "This host’s key changed. Review it before you connect" : "Trust this host’s key to connect",
                text: FingerprintPattern.short(fp), tone: .warn
            ) {
                Button(changed ? "Review" : "Trust") {
                    if changed { state.model.accessOpen = true } else { Task { await state.trustHostKey() } }
                }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small, busy: state.trusting))
                .disabled(state.trusting || state.model.readOnly)
            }
            .accessibilityIdentifier("host-key-prompt")
        }
    }
}
