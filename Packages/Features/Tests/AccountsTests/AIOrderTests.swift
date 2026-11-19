import CoreKit
import Foundation
import Testing

@testable import Accounts

struct AIOrderLogicTests {
    @Test func movesAreWholeListAnswers() {
        #expect(OrderMoves.moved([1, 2, 3, 4], from: 0, to: 2) == [2, 3, 1, 4])
        #expect(OrderMoves.moved([1, 2, 3], from: 2, to: 0) == [3, 1, 2])
        #expect(OrderMoves.moved([1, 2, 3], from: 1, to: 1) == [1, 2, 3])
        #expect(OrderMoves.moved([1, 2, 3], from: 5, to: 0) == [1, 2, 3])
        #expect(OrderMoves.up([1, 2, 3], 3) == [1, 3, 2])
        #expect(OrderMoves.up([1, 2, 3], 1) == [1, 2, 3], "the first one cannot go up")
        #expect(OrderMoves.down([1, 2, 3], 3) == [1, 2, 3], "the last one cannot go down")
        #expect(OrderMoves.down([1, 2, 3], 1) == [2, 1, 3])
    }

    @Test func aDragLandsWhereItPointsAndOthersOpenAGap() {
        #expect(OrderMoves.dragTarget(from: 1, translation: 80, pitch: 72, count: 5) == 2)
        #expect(OrderMoves.dragTarget(from: 1, translation: 30, pitch: 72, count: 5) == 1)
        #expect(OrderMoves.dragTarget(from: 1, translation: -500, pitch: 72, count: 5) == 0)
        #expect(OrderMoves.dragTarget(from: 1, translation: 900, pitch: 72, count: 5) == 4)
        // dragging row 0 to slot 2: rows 1 and 2 each shift up one slot
        #expect([0, 1, 2, 3].map { OrderMoves.shift(row: $0, dragged: 0, target: 2) } == [0, -1, -1, 0])
        #expect([0, 1, 2, 3].map { OrderMoves.shift(row: $0, dragged: 3, target: 1) } == [0, 1, 1, 0])
    }

