import AppKit
import SwiftUI

/// One row of a `CoreDropdown`.
public struct CoreDropdownItem: Identifiable {
    public let id = UUID()
    public let title: String
    public let symbol: String?
    public let destructive: Bool
    public let enabled: Bool
    /// A row that belongs to the one above it (a submenu's entry).
    public let indented: Bool
    /// The current value, in a `CoreSelect`: a check before the title and a light blue row.
    public let checked: Bool
    /// Quiet words at the right of the row.
    public let note: String?
    public let run: @MainActor () -> Void
    public init(
        _ title: String, symbol: String? = nil, destructive: Bool = false, enabled: Bool = true, indented: Bool = false,
        checked: Bool = false, note: String? = nil, run: @escaping @MainActor () -> Void
    ) {
        self.title = title
        self.symbol = symbol
        self.destructive = destructive
        self.enabled = enabled
        self.indented = indented
        self.checked = checked
        self.note = note
        self.run = run
    }
}

/// A glass dropdown (Ahmed, 2026-11-06: menus are glass, not the system's): a button that toggles a small panel under it,
/// the one frame, with a row per item. Hover tints a row; ↑ ↓ move the highlight, Return runs it, Esc or a click outside
/// closes. The panel fades in and rises a few points. Right-click menus stay native.
public struct CoreDropdown<Label: View>: View {
    @Environment(\.coreAccent) private var accent
    let items: [CoreDropdownItem]
    let label: Label
    let isPresented: Binding<Bool>?
    @State private var ownOpen = false
    @State private var selected = 0
    @State private var hovered: UUID?
    @State private var monitor: Any?
    @State private var triggerFrame = CGRect.zero
    @State private var panelFrame = CGRect.zero
    @State private var menuID = UUID()
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.coreMenuHost) private var host

    /// `isPresented` lets the owner see (and set) whether the panel is open, e.g. to keep its trigger visible.
    public init(items: [CoreDropdownItem], isPresented: Binding<Bool>? = nil, @ViewBuilder label: () -> Label) {
        self.items = items
        self.isPresented = isPresented
        self.label = label()
    }

    private var open: Bool {
        get { isPresented?.wrappedValue ?? ownOpen }
        nonmutating set {
            if let isPresented { isPresented.wrappedValue = newValue } else { ownOpen = newValue }
        }
    }

    public var body: some View {
        Button {
            open.toggle()
        } label: {
            label
        }
        .buttonStyle(.plain)
        .background(
            GeometryReader { g in
                Color.clear.onChange(of: g.frame(in: .global), initial: true) { _, f in triggerFrame = f }
            }
        )
        // The window's menu layer draws the panel above everything, below or above this button, wherever it fits.
        .anchorPreference(key: MenuRequestKey.self, value: .bounds) { a in
            open && host ? [MenuRequest(id: menuID, anchor: a, height: estimatedHeight, panel: AnyView(panel))] : []
        }
        // No menu layer above (a view outside coreTheme): the panel opens in place, under the button.
        .overlay(alignment: .bottomTrailing) {
            if open && !host {
                panel
                    .alignmentGuide(.bottom) { d in d[.top] - Space.s1 }
                    .transition(.opacity.combined(with: .offset(y: coreMove(reduce, -Space.s1))))
            }
        }
        .animation(Motion.out(Motion.ui), value: open)
        .onChange(of: open) { _, now in
            if now {
                selected = items.firstIndex { $0.checked && $0.enabled } ?? items.firstIndex { $0.enabled } ?? 0
                listen()
            } else {
                stop()
            }
        }
        .onDisappear { stop() }
        .coreEscape(active: open) {
            open = false
            return true
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in row(item, on: i == selected) }
        }
        .padding(Space.s1)
        .frame(minWidth: max(Space.s8 * 6, triggerFrame.width), alignment: .leading)
        .fixedSize()
        .coreFrame(radius: Radius.cardMac + Space.s1, rim: Space.s1, part: .dropdowns)
        .shadow(color: GlassInk.shade(0.3), radius: 24, y: 8)
        .background(
            GeometryReader { g in
                Color.clear.onChange(of: g.frame(in: .global), initial: true) { _, f in panelFrame = f }
            }
        )
        .accessibilityElement(children: .contain)
    }

    private func row(_ item: CoreDropdownItem, on: Bool) -> some View {
        Button {
            choose(item)
        } label: {
            HStack(spacing: Space.s2) {
                if checks {
                    Image(systemName: "checkmark").coreFont(size: MacTextSize.meta, weight: .bold)
                        .foregroundStyle(GlassInk.accentInk(accent)).frame(width: Space.s3).opacity(item.checked ? 1 : 0)
                        .accessibilityHidden(true)
                }
                if let symbol = item.symbol {
                    Image(systemName: symbol).coreFont(size: MacTextSize.body, weight: .medium)
                        .frame(width: Space.s4).accessibilityHidden(true)
                }
                Text(item.title).coreFont(size: MacTextSize.body).lineLimit(1)
                Spacer(minLength: Space.s3)
                if let note = item.note {
                    Text(note).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                }
            }
            .foregroundStyle(item.destructive ? GlassInk.red : GlassInk.primary)
            .padding(.leading, item.indented ? Space.s4 : 0)
            .padding(.horizontal, Space.s3)
            .frame(height: MacSize.controlMd + Space.s1)
            .background(
                on || hovered == item.id
                    ? GlassInk.wellHover : item.checked ? GlassInk.accent(accent).opacity(0.22) : .clear,
                in: coreShape(Radius.control)
            )
            .contentShape(coreShape(Radius.control))
        }
        .buttonStyle(.plain)
        .coreDimWhenDisabled(item.enabled)
        .disabled(!item.enabled)
        .onHover { inside in hovered = inside ? item.id : (hovered == item.id ? nil : hovered) }
        .animation(Motion.out(Motion.hover), value: hovered)
        .accessibilityAddTraits(on || item.checked ? .isSelected : [])
    }

    private var checks: Bool { items.contains { $0.checked } }

    /// The panel's height before it is drawn: rows, gaps, padding and rim. Decides whether it opens below or above.
    private var estimatedHeight: CGFloat {
        let n = CGFloat(items.count)
        return n * (MacSize.controlMd + Space.s1) + max(n - 1, 0) * Space.s1 + Space.s1 * 4
    }

    private func choose(_ item: CoreDropdownItem) {
        open = false
        item.run()
    }

    private func move(_ step: Int) {
        guard !items.isEmpty else { return }
        var i = selected
        for _ in items.indices {
            i = (i + step + items.count) % items.count
            if items[i].enabled { break }
        }
        selected = i
    }

    private func listen() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [
            .keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel,
        ]) { e in
            // Scrolling closes it, as a Mac menu does: the button may be leaving the screen.
            if e.type == .scrollWheel {
                open = false
                return e
            }
            if e.type != .keyDown {
                // A click outside both the button and the panel closes it, and still reaches what was clicked.
                let height = e.window?.contentView?.bounds.height ?? 0
                let p = CGPoint(x: e.locationInWindow.x, y: height - e.locationInWindow.y)
                if !triggerFrame.contains(p) && !panelFrame.contains(p) { open = false }
                return e
            }
            switch e.keyCode {
            case 125: move(1)  // ↓
            case 126: move(-1)  // ↑
            case 36, 76:  // Return, Enter
                if items.indices.contains(selected), items[selected].enabled { choose(items[selected]) }
            default: return e
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// A menu a dropdown asks the window's menu layer to draw (Ahmed, 2026-11-15: open below or above, wherever it fits).
struct MenuRequest: Identifiable {
    let id: UUID
    let anchor: Anchor<CGRect>
    let height: CGFloat
    let panel: AnyView
}

struct MenuRequestKey: PreferenceKey {
    static var defaultValue: [MenuRequest] { [] }
    static func reduce(value: inout [MenuRequest], nextValue: () -> [MenuRequest]) { value += nextValue() }
}

extension EnvironmentValues {
    /// Set by the window's menu layer (`coreTheme`): dropdowns below it hand it their panel.
    @Entry var coreMenuHost = false
}

extension View {
    /// The window's menu layer: every open dropdown drawn above all content, so no card or scroll view clips or covers it.
    func coreMenuLayer() -> some View {
        environment(\.coreMenuHost, true)
            .overlayPreferenceValue(MenuRequestKey.self) { requests in
                GeometryReader { g in
                    ForEach(requests) { r in
                        MenuPlacement(rect: g[r.anchor], bounds: g.size, height: r.height, panel: r.panel)
                            .transition(.opacity)
                    }
                }
            }
    }
}

/// Puts a menu under its button when it fits (or when there is more room below), else above it; lined up with the
/// button's leading edge, or its trailing edge when the leading side has no room.
struct MenuPlacement: View {
    let rect: CGRect
    let bounds: CGSize
    let height: CGFloat
    let panel: AnyView
    var body: some View {
        let gap = Space.s1
        let roomBelow = bounds.height - rect.maxY - gap
        let roomAbove = rect.minY - gap
        let below = roomBelow >= height + Space.s2 || roomBelow >= roomAbove
        let leading = bounds.width - rect.minX >= Space.s8 * 10
        panel
            .frame(
                width: max(leading ? bounds.width - rect.minX : rect.maxX, 1), alignment: leading ? .leading : .trailing
            )
            .frame(height: max(below ? roomBelow : roomAbove, 1), alignment: below ? .top : .bottom)
            .offset(x: leading ? rect.minX : 0, y: below ? rect.maxY + gap : 0)
    }
}
