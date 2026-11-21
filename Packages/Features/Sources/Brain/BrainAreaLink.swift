/// Where the top bar's Brain counts land (`me`, `rules`, `knowledge`, `timeline`, `places`, and `inbox`, `sources`,
/// `activity`): the sidebar section of the same name. Anything else opens Home.
enum BrainAreaLink {
    static let areas: Set<String> = ["me", "rules", "knowledge", "timeline", "places", "inbox", "sources", "activity"]

    static func tab(for area: String) -> BrainTab {
        guard areas.contains(area) else { return .overview }
        return area == "places" ? .rooms : BrainTab(rawValue: area) ?? .overview
    }
}
