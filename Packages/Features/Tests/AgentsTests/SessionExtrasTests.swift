import Testing

@testable import Agents

struct SessionExtrasTests {
    @Test func aCodeBlockNamesItsFile() {
        #expect(CodeTarget.path(info: "swift Sources/A.swift", before: nil) == "Sources/A.swift")
        #expect(CodeTarget.path(info: "swift:Sources/A.swift", before: nil) == "Sources/A.swift")
        #expect(CodeTarget.path(info: "swift", before: "Update `src/app.ts` like this:") == "src/app.ts")
        #expect(CodeTarget.path(info: "swift", before: "See https://example.com/page") == nil)
        #expect(CodeTarget.path(info: "", before: nil) == nil)
    }

    @Test func aMentionIsTheWordAtTheEnd() {
        #expect(MentionToken.at(end: "look at @src/ma") == MentionToken(dir: "src", prefix: "ma", length: 7))
        #expect(MentionToken.at(end: "@") == MentionToken(dir: "", prefix: "", length: 1))
        #expect(MentionToken.at(end: "mail me@x.com") == nil)
        #expect(MentionToken.at(end: "@file then more") == nil)
    }

    @Test func theTreeShowsOpenFoldersOnly() {
        let root = FolderListing(dir: "", entries: [FolderEntry(name: "src", dir: true), FolderEntry(name: "a.md", dir: false)])
        let src = FolderListing(dir: "src", entries: [FolderEntry(name: "main.rs", dir: false)])
        let folders = ["": root, "src": src]
        #expect(FilesTab.lines(folders, open: []).map(\.path) == ["src", "a.md"])
        #expect(FilesTab.lines(folders, open: ["src"]).map(\.path) == ["src", "src/main.rs", "a.md"])
    }

    @Test func aThinkingEntryIsParsed() {
        let k = EntryParser.kind(["type": "thinking", "text": "hmm"])
        #expect(k == .thinking("hmm"))
        #expect(EntryParser.kind(["type": "thinking", "text": ""]) == .hidden)
    }
}
