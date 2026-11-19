import Foundation
import Testing

@testable import LoreEditor

struct LoreTableEditTests {
    let table = ["| A | B |", "| --- | --- |", "| 1 | 2 |", "| 3 | 4 |"]

    @Test func addRowGoesAfterTheCaretRowAndIsBlank() {
        let out = LoreTableEdit.apply(.addRow, lines: table, line: 2)
        #expect(out == ["| A | B |", "| --- | --- |", "| 1 | 2 |", "|  |  |", "| 3 | 4 |"])
        // On the header the first row is new.
        #expect(LoreTableEdit.apply(.addRow, lines: table, line: 0)?[2] == "|  |  |")
    }

    @Test func addColumnExtendsEveryLineIncludingTheSeparator() {
        let out = LoreTableEdit.apply(.addColumn, lines: table, line: 2)
        #expect(out?[0] == "| A | B | New |" && out?[1] == "| --- | --- | --- |" && out?[2] == "| 1 | 2 |  |")
    }

    @Test func deleteRowRemovesOnlyABodyRow() {
        #expect(LoreTableEdit.apply(.deleteRow, lines: table, line: 3)?.count == 3)
        #expect(LoreTableEdit.apply(.deleteRow, lines: table, line: 0) == nil)
        #expect(LoreTableEdit.apply(.deleteRow, lines: table, line: 1) == nil)
        #expect(LoreTableEdit.apply(.addRow, lines: ["no", "table"], line: 0) == nil)
    }

    @Test func aPageHoldsATableOnlyWithASeparatorRow() {
        #expect(LoreTableEdit.hasTable("intro\n\n| a | b |\n| --- | --- |\n| 1 | 2 |\n"))
        #expect(!LoreTableEdit.hasTable("| a | b |\nplain\n"))
    }
}
