import Foundation
import Testing

@testable import Accounts

@MainActor struct AccountsOptionsTests {
    @Test func theWizardStartsOnTheChosenProviderTheCoreOffers() {
        #expect(AccountsOptions.startProvider("claude", among: ["openai", "anthropic"]) == "anthropic")
        #expect(AccountsOptions.startProvider("openai", among: ["openai", "anthropic"]) == "openai")
        #expect(AccountsOptions.startProvider("gemini", among: ["openai", "anthropic"]) == nil)
    }

    @Test func checkIntervalsAreMinuteFiveMinutesHour() {
        #expect(ConnectionsOptions.seconds("1m") == 60)
        #expect(ConnectionsOptions.seconds("5m") == 300)
        #expect(ConnectionsOptions.seconds("1h") == 3600)
        #expect(ConnectionsOptions.seconds("odd") == 300)
    }
}