    @Test func theListHoldsTheOrderThenWhatItDoesNotHoldYet() {
        #expect(AccountsModel.merge(order: [3, 1], accounts: [1, 2, 3]) == [3, 1, 2])
        #expect(
            AccountsModel.merge(order: [9, 2, 2], accounts: [1, 2]) == [2, 1], "unknown and repeated ids drop out")
        #expect(AccountsModel.merge(order: [], accounts: [4, 5]) == [4, 5])
    }

    @Test func theFirstUsableAccountIsInUseAndStatesShowAsChips() {
        func v(_ state: String) -> (AccountVerdict, String) {
            (AccountVerdict.of(account(1, "a", state: state)), state)
        }
        let chips = OrderChips.chips([v("limited"), v("active"), v("active"), v("disabled"), v("signing_in")])
        #expect(chips == [.limitHit, .inUse, .ready, .off, .signingIn])
        #expect(OrderChips.chips([v("cooling")]) == [.limitHit])
        #expect(OrderChips.chips([v("unhealthy")]) == [.needsLook("Needs a look")])
        #expect(OrderChips.chips([v("disabled"), v("active")]) == [.off, .inUse], "a turned-off row is skipped")
    }

    @Test func usageSentencesUseTheNumbersTheCoreHas() {
        let utc = TimeZone(identifier: "UTC")!
        #expect(UsageSentence.of(UsageFacts(share: 0.38, windowSecs: 604_800), tz: utc) == "38% of this week used")
        #expect(UsageSentence.of(UsageFacts(share: 0.5, windowSecs: 18_000), tz: utc) == "50% of these 5 hours used")
        #expect(
            UsageSentence.of(UsageFacts(monthSpendMicros: 12_000_000, monthLimitMicros: 50_000_000), tz: utc)
                == "$12 of $50 this month")
        #expect(UsageSentence.of(UsageFacts(monthSpendMicros: 4_500_000), tz: utc) == "$4.50 this month")
        #expect(UsageSentence.of(UsageFacts(), tz: utc) == "No use yet this month")
        #expect(UsageSentence.of(UsageFacts(signing: true), tz: utc) == "Finish signing in to use it")
        // 2026-11-20 is a Friday
        let friday = Date(timeIntervalSince1970: 1_795_165_200)  // 2026-11-20 09:00 UTC
        #expect(
            UsageSentence.of(UsageFacts(limitHit: true, resetsAt: friday, windowSecs: 604_800), tz: utc)
                == "Used all of this week. Back Friday 9:00")
        #expect(
            UsageSentence.of(UsageFacts(limitHit: true), tz: utc) == "Used all of this week. Waiting for it to reset")
        #expect(UsageSentence.meter(UsageFacts(limitHit: true)) == 1)
        #expect(UsageSentence.meter(UsageFacts(share: 1.4, windowSecs: 18_000)) == 1)
        #expect(UsageSentence.meter(UsageFacts()) == 0)
    }

    @Test func addStepsGoPickThenKeyOrSignInThenDone() {
        var s = AddStepper()
        #expect(s.step == .pick && s.number == 1)
        s.choose(.apiKey)
        #expect(s.step == .key && s.number == 2)
        s.submitKey()
        #expect(s.step == .checking && s.number == 2)
        s.checked(ok: false)
        #expect(s.step == .key, "a key that failed is asked for again")
        s.submitKey()
        s.checked(ok: true)
        #expect(s.step == .done && s.number == 3)
        s.again()
        s.choose(.subscription)
        #expect(s.step == .signIn)
        s.back()
        #expect(s.step == .pick)
        s.choose(.subscription)
        s.signedIn()
        #expect(s.step == .done)
    }

    @Test func aStepOnlyMovesFromItsOwnPlace() {
        var s = AddStepper()
        s.submitKey()
        s.signedIn()
        s.checked(ok: true)
        #expect(s.step == .pick)
        s.back()
        #expect(s.step == .pick)
    }

    @Test func theKeyLineSaysWhatIsWrongWhileTyping() {
        #expect(KeyShape.live("abc", prefix: nil) == .empty)
        #expect(KeyShape.live("demo-key-4f9c1a7e20b8", prefix: nil) == .looksValid)
        #expect(KeyShape.live("demo-key-4f9c1a7e20b8", prefix: "sk-or-v1-") == .wrongPrefix("sk-or-v1-"))
        #expect(KeyShape.live("  sk-or-v1-abcdef  ", prefix: "sk-or-v1-") == .looksValid)
        #expect(KeyShape.words(.looksValid) == "Looks like a valid key")
    }

    @Test func addCardsComeFromTheCoreListInTheMockupsOrder() {
        func p(_ id: String, _ login: String = "paste") -> ProviderItem {
            ProviderItem(
                id: id, name: id.uppercased(), harness: "claude", authVar: "K", baseURL: "", delivery: [],
                loginMethods: [login], models: [], pricedAt: nil, builtin: false)
        }
        let all = [
            p("groq"), p("codex-sub", "device_code"), p("openrouter"), p("claude-sub", "browser_code"), p("newcomer"),
            p("anthropic"),
        ]
        #expect(ProviderCatalog.cards(all, .subscription).map(\.id) == ["claude-sub", "codex-sub"])
        #expect(ProviderCatalog.cards(all, .apiKey).map(\.id) == ["anthropic", "openrouter", "groq", "newcomer"])
        #expect(ProviderCatalog.name("codex-sub") == "ChatGPT / Codex")
        #expect(
            ProviderCatalog.name("newcomer", fallback: "Newcomer") == "Newcomer",
            "an unknown provider shows its own name")
    }

    @Test func aNewAccountNameIsFreeAndLegal() {
        #expect(ProviderCatalog.label(for: "ChatGPT / Codex", taken: []) == "chatgpt--codex")
        #expect(ProviderCatalog.label(for: "Anthropic", taken: ["anthropic"]) == "anthropic-2")
        #expect(ProviderCatalog.label(for: "Anthropic", taken: ["anthropic", "anthropic-2"]) == "anthropic-3")
        #expect(ProviderCatalog.label(for: "9lives", taken: []) == "a-9lives")
    }

    @Test func anAgentsChoiceReadsBackFromItsOrder() {
        #expect(AccountsModel.choice(override: [], all: [1, 2, 3]) == .follow)
        #expect(AccountsModel.choice(override: [2], all: [1, 2, 3]) == .only(2))
        #expect(AccountsModel.choice(override: [2, 1, 3], all: [1, 2, 3]) == .first(2))
        #expect(AccountsModel.choice(override: [3, 2, 1], all: [1, 2, 3]) == .custom)
        #expect(AccountsModel.agentItems(.first(2), all: [1, 2, 3]) == [2, 1, 3])
        #expect(AccountsModel.agentItems(.only(2), all: [1, 2, 3]) == [2])
        #expect(AccountsModel.agentItems(.follow, all: [1, 2, 3]) == nil)
    }
}

