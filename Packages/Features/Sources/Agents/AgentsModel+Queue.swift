import Foundation

/// A message typed while a turn runs.
public struct QueuedMessage: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var text: String
    /// Files attached with it; they go with the message.
    public var files: [URL]
    public init(id: UUID = UUID(), text: String, files: [URL] = []) {
        self.id = id
        self.text = text
        self.files = files
    }
}

/// Messages typed during a turn (Ahmed, 2026-11-16: "it should not be sent directly"). As in Claude Code, they wait above
/// the field, where each can be edited, sent now or removed, and go out together as one message when the turn ends.
extension AgentsModel {
    /// Takes the field's words (and attachments) into the queue.
    public func enqueue(_ id: String) {
        let text = (drafts[id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let files = attachments[id] ?? []
        guard !text.isEmpty || !files.isEmpty, text.utf8.count <= Self.messageLimit else { return }
        queued[id, default: []].append(QueuedMessage(text: text, files: files))
        drafts[id] = ""
        attachments[id] = nil
        flushQueues()
    }

    public func removeQueued(_ id: String, _ message: QueuedMessage.ID) {
        queued[id]?.removeAll { $0.id == message }
    }

    /// Back into the field to change it; what was typed there stays, after it.
    public func editQueued(_ id: String, _ message: QueuedMessage.ID) {
        guard let m = queued[id]?.first(where: { $0.id == message }) else { return }
        removeQueued(id, message)
        let typed = drafts[id] ?? ""
        drafts[id] = typed.isEmpty ? m.text : m.text + "\n\n" + typed
        attachments[id] = m.files + (attachments[id] ?? [])
    }

    /// ↑ on an empty field (the Claude CLI's key): every queued message back into the field, in order, to edit.
    public func editAllQueued(_ id: String) {
        guard let list = queued[id], !list.isEmpty else { return }
        queued[id] = []
        let typed = drafts[id] ?? ""
        drafts[id] = Self.joined(list) + (typed.isEmpty ? "" : "\n\n" + typed)
        attachments[id] = list.flatMap(\.files) + (attachments[id] ?? [])
    }

    /// Hands one queued message to the tool now, while the turn runs (it reads it at its next step).
    public func sendQueuedNow(_ id: String, _ message: QueuedMessage.ID) {
        guard let m = queued[id]?.first(where: { $0.id == message }) else { return }
        removeQueued(id, message)
        Task { [weak self] in
            if await self?.say(id, m.text, files: m.files) == false { self?.queued[id, default: []].insert(m, at: 0) }
        }
    }

    /// The turn is over: everything queued goes out as one message. If sending fails, it stays queued.
    func flushQueues() {
        for (id, list) in queued where !list.isEmpty {
            guard let s = sessions.session(id), s.live, s.idle, canReply(s), !sending.contains(id), !waiting(id)
            else { continue }
            queued[id] = []
            let text = Self.joined(list)
            let files = list.flatMap(\.files)
            Task { [weak self] in
                if await self?.say(id, text, files: files) == false {
                    self?.queued[id] = list + (self?.queued[id] ?? [])
                }
            }
        }
    }

    static func joined(_ list: [QueuedMessage]) -> String {
        list.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}
