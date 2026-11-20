import Foundation
import Testing

@testable import Agents

@MainActor
struct TodoStripTests {
    private func todos(_ s: [TodoItem.Status]) -> [TranscriptEntry] {
        [
            TranscriptEntry(
                seq: 1, at: Date(timeIntervalSince1970: 0),
                kind: .toolTodos(id: "t", items: s.map { TodoItem(text: "step", status: $0) }))
        ]
    }

    @Test func theStripShowsOnlyAnUnfinishedList() {
        #expect(TodoStrip.items([]) == nil)
        #expect(TodoStrip.items(todos([.completed, .completed])) == nil)
        #expect(TodoStrip.items(todos([.completed, .inProgress]))?.count == 2)
    }
}
