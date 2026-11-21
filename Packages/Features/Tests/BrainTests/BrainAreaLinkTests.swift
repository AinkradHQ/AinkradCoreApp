import Testing

@testable import Brain

struct BrainAreaLinkTests {
    @Test func everyKnownAreaOpensItsSidebarSection() {
        #expect(BrainAreaLink.tab(for: "me") == .me)
        #expect(BrainAreaLink.tab(for: "rules") == .rules)
        #expect(BrainAreaLink.tab(for: "knowledge") == .knowledge)
        #expect(BrainAreaLink.tab(for: "timeline") == .timeline)
        #expect(BrainAreaLink.tab(for: "places") == .rooms)
        #expect(BrainAreaLink.tab(for: "inbox") == .inbox)
        #expect(BrainAreaLink.tab(for: "sources") == .sources)
        #expect(BrainAreaLink.tab(for: "activity") == .activity)
        #expect(BrainAreaLink.tab(for: "nonsense") == .overview)
    }

    @Test func eachCalmPageHasItsSection() {
        for p in BrainCalmModel.Page.allCases { #expect(p.tab.calmPage == p) }
    }
}
