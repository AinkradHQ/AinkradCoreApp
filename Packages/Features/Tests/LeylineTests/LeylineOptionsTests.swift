import Foundation
import Testing

@testable import Leyline

@MainActor struct LeylineOptionsTests {
    private func host(_ id: String) -> HostItem {
        HostItem(
            id: id, name: id, address: "\(id).example.net", port: 22, username: "me", keyID: nil, jumpChain: [],
            viaRunner: nil, group: nil, tags: [], aiRule: .ask, os: nil, createdAt: nil)
    }

    @Test func showFiltersByWhatThisMacKnows() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let hosts = [host("a"), host("b"), host("c")]
        let opened = ["a": now.addingTimeInterval(-86_400), "b": now.addingTimeInterval(-40 * 86_400)]
        func ids(_ s: LeylineOptions.Show) -> [String] {
            LeylineOptions.filter(hosts, show: s, opened: opened, mine: ["c"], now: now).map(\.id)
        }
        #expect(ids(.everything) == ["a", "b", "c"])
        #expect(ids(.active) == ["a"], "b was opened 40 days ago, c never")
        #expect(ids(.mine) == ["c"])
    }
}
