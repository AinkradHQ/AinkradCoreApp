import Foundation
import Testing

@testable import Brain

@MainActor struct BrainOptionsTests {
    @Test func rememberSetsRetentionForNewRoomsOnlyWhenNotForever() {
        #expect(BrainOptions.newRoomRetention("month") == 30)
        #expect(BrainOptions.newRoomRetention("year") == 365)
        #expect(BrainOptions.newRoomRetention("forever") == nil)
        #expect(BrainOptions.newRoomRetention("unknown") == nil)
    }

    @Test func askingMapsToTheCoresSuggestionStrength() {
        #expect(BrainOptions.asks.map(\.id) == [0, 1, 2])
    }
}
