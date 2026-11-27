import Foundation
import Observation

/// A note on a point of a mockup screen. `x` and `y` are fractions (0...1) of the page, so a pin survives a resize.
struct MockupPin: Identifiable, Equatable, Sendable {
    let id: UUID
    let screen: String
    var x: Double
    var y: Double
    var text: String
    var resolved = false
}

/// The review of one mockup package: pins per screen and a "reviewed" mark per screen, for the time the mockup is open.
/// The Core's comment and approval routes are keyed by a design's frame ids (`is_node_id`, 422 otherwise), and a mockup
/// package's screens are file paths, so nothing here can be saved to the Core: the viewer says "not saved" in its words.
/// `onChange` is the seam for when a mockup route exists.
@MainActor @Observable
final class MockupReview {
    private(set) var pins: [MockupPin] = []
    private(set) var approved: Set<String> = []
    /// Called after every change, with the whole state.
    @ObservationIgnored var onChange: (([MockupPin], Set<String>) -> Void)?

    func pins(on screen: String) -> [MockupPin] { pins.filter { $0.screen == screen } }

    @discardableResult
    func add(on screen: String, x: Double, y: Double, text: String = "") -> MockupPin {
        let pin = MockupPin(id: UUID(), screen: screen, x: min(max(x, 0), 1), y: min(max(y, 0), 1), text: text)
        pins.append(pin)
        changed()
        return pin
    }

    func edit(_ id: UUID, text: String) { update(id) { $0.text = text } }
    func resolve(_ id: UUID, _ on: Bool) { update(id) { $0.resolved = on } }
    func remove(_ id: UUID) {
        pins.removeAll { $0.id == id }
        changed()
    }

    func approve(_ screen: String) {
        approved.insert(screen)
        changed()
    }

    /// A later pin or edit on an approved screen does not unapprove it; re-approving is the only way to a new baseline (plan).
    func isApproved(_ screen: String) -> Bool { approved.contains(screen) }

    private func update(_ id: UUID, _ f: (inout MockupPin) -> Void) {
        guard let i = pins.firstIndex(where: { $0.id == id }) else { return }
        f(&pins[i])
        changed()
    }

    private func changed() { onChange?(pins, approved) }
}
