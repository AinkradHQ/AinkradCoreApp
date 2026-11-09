import Foundation
import Testing

@testable import Accounts

/// A typed money amount is never off by 100x: every field reads the raw text with the person's locale.
struct MoneyInputTests {
    static let us = Locale(identifier: "en_US")
    static let de = Locale(identifier: "de_DE")
    static let cases: [(String, Int64?)] = [
        ("2,50", 2_500_000), ("2.50", 2_500_000), ("1,234.50", 1_234_500_000), ("1.234,50", 1_234_500_000),
        ("2,5", 2_500_000), (" 2 ", 2_000_000), ("abc", nil), ("$2.50", 2_500_000),
    ]

    @Test(arguments: [us, de], cases)
    func everyDollarFieldReadsTheSameAmount(_ locale: Locale, _ c: (String, Int64?)) {
        let (text, micros) = c
        // budget cap, raise and per-session cap all route through `dollars`
        #expect(BudgetInput.dollars(text, locale: locale) == (micros.map { .some($0) } ?? nil))
        #expect(BudgetInput.dollars(text, below: 1_000_000, locale: locale) == (micros.map { .some($0) } ?? nil))
        // prices accept the same text
        #expect(BudgetInput.price(text, locale: locale) == micros)
        #expect(AccountsNumbers.parseUSDMicros(text, locale: locale) == micros)
    }

    @Test(arguments: [us, de])
    func emptyMeansNoneAndZeroIsRefused(_ locale: Locale) {
        #expect(BudgetInput.dollars("", locale: locale) == .some(nil))
        #expect(BudgetInput.dollars("  ", locale: locale) == .some(nil))
        #expect(BudgetInput.dollars("0", locale: locale) == nil)
        #expect(BudgetInput.price("0", locale: locale) == 0)
    }

    @Test func twoFiftyIsNeverTwoHundredFifty() {
        #expect(BudgetInput.dollars("2,50", locale: Self.us) == .some(2_500_000))
        #expect(BudgetInput.dollars("2,50", locale: Self.de) == .some(2_500_000))
    }

    @Test func tokensAreWholeNumbersWithRealGrouping() {
        for l in [Self.us, Self.de] {
            #expect(BudgetInput.tokens("5,000,000", locale: l) == 5_000_000)
            #expect(BudgetInput.tokens("5.000.000", locale: l) == 5_000_000)
            #expect(BudgetInput.tokens(" 5000 ", locale: l) == 5000)
            #expect(BudgetInput.tokens("", locale: l) == 0)
            #expect(BudgetInput.tokens("2,50", locale: l) == nil)  // not 250
            #expect(BudgetInput.tokens("2,5", locale: l) == nil)
            #expect(BudgetInput.tokens("abc", locale: l) == nil)
            #expect(BudgetInput.raiseTokens("", locale: l) == .some(nil))
            #expect(BudgetInput.raiseTokens("1,234", locale: l) == .some(1234))
            #expect(BudgetInput.sessionTokens("400,000", min: 328_000, locale: l) == .some(400_000))
            #expect(BudgetInput.sessionTokens("4,00", min: 328_000, locale: l) == nil)
            #expect(AccountsNumbers.parseWhole("1,234.50", locale: l) == nil)
        }
        #expect(UsageLimitWords.parseCap("2,50") == nil)
        #expect(UsageLimitWords.parseCap("5,000,000") == 5_000_000)
    }

    @Test func theFieldShowsWhatItReads() {
        #expect(AccountsNumbers.usdPreview("2,50", locale: Self.us) == "= $2.50")
        #expect(AccountsNumbers.usdPreview("abc", locale: Self.us) == nil)
        #expect(AccountsNumbers.usdPreview("", locale: Self.us) == nil)
        #expect(BudgetInput.issue(tokens: "2,50", dollars: "", locale: Self.us).contains("whole number"))
        #expect(BudgetInput.issue(tokens: "", dollars: "x", locale: Self.us).contains("Dollars"))
    }
}
