#if DEBUG
// Debug only: the editor tools' scenes of the Lore walk (selection bar, block menu, insert menu, inserted blocks, the
// outline following the page).
import LoreEditor

extension LoreDemo {
    static let toolScenes = [
        "tools-selection", "tools-blocks", "tools-slash", "tools-table", "tools-checklist", "tools-image",
        "tools-outline",
    ]

    func showTools(_ scene: String) async {
        guard let editor = model.editor else { return }
        func settle() async { try? await Task.sleep(for: .milliseconds(500)) }
        switch scene {
        case "tools-selection", "tools-blocks":
            await model.openDay(model.todayKey)
            await settle()
            editor.demoSelect("small notes every day")
            if scene == "tools-blocks" {
                await settle()
                editor.demoBlockMenu()
            }
        case "tools-slash":
            await model.openDay(model.todayKey)
            await settle()
            editor.demoSlash("li")
        case "tools-table":
            await model.openDay(model.todayKey)
            await settle()
            editor.demoInsert(.table)
        case "tools-checklist":
            await model.openNote("ln_demoprojecta")
            await settle()
            editor.demoTick("Add the plot map")
        case "tools-image":
            await model.openNote("ln_demoprojecta")
            await settle()
            editor.demoImage("Plot map", "https://example.com/plot-map.png")
        case "tools-outline":
            await model.openNote("ln_demolongnote")
            await settle()
            if let h = model.outline.first(where: { $0.title == "Bed three: greens" }) { model.reveal(h) }
        default: break
        }
    }
}
#endif
