import Foundation
import Testing

@testable import Admin

struct SecretWordsTests {
    func item(
        _ name: String = "github-token", runners: [String] = [], version: Int64 = 1, size: Int64 = 20,
        ago: TimeInterval = 7200
    ) -> SecretItem {
        SecretItem(
            name: name, owner: "d_me", runners: runners, delivery: "env", version: version, size: size, keyID: "k1",
            createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 1_000_000 - ago))
    }

    @Test func onlyTextIsStoredToday() {
        #expect(SecretWords.Kind.allCases.filter(\.available) == [.text])
        #expect(SecretWords.Kind.file.blurb.contains("1 MB"))
    }

    @Test func sizesReadLikeTheDesign() {
        #expect(SecretWords.size(20) == "20 B")
        #expect(SecretWords.size(1_200) == "1.2 KB")
        #expect(SecretWords.size(40_000) == "40 KB")
    }

    @Test func deliveryIsInPlainWords() {
        #expect(SecretWords.delivery("env").line == "As a setting (environment variable)")
        #expect(SecretWords.delivery("askpass").line == "As a password prompt (for git and ssh)")
        #expect(SecretWords.delivery("file").title == "As a file")
    }

    @Test func thePreviewSaysWhoGetsItAndHow() {
        #expect(
            SecretWords.preview(delivery: "file", runners: ["Azure Dev"])
                == "Agents on Azure Dev get it as a file only they can read.")
        #expect(SecretWords.preview(delivery: "env", runners: []).hasPrefix("No runner may use it yet"))
    }

    @Test func rowsTellWhoUsesItAndWhenItChanged() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(SecretWords.usedBy([]) == "No runner yet")
        #expect(SecretWords.usedBy(["Oracle", "vps-1"]) == "Oracle, vps-1")
        #expect(SecretWords.changed(item(ago: 7200), now: now) == "Changed 2 h ago")
        #expect(SecretWords.changed(item(ago: 30), now: now) == "Changed just now")
        #expect(SecretWords.versions(item(version: 1)) == "First value")
        #expect(SecretWords.versions(item(version: 4)) == "Changed 3 times")
    }

    @Test func searchAndRunnerFilterNarrowTheList() {
        let a = item("aws-key", runners: ["r1"])
        let b = item("github-token", runners: ["r2"])
        #expect(SecretWords.matches(a, query: "AWS", runner: nil))
        #expect(!SecretWords.matches(b, query: "aws", runner: nil))
        #expect(SecretWords.matches(b, query: "", runner: "r2"))
        #expect(!SecretWords.matches(b, query: "", runner: "r1"))
    }

    @Test func theDeleteDialogSaysWhereItIsUsed() {
        let line = SecretWords.usage(item(runners: ["r1"], version: 3), runnerNames: ["Oracle"])
        #expect(line.contains("Used on 1 runner (Oracle)") && line.contains("Changed 2 times"))
        #expect(SecretWords.usage(item(), runnerNames: []).hasPrefix("No runner may use it."))
    }

    @Test func withoutGroupsEverySecretIsInOneSection() {
        #expect(SecretSections.sections([]).isEmpty)
        let s = SecretSections.sections([item("a"), item("b")])
        #expect(s.count == 1 && s[0].items.count == 2)
    }
}
