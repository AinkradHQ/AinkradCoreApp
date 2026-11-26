// LoreTextMenu — what the page's context menu and previews may do (T9: nothing is fetched or sent out), and the typing
// latency ring. Kept apart so the text view stays about typing.
import AppKit

extension LoreTextView {
    // MARK: no previews, no Look Up on links (T9: nothing is fetched)

    /// Force click and a three-finger tap would show a live web preview of a link, which loads the page.
    override func quickLook(with event: NSEvent) {}

    /// Look Up on a link shows a web preview too; on plain words it stays (the dictionary is local).
    override func showDefinition(for attrString: NSAttributedString?, at textBaselineOrigin: NSPoint) {
        if let a = attrString, a.length > 0 {
            var hasLink = false
            a.enumerateAttribute(.link, in: NSRange(location: 0, length: a.length)) { v, _, stop in
                if v != nil {
                    hasLink = true
                    stop.pointee = true
                }
            }
            if hasLink { return }
        }
        super.showDefinition(for: attrString, at: textBaselineOrigin)
    }

    /// A copy: `NSTextView.defaultMenu` is shared by every text view in the app and must not lose items.
    override func menu(for event: NSEvent) -> NSMenu? {
        (super.menu(for: event)?.copy() as? NSMenu).map(Self.safeMenu)
    }

    /// AppKit adds Look Up, Open Link, Share and Services after `menu(for:)`; filter again right before it shows.
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        _ = Self.safeMenu(menu)
    }

    /// The context menu without the items that open, preview or send text out on their own: Open Link (it bypasses the
    /// link policy), Look Up, Search With, Share, Services, Writing Tools. A link still opens by click, through the policy.
    static func safeMenu(_ menu: NSMenu) -> NSMenu {
        // By action selector only, so it works in every language (titles are localised).
        let blocked = ["openlink", "lookup", "searchwith", "share", "service", "writingtools", "translat", "quicklook"]
        for item in menu.items.reversed() {
            let key = (item.action.map(NSStringFromSelector) ?? "").lowercased()
            if blocked.contains(where: key.contains) || (item.submenu != nil && item.submenu === NSApp?.servicesMenu) {
                menu.removeItem(item)
            } else if let sub = item.submenu {
                _ = safeMenu(sub)
                if sub.items.isEmpty { menu.removeItem(item) }
            }
        }
        // No separator left first, last or doubled.
        while menu.items.first?.isSeparatorItem == true { menu.removeItem(at: 0) }
        while menu.items.last?.isSeparatorItem == true { menu.removeItem(at: menu.items.count - 1) }
        for i in stride(from: menu.items.count - 1, to: 0, by: -1)
        where menu.items[i].isSeparatorItem && menu.items[i - 1].isSeparatorItem {
            menu.removeItem(at: i)
        }
        return menu
    }
}

/// Typing latency over the last 200 keystrokes (key press → visible text laid out again).
struct LoreLatency {
    private var ring: [Double] = []

    mutating func record(_ seconds: Double) {
        ring.append(seconds * 1000)
        if ring.count > 200 { ring.removeFirst(ring.count - 200) }
    }

    mutating func reset() { ring.removeAll() }

    /// Milliseconds.
    var stats: (p50: Double, p95: Double, n: Int) {
        guard !ring.isEmpty else { return (0, 0, 0) }
        let s = ring.sorted()
        func pct(_ p: Double) -> Double { s[min(s.count - 1, Int((Double(s.count - 1) * p).rounded()))] }
        return (pct(0.5), pct(0.95), s.count)
    }
}
