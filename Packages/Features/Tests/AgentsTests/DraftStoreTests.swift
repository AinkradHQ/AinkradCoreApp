import Testing

@testable import Agents

struct DraftStoreTests {
    @Test func aDraftIsKeptAndClearedWithTheField() {
        let id = "as_draft_test"
        DraftStore.save(id, "half a thought")
        #expect(DraftStore.load(id) == "half a thought")
        DraftStore.save(id, "")
        #expect(DraftStore.load(id).isEmpty)
    }
}
