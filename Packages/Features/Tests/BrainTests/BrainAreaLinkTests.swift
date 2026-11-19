import Testing

@testable import Brain

struct BrainAreaLinkTests {
    @Test func everyKnownAreaOpensABrainTab() {
        for area in BrainAreaLink.areas { #expect(BrainTab.allCases.contains(BrainAreaLink.tab(for: area))) }
        #expect(BrainAreaLink.tab(for: "nonsense") == .overview)
    }
}
