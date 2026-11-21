import CoreKit
import Foundation
import Testing

@testable import Accounts

struct AccountNamesTests {
    @Test func aNameIsTrimmedFreeTextOfAtMost64Characters() {
        #expect(AccountNames.clean("  Work Claude ") == "Work Claude")
        #expect(AccountNames.clean("   ") == nil, "blank is no name")
        #expect(AccountNames.problem("Google Gemini (EU) · 2") == nil, "capitals, spaces and punctuation")
        #expect(AccountNames.problem(String(repeating: "é", count: 64)) == nil)
        #expect(AccountNames.problem(String(repeating: "N", count: 65)) != nil)
        #expect(AccountNames.problem("Work\nClaude") != nil && AccountNames.problem("tab\there") != nil)
        #expect(AccountNames.problem("") == nil, "empty is allowed: it clears the name")
    }

    @Test func anUnnamedAccountGoesByItsProvider() {
        #expect(AccountNames.title("Work Claude", provider: "Claude") == "Work Claude")
        #expect(AccountNames.title(nil, provider: "Claude") == "Claude")
        #expect(AccountNames.title("  ", provider: "Claude") == "Claude")
    }
}

@MainActor
struct AccountRenameTests {
    func make(names: Bool) async -> (AccountsModel, FakeService) {
        let model = AccountsModel(host: FakeHost())
        let svc = FakeService()
        svc.orderOn = true
        svc.namesOn = names
        var named = account(1, "claude-main")
        named.displayName = "Work Claude"
        svc.accountList = [named, account(2, "spare")]
        model.use(svc)
        await model.reload()
        return (model, svc)
    }

    @Test func rowsShowTheNameElseTheProvider() async {
        let (m, _) = await make(names: true)
        let provider = ProviderCatalog.name("anthropic", fallback: m.providerName("anthropic"))
        #expect(m.title(m.account(1)!) == "Work Claude")
        #expect(m.title(m.account(2)!) == provider)
        #expect(m.orderRows.map(\.title) == ["Work Claude", provider])
    }

    @Test func renameIsOnlyOfferedByACoreThatKeepsNames() async {
        #expect(await make(names: false).0.namesOn == false)
        #expect(await make(names: true).0.namesOn)
    }

    @Test func renameWritesTheNameAndBlankClearsIt() async {
        let (m, svc) = await make(names: true)
        #expect(await m.rename(m.account(2)!, to: "  Night Shift "))
        #expect(m.account(2)?.displayName == "Night Shift")
        #expect(await m.rename(m.account(1)!, to: " "))
        #expect(m.account(1)?.displayName == nil)
        // Unchanged, or the provider's own name on an unnamed account: nothing is written.
        let before = svc.log.count
        #expect(await m.rename(m.account(2)!, to: "Night Shift"))
        #expect(await m.rename(m.account(1)!, to: m.title(m.account(1)!)))
        #expect(svc.log.count == before)
        #expect(svc.log.contains("setAccountName 2 Night Shift") && svc.log.contains("setAccountName 1 -"))
    }
}
