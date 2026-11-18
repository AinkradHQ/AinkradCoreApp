import CoreKit
import Foundation

/// Reads a mockup package from the Core: `GET /docs/{doc}/package` for the manifest and file list, and
/// `GET /docs/{doc}/package/files?path=` for one file (the Core sends it as an inert attachment; the viewer decides the type).
struct LiveMockupSource: MockupSource {
    let connection: CoreConnection

    private struct FileWire: Decodable { let path: String }
    private struct ScreenWire: Decodable {
        let name: String
        let path: String
        let states: [String]?
    }
    private struct ManifestWire: Decodable { let screens: [ScreenWire] }
    private struct PackageWire: Decodable {
        let sealed: Bool
        let manifest: ManifestWire?
        let files: [FileWire]
    }

    func package(_ doc: String) async throws -> MockupPackage {
        let data = try await get("\(LiveDesignService.base)/docs/\(LiveDesignService.seg(doc))/package")
        let wire: PackageWire
        do { wire = try JSONDecoder().decode(PackageWire.self, from: data) } catch {
            throw MockupFailure.core("The Core answered something this app does not know.")
        }
        guard wire.sealed, let manifest = wire.manifest else { throw MockupFailure.notSealed }
        return MockupPackage(
            doc: doc, screens: manifest.screens.map { .init(name: $0.name, path: $0.path, states: $0.states ?? []) },
            files: wire.files.map(\.path))
    }

    func file(_ doc: String, path: String) async throws -> Data {
        // The path is a package path the viewer already validated; it still goes out as one escaped query value.
        var q = URLComponents()
        q.queryItems = [URLQueryItem(name: "path", value: path)]
        let query = q.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B") ?? ""
        return try await get("\(LiveDesignService.base)/docs/\(LiveDesignService.seg(doc))/package/files?\(query)")
    }

    private func get(_ target: String) async throws -> Data {
        do {
            return try await connection.signedRequest(method: "GET", target: target)
        } catch CoreError.http(let status, let code, let message) {
            throw MockupFailure.core(LiveDesignService.failure(status: status, code: code, message: message).sentence)
        } catch CoreError.badRequest(let message) {
            throw MockupFailure.core(message)
        }
    }
}
