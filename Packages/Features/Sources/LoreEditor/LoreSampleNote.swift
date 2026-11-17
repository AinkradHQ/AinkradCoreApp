import Foundation

/// A made-up ~10,000-word note (no real names, repos or data), generated deterministically: the latency and round-trip
/// fixture from the R0-01 prototypes, and the debug walk's page.
public enum LoreSampleNote {
    public static let noteTitles = ["Roadmap", "Reading list", "Garden plan", "Meeting notes", "Recipe ideas"]
    public static let markdown: String = build()

    private struct RNG {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
        mutating func pick<T>(_ a: [T]) -> T { a[int(a.count)] }
    }

    private static let nouns = [
        "lantern", "harbor", "paper", "copper", "garden", "river", "signal", "morning", "draft",
        "ledger", "window", "thread", "bridge", "orchard", "compass", "canvas", "meadow", "cabin",
        "workshop", "pattern", "rhythm", "letter", "kettle", "stone", "cedar", "ember", "tide",
        "field", "notebook", "shelf", "map", "season", "kitchen", "station", "valley", "studio",
        "printer", "margin", "chapter", "sketch", "routine", "table", "desk", "path", "harvest",
    ]
    private static let verbs = [
        "holds", "keeps", "shapes", "follows", "gathers", "carries", "softens", "frames", "marks",
        "opens", "settles", "invites", "slows", "lifts", "guides", "returns", "rewards", "needs",
    ]
    private static let adjs = [
        "quiet", "warm", "steady", "small", "patient", "early", "simple", "careful", "bright",
        "plain", "gentle", "honest", "clear", "slow", "open", "familiar", "light", "calm",
    ]
    private static let glue = ["and", "but", "while", "because", "so", "until", "before", "after", "as"]
    private static let titles = [
        "Opening notes", "The workshop", "Morning routine", "Paper and ink", "Tools we keep",
        "A slower week", "Small decisions", "The garden table", "Reading by the window",
        "What the ledger says", "Kitchen experiments", "Station notes", "Walking the river",
        "Margins and drafts", "Harvest plans", "Letters to send", "The copper kettle",
        "Evening review", "The long table", "Notes on rhythm",
    ]

    private static func build() -> String {
        var r = RNG(state: 42)
        func sentence() -> String {
            var w: [String] = []
            for i in 0..<(7 + r.int(9)) {
                switch i % 4 {
                case 0: w.append("the " + r.pick(adjs) + " " + r.pick(nouns))
                case 1: w.append(r.pick(verbs))
                case 2: w.append(r.pick(nouns))
                default: w.append(r.pick(glue))
                }
            }
            if ["and", "but", "while", "because", "so", "until", "before", "after", "as"].contains(w.last!) {
                w.removeLast()
            }
            let s = w.joined(separator: " ")
            return s.prefix(1).uppercased() + s.dropFirst() + "."
        }
        func paragraph(_ decorate: Bool) -> String {
            var ss = (0..<(4 + r.int(3))).map { _ in sentence() }
            if decorate {
                switch r.int(6) {
                case 0: ss.insert("Keep the **\(r.pick(adjs)) \(r.pick(nouns))** close at hand.", at: 1)
                case 1: ss.insert("It felt *\(r.pick(adjs))* in a good way.", at: 1)
                case 2: ss.insert("The setting is called `\(r.pick(nouns))_\(r.pick(nouns))` in the notes.", at: 2)
                case 3: ss.insert("More in [[\(r.pick(noteTitles))]].", at: 2)
                case 4:
                    ss.insert(
                        "A reference lives at https://example.com/\(r.pick(nouns))/\(r.pick(nouns)) for later.", at: 1)
                default:
                    ss.insert("Read [the \(r.pick(nouns)) guide](https://example.org/\(r.pick(nouns))) first.", at: 2)
                }
            }
            return ss.joined(separator: " ")
        }
        func item() -> String { "\(r.pick(adjs).capitalized) \(r.pick(nouns)) \(r.pick(verbs)) the \(r.pick(nouns))" }

        var out = ["# Field notes: the Lantern Workshop", "", paragraph(true), ""]
        for i in 0..<36 {
            out += [
                "## \(titles[i % titles.count])\(i >= titles.count ? ", again" : "")", "", paragraph(true), "",
                paragraph(i % 2 == 0), "",
            ]
            switch i % 5 {
            case 0:
                out += ["- \(item())", "- \(item())", "  - \(item())", "  - \(item())", "- \(item())", ""]
            case 1:
                out += ["- [x] \(item())", "- [ ] \(item())", "- [ ] \(item())", "- [x] \(item())", ""]
            case 2:
                out += ["> \(sentence()) \(sentence())", ""]
            case 3:
                out += [
                    "```swift", "let \(r.pick(nouns)) = Lantern(\"\(r.pick(adjs))\")",
                    "for page in notebook.pages where page.isDraft {",
                    "    page.settle(after: .seconds(\(r.int(9) + 1)))", "}", "```", "",
                ]
            default:
                out += ["1. \(item())", "2. \(item())", "3. \(item())", ""]
            }
            if i % 9 == 4 {
                out += [
                    "| Item | Owner | When |", "| --- | --- | --- |",
                    "| \(r.pick(nouns).capitalized) | \(r.pick(["Ana", "Ben", "Cleo", "Dov"])) | \(r.pick(["Mon", "Tue", "Wed", "Fri"])) |",
                    "| \(r.pick(nouns).capitalized) | \(r.pick(["Ana", "Ben", "Cleo", "Dov"])) | \(r.pick(["Mon", "Tue", "Wed", "Fri"])) |",
                    "",
                ]
            }
            if i % 3 == 0 { out += ["### A smaller thought", "", paragraph(true), ""] }
            out += [paragraph(true), ""]
        }
        return out.joined(separator: "\n")
    }
}