@MainActor
struct AIOrderModelTests {
    func make(on: Bool = true) async -> (AccountsModel, FakeService, FakeHost) {
        let host = FakeHost()
        let model = AccountsModel(host: host)
        let svc = FakeService()
        svc.orderOn = on
        svc.accountList = [
            account(1, "claude-main"), account(2, "codex-main", provider: "openai"), account(3, "spare"),
        ]
        svc.orderEntries = [3, 1].map {
            AIOrderEntry(account: $0, provider: nil, harness: nil, model: $0 == 1 ? "claude-sonnet" : nil)
        }
        model.use(svc)
        await model.reload()
        return (model, svc, host)
    }

    @Test func belowMinor95TheOldPagesStay() async {
        let (m, _, _) = await make(on: false)
        #expect(!m.aiOrderOn)
        #expect(m.orderIDs.isEmpty)
    }

    @Test func theListFollowsTheCoresOrderThenTheRest() async {
        let (m, _, _) = await make()
        #expect(m.aiOrderOn)
        #expect(m.orderIDs == [3, 1, 2])
        #expect(m.orderRows.map(\.number) == [1, 2, 3])
        #expect(m.orderRows.first?.chip == .inUse)
        #expect(m.orderRows.dropFirst().first?.model == "claude-sonnet")
    }

    @Test func aMoveShowsAtOnceAndWritesTheWholeListKeepingModels() async {
        let (m, svc, host) = await make()
        await m.move(2, to: 0)
        #expect(m.orderIDs == [2, 3, 1])
        #expect(svc.log.contains("setAIOrder - 2,3,1"))
        #expect(svc.orderEntries.first { $0.account == 1 }?.model == "claude-sonnet")
        #expect(host.reasons.count == 1, "one Touch ID")
    }

    @Test func aRefusedMoveGoesBackAndSaysWhy() async {
        let (m, svc, _) = await make()
        svc.failure = CoreError.http(status: 409, code: "conflict", message: "no")
        await m.moveDown(3)
        #expect(m.orderIDs == [3, 1, 2])
        #expect(m.writeError["order"] != nil)
    }

    @Test func aDeclinedTouchIDAlsoGoesBackWithoutAnError() async {
        let (m, svc, host) = await make()
        host.declines = true
        await m.moveUp(2)
        #expect(m.orderIDs == [3, 1, 2])
        #expect(m.writeError["order"] == nil)
        #expect(!svc.log.contains { $0.hasPrefix("setAIOrder") })
    }

    @Test func movingTheFirstUpOrTheLastDownWritesNothing() async {
        let (m, svc, _) = await make()
        await m.moveUp(3)
        await m.moveDown(2)
        #expect(!svc.log.contains { $0.hasPrefix("setAIOrder") })
    }

    @Test func anAgentOrderIsSetWithItsOwnListAndClearedWhenItFollowsAgain() async {
        let (m, svc, _) = await make()
        await m.setAgentOrder("atlas", .only(2))
        #expect(svc.log.contains("setAIOrder atlas 2"))
        #expect(m.agentChoice("atlas") == .only(2))
        await m.setAgentOrder("atlas", .first(1))
        #expect(svc.log.contains("setAIOrder atlas 1,3,2"))
        await m.setAgentOrder("atlas", .follow)
        #expect(svc.log.contains("clearAIOrder atlas"))
        #expect(m.agentChoice("atlas") == .follow)
        await m.setAgentOrder("birch", .follow)
        #expect(!svc.log.contains("clearAIOrder birch"), "an agent with no order of its own is not cleared")
    }
}
