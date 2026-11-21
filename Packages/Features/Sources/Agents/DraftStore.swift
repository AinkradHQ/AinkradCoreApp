import Foundation

/// A half-written message survives a relaunch: the draft of each session is kept on this Mac (UserDefaults) as you type, and
/// put back when its composer opens with an empty field. Sending clears the field, which clears the kept draft.
enum DraftStore {
    private static func key(_ id: String) -> String { "agents.draft." + id }

    static func load(_ id: String) -> String { UserDefaults.standard.string(forKey: key(id)) ?? "" }

    static func save(_ id: String, _ text: String) {
        if text.isEmpty {
            UserDefaults.standard.removeObject(forKey: key(id))
        } else {
            UserDefaults.standard.set(text, forKey: key(id))
        }
    }
}
