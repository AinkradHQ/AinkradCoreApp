import Testing

@testable import CoreUI

struct GFMTableTests {
    @Test(arguments: [
        "| --- | --- |", "|---|---|", "---|---", "--- | ---", "| :-- | --: |", ":-:|:-:", "|-|-|", "| --- |", "|---",
    ])
    func separators(_ line: String) { #expect(GFMTable.isSeparator(line)) }

    @Test(arguments: ["", "|", "| a | b |", "::-", "-:-", "| -x- |", "text --- text", "|  |  |"])
    func notSeparators(_ line: String) { #expect(!GFMTable.isSeparator(line)) }

    @Test func cellsKeepEscapedPipesAndDropEdgePipes() {
        #expect(GFMTable.cells("| a | b |") == ["a", "b"])
        #expect(GFMTable.cells("a | b") == ["a", "b"])
        #expect(GFMTable.cells("| a \\| b | c |") == ["a \\| b", "c"])
        #expect(GFMTable.cells("| a | |") == ["a", ""])
    }

    @Test func alignmentsComeFromTheColons() {
        #expect(GFMTable.alignments("|:--|:-:|--:|---|") == [.leading, .center, .trailing, .leading])
    }

    @Test func extentCoversHeaderSeparatorAndRows() {
        let md = ["| a | b |", "| - | - |", "| 1 | 2 |", "| 3 | 4 |", "", "after | pipe"]
        #expect(GFMTable.extent(md, at: 0) == 4)
        // Edge pipes are optional, and so is the pipe in a row, but not in the header.
        #expect(GFMTable.extent(["a | b", "--|--", "1 | 2"], at: 0) == 3)
        #expect(GFMTable.extent(["a | b", "--|--", "no pipes here"], at: 0) == 2)
    }

    @Test func notATable() {
        #expect(GFMTable.extent(["| a | b |"], at: 0) == nil)  // no separator
        #expect(GFMTable.extent(["| a | b |", "| --- |"], at: 0) == nil)  // cell counts differ
        #expect(GFMTable.extent(["a b", "---"], at: 0) == nil)  // a heading underline, no pipe in the header
        #expect(GFMTable.extent(["a | b", "text"], at: 0) == nil)
    }
}
