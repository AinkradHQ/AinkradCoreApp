import Foundation
import Testing

@testable import Design

@MainActor struct DesignOptionsTests {
    @Test func snapMovesOntoTheGridOnlyWhenOn() {
        #expect(DesignOptions.snap(13, on: true) == 16)
        #expect(DesignOptions.snap(11, on: true) == 8)
        #expect(DesignOptions.snap(13, on: false) == 13)
        #expect(DesignOptions.snap(nil, on: true) == nil, "a cleared field stays cleared")
    }

    @Test func starterIsAPageWithOneFrameOfTheCanvasSize() {
        let ops = DesignOptions.starterOps(.phone, page: "n_aaaaaaaaaaaa", frame: "n_bbbbbbbbbbbb")
        #expect(ops.count == 2)
        #expect(ops[0]["type"] == .string("page") && ops[0]["parent"] == .null)
        #expect(ops[1]["parent"] == .string("n_aaaaaaaaaaaa"))
        #expect(ops[1]["props"] == .object(["w": .number(390), "h": .number(844)]))
        #expect(EditOps.json(ops) != nil)
    }

    @Test func generatedIDsFollowTheEngineGrammar() {
        let id = DesignOptions.nodeID()
        #expect(id.count == 14 && id.hasPrefix("n_"))
        #expect(id.dropFirst(2).allSatisfy { ("a"..."z").contains($0) || ("2"..."7").contains($0) })
    }
}
