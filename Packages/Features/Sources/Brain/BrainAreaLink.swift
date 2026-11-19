/// Where the top bar's Brain counts land (`me`, `rules`, `knowledge`, `timeline`, `places`). The calm Brain opens its own
/// page (`BrainModel.open(area:)` sets `calm.page = Page(rawValue: area)`); the console, which has no area pages, opens the overview.
enum BrainAreaLink {
    static let areas: Set<String> = ["me", "rules", "knowledge", "timeline", "places"]

    static func tab(for area: String) -> BrainTab { .overview }
}
