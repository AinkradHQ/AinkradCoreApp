#if DEBUG
// Debug only: the editor tools' scenes of the Lore walk (selection bar, block menu, insert menu, inserted blocks, the
// outline following the page).
import AppKit
import LoreEditor
import SwiftUI

extension LoreDemo {
    static let toolScenes = [
        "tools-selection", "tools-blocks", "tools-slash", "tools-table", "tools-checklist", "tools-image",
        "tools-outline", "blank-left-hidden", "blank-right-hidden", "blank-sides-hidden", "blank-focus",
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
        case "blank-left-hidden", "blank-right-hidden", "blank-sides-hidden", "blank-focus":
            // The blank page with the sidebars in each combination: the header, the prompt and the key line stay whole.
            await show("today-blank")
            if scene == "blank-focus" {
                model.toggleFocus()
            } else {
                model.showLeft = scene == "blank-right-hidden"
                model.showRight = scene == "blank-left-hidden"
            }
            await settle()
        default: break
        }
    }
}

extension LoreDemo {
    /// The Lore space alone in a plain window of `size`, for the walk's window sizes (the app itself is full screen
    /// only). The page's editor moves into this window, so the walk does this last.
    public func window(_ size: CGSize) -> NSWindow {
        let w = NSWindow(
            contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .fullSizeContentView],
            backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: LoreView(model: model).frame(width: size.width, height: size.height))
        w.setFrame(NSRect(origin: .zero, size: size), display: true)
        w.orderFrontRegardless()
        return w
    }

    /// A note with a title far longer than the header has room for.
    public func longTitle() async {
        await model.openNote("ln_demolongnote")
        var n = model.note
        n?.title = "Planting plan for the community garden beds, the shed by the fence and the August open day"
        model.apply(n)
    }

    public func sides(_ left: Bool, _ right: Bool) {
        model.showLeft = left
        model.showRight = right
    }

    public var textView: NSTextView? { model.editor?.scrollView.documentView as? NSTextView }

    /// A note of `sections` × 6 lines on the page, the caret in its middle and latency counting from zero.
    public func loadLong(_ sections: Int) {
        var md = ""
        for i in 0..<sections {
            md +=
                "## Section \(i)\n\nA line about the garden, number \(i), with **bold** words.\n\n- item\n- [ ] task\n"
        }
        model.page.show(md, fold: false)
        if let tv = textView {
            tv.setSelectedRange(NSRange(location: (tv.string as NSString).length / 2, length: 0))
            tv.scrollRangeToVisible(tv.selectedRange())
        }
        model.editor?.resetLatency()
    }

    public var latency: String {
        guard let l = model.editor?.latency else { return "none" }
        return String(format: "p50 %.2f ms · p95 %.2f ms · %d keys", l.p50, l.p95, l.n)
    }
}
#endif
