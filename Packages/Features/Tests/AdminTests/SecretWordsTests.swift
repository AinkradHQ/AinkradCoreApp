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

    @Test func everyKindHasItsCoreWordAndFilesAreLimitedToOneMegabyte() {
        #expect(SecretWords.Kind.allCases.map(\.wire) == ["text", "multiline", "file", "env_bundle"])
        #expect(SecretWords.Kind(wire: "env_bundle") == .env && SecretWords.Kind(wire: "old") == .text)
        #expect(SecretWords.Kind.file.blurb.contains("1 MB") && SecretWords.fileLimit == 1_048_576)
    }

    @Test func dialogTitlesKeepANameInOnePiece() {
        #expect(SecretWords.unbroken("aws-prod") == "aws\u{2011}prod")
        #expect(SecretWords.unbroken("my key") == "my\u{00A0}key")
        let long = SecretWords.unbroken("abcdefghijklmnopqrstuvwxyz0123456789", max: 11)
        #expect(long == "abcde…56789" && long.count == 11)
    }

    @Test func rowsShowLastUsedAndUseCount() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var s = item()
        #expect(SecretWords.lastUsed(s, now: now) == "Never used")
        s.lastUsedAt = now.addingTimeInterval(-7200)
        s.useCount = 12
        #expect(SecretWords.lastUsed(s, now: now) == "Used 2 h ago · 12 times")
        s.kind = "file"
        s.fileName = "aws.json"
        #expect(SecretWords.sealed(s) == "aws.json · Sealed · 20 B")
    }

    @Test("the list's columns say the mockup's short words")
    func listColumnsUseShortWords() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var s = item()
        #expect(SecretWords.lastUsedShort(s, now: now) == "Never")
        s.lastUsedAt = now.addingTimeInterval(-30)
        #expect(SecretWords.lastUsedShort(s, now: now) == "Just now")
        s.lastUsedAt = now.addingTimeInterval(-7200)
        #expect(SecretWords.lastUsedShort(s, now: now) == "2 hours ago")
        s.lastUsedAt = now.addingTimeInterval(-90_000)
        #expect(SecretWords.lastUsedShort(s, now: now) == "Yesterday")
        s.lastUsedAt = now.addingTimeInterval(-3 * 86_400)
        #expect(SecretWords.lastUsedShort(s, now: now) == "3 days ago")
        #expect(SecretWords.lent(to: "Build box", secondsLeft: 41 * 60) == "Lent to Build box · 41 min left")
        #expect(SecretWords.lent(to: "Build box", secondsLeft: 40) == "Lent to Build box · 40 s left")
        #expect(SecretWords.lent(to: "Build box", secondsLeft: 0) == "Back from Build box")
        #expect(SecretWords.header(count: 6) == "6 · values never come back")
    }

    @Test func groupsAreSectionsAndTheRestIsNoGroup() {
        var a = item("a")
        a.group = "aws"
        let b = item("b")
        let aws = SecretGroupItem(name: "aws", description: "", members: ["a"], runners: [])
        let empty = SecretGroupItem(name: "zed", description: "", members: [], runners: [])
        let all = SecretSections.sections([a, b], groups: [empty, aws])
        #expect(all.map(\.title) == ["aws", "zed", "No group"])
        #expect(
            SecretSections.sections([a, b], groups: [empty, aws], narrowed: true).map(\.title) == ["aws", "No group"])
        #expect(SecretSections.sections([b], groups: []).map(\.title) == ["All secrets"])
    }

    @Test func aGroupsRunnersCountWhenTheSecretHasNone() {
        var s = item("a", runners: [])
        s.effectiveRunners = ["r9"]
        #expect(s.runnersUsing == ["r9"] && SecretWords.matches(s, query: "", runner: "r9"))
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
            SecretWords.preview(delivery: "file", runners: ["Build box"])
                == "AI sessions on Build box get it as a file only they can read.")
        #expect(SecretWords.preview(delivery: "env", runners: []).hasPrefix("No runner may use it yet"))
    }

    @Test func rowsTellWhoUsesItAndWhenItChanged() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(SecretWords.usedBy([]) == "No runner yet")
        #expect(SecretWords.usedBy(["Home server", "build-box"]) == "Home server, build-box")
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
        let line = SecretWords.usage(item(runners: ["r1"], version: 3), runnerNames: ["Home server"])
        #expect(line.contains("Used on 1 runner (Home server)") && line.contains("Changed 2 times"))
        #expect(SecretWords.usage(item(), runnerNames: []).hasPrefix("No runner may use it."))
    }

    @Test func withoutGroupsEverySecretIsInOneSection() {
        #expect(SecretSections.sections([], groups: []).isEmpty)
        let s = SecretSections.sections([item("a"), item("b")], groups: [])
        #expect(s.count == 1 && s[0].items.count == 2)
    }
}
