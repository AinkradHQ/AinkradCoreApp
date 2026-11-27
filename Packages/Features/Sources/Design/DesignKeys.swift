import CoreUI
import SwiftUI

/// The Design pane's keys. Home: ⌘1…⌘5 pick the page, ⌘F or typing finds, the arrows move over the cards, ⏎ opens, ⌘N (the
/// shell's New, through the pane's `onNew`) makes a new design and ⌥⌘N opens the advanced sheet, Esc clears the find. An
/// open item: Esc goes back, ⌘I shows or hides About.
extension DesignModel {
    /// What the wall shows now, in its order.
    /// On Library's Everything the wall groups by kind, so the keys follow that grouped order, not the newest-first one.
    var shown: [DesignItem] {
        let list = items(in: category)
        guard category == .library, filter.isEmpty else { return list }
        return DesignCategory.libraryKinds.flatMap { k in list.filter { $0.category == k } }
    }

    /// Moves the keyboard's card by `step` (±1 across, ±columns down and up). The first press lands on the first card.
    @discardableResult
    func move(_ step: Int) -> Bool {
        let list = shown
        guard !list.isEmpty else { return false }
        guard let at = list.firstIndex(where: { $0.id == selected }) else {
            selected = list[0].id
            return true
        }
        let next = at + step
        guard list.indices.contains(next) else { return false }
        selected = list[next].id
        return true
    }

    func key(_ press: KeyPress, find: FocusState<Bool>.Binding) -> KeyPress.Result {
        let cmd = press.modifiers.contains(.command)
        let c = press.characters.lowercased()
        if let p = presenter {
            switch press.key {
            case .escape: p.close()
            case .leftArrow, .upArrow: p.step(-1)
            case .rightArrow, .downArrow, .space: p.step(1)
            default: return .ignored
            }
            return .handled
        }
        if press.key == .escape {
            if aboutOpen {
                aboutOpen = false
                return .handled
            }
            if openID != nil {
                closeItem()
                return .handled
            }
            if !filter.isEmpty {
                filter = ""
                return .handled
            }
            if selected != nil {
                selected = nil
                return .handled
            }
            return .ignored
        }
        if openID != nil {
            guard cmd, c == "i" else { return .ignored }
            withAnimation(Motion.out(Motion.ui)) { aboutOpen.toggle() }
            return .handled
        }
        guard load == .ready else { return .ignored }
        if cmd, press.key != .delete {
            if c == "f" {
                find.wrappedValue = true
                return .handled
            }
            if let n = Int(c), (1...DesignCategory.pages.count).contains(n) {
                pick(DesignCategory.pages[n - 1])
                return .handled
            }
            return .ignored
        }
        if find.wrappedValue { return press.key == .return ? openSelectedOrFirst() : .ignored }
        if press.key == .delete, press.modifiers.contains(.command) || press.modifiers.isEmpty,
            let item = item(selected)
        {
            askDelete(item)
            return .handled
        }
        switch press.key {
        case .return: return openSelectedOrFirst()
        case .leftArrow: return move(-1) ? .handled : .ignored
        case .rightArrow: return move(1) ? .handled : .ignored
        case .upArrow: return move(-columns) ? .handled : .ignored
        case .downArrow: return move(columns) ? .handled : .ignored
        default: break
        }
        guard press.modifiers.subtracting(.shift).isEmpty else { return .ignored }
        if c.count == 1, c.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) {
            filter += press.characters
            selected = nil
            find.wrappedValue = true
            return .handled
        }
        return .ignored
    }

    private func openSelectedOrFirst() -> KeyPress.Result {
        guard let id = selected ?? shown.first?.id else { return .ignored }
        openItem(id)
        return .handled
    }
}
