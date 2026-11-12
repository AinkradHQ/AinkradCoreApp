import Foundation

/// How many tokens a model reads at once, for the side panel's Context bar. The Core exposes no such figure (its price data has
/// none), so this is a small table keyed by what the model id contains; an id it does not know gets 200K.
enum ContextWindow {
    static let fallback: Int64 = 200_000

    static func tokens(model: String?) -> Int64 {
        let id = (model ?? "").lowercased()
        // Claude's long-context variants carry `[1m]` or `-1m` in the id.
        if id.contains("[1m]") || id.contains("-1m") { return 1_000_000 }
        if id.contains("gemini") { return 1_000_000 }
        if id.contains("gpt-5") || id.contains("codex") { return 400_000 }
        return fallback
    }
}
