/// Where the top bar's Brain counts land (`me`, `rules`, `knowledge`, `timeline`, `places`). This branch has no area pages
/// yet, so every area opens the overview; E9's calm Brain (`BrainCalmModel.Page`, same raw values) replaces `tab(for:)`
/// with `calm.page = Page(rawValue: area)` at the epic merge, and nothing else changes.
enum BrainAreaLink {
    static let areas: Set<String> = ["me", "rules", "knowledge", "timeline", "places"]

    static func tab(for area: String) -> BrainTab { .overview }
}
