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
    let items: [CoreDropdownItem]
    let label: Label
    let isPresented: Binding<Bool>?
    @State private var ownOpen = false
    @State private var selected = 0
    @State private var hovered: UUID?
    @State private var monitor: Any?
    @State private var triggerFrame = CGRect.zero
    @State private var panelFrame = CGRect.zero
    @Environment(\.accessibilityReduceMotion) private var reduce

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
        .overlay(alignment: .bottomTrailing) {
            if open {
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
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in row(item, on: i == selected) }
        }
        .padding(Space.s1)
        .frame(minWidth: max(Space.s8 * 6, triggerFrame.width), alignment: .leading)
        .fixedSize()
        .coreFrame(radius: Radius.cardMac + Space.s1, rim: Space.s1, part: .dropdowns)
        .shadow(color: .black.opacity(0.3), radius: 24, y: 8)
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
                    Image(systemName: "checkmark").font(.system(size: MacTextSize.meta, weight: .bold))
                        .foregroundStyle(GlassInk.blueInk).frame(width: Space.s3).opacity(item.checked ? 1 : 0)
                        .accessibilityHidden(true)
                }
                if let symbol = item.symbol {
                    Image(systemName: symbol).font(.system(size: MacTextSize.body, weight: .medium))
                        .frame(width: Space.s4).accessibilityHidden(true)
                }
                Text(item.title).font(.system(size: MacTextSize.body)).lineLimit(1)
                Spacer(minLength: Space.s3)
                if let note = item.note {
                    Text(note).font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
                }
            }
            .foregroundStyle(item.destructive ? GlassInk.red : GlassInk.primary)
            .padding(.leading, item.indented ? Space.s4 : 0)
            .padding(.horizontal, Space.s3)
            .frame(height: MacSize.controlMd + Space.s1)
            .background(
                on || hovered == item.id
                    ? GlassInk.wellHover : item.checked ? GlassInk.blue.opacity(0.22) : .clear,
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
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { e in
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
            case 53: open = false  // Esc
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
