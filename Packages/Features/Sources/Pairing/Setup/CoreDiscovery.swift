import Foundation
import Network

/// A Core that advertises itself on this network (`_ainkrad._tcp`, from the Core's Avahi file). The record carries public
/// facts only; pairing it still needs its link or code, and the link's fingerprint must match this one.
struct NearbyCore: Identifiable, Equatable, Sendable {
    let name: String
    let fingerprint: String
    let host: String
    var id: String { fingerprint }
    var fingerprintHint: String { "\(fingerprint.prefix(8))…\(fingerprint.suffix(4))" }
}

/// What the wizard needs from discovery, so a test can stand in for the network.
@MainActor
protocol CoreDiscovery: AnyObject {
    /// Starts looking; `found` is called with everything seen so far, each time it changes.
    func start(_ found: @escaping @MainActor ([NearbyCore]) -> Void)
    func stop()
}

/// Looks for nothing: the default, so a test never opens the network.
@MainActor
final class NoDiscovery: CoreDiscovery {
    func start(_ found: @escaping @MainActor ([NearbyCore]) -> Void) {}
    func stop() {}
}

/// Bonjour through Network.framework. The first browse asks macOS for Local Network access (Info.plist says why).
@MainActor
final class BonjourDiscovery: CoreDiscovery {
    private var browser: NWBrowser?

    func start(_ found: @escaping @MainActor ([NearbyCore]) -> Void) {
        stop()
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: "_ainkrad._tcp", domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { results, _ in
            let cores = results.compactMap(Self.core)
            Task { @MainActor in found(cores) }
        }
        b.start(queue: .main)
        browser = b
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }

    private nonisolated static func core(_ r: NWBrowser.Result) -> NearbyCore? {
        guard case .service(let name, _, _, _) = r.endpoint,
            case .bonjour(let txt) = r.metadata, let fp = txt["fp"], fp.count == 43
        else { return nil }
        return NearbyCore(name: name, fingerprint: fp, host: txt["host"] ?? "")
    }
}
