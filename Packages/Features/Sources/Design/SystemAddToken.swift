import CoreUI
import SwiftUI

/// Add a token to a design system, and rename one. A token is `group.name`; the style guide shows five groups.
enum TokenGroup: String, CaseIterable, Identifiable {
    case color, type, space, radius, shadow
    var id: String { rawValue }
    var title: String {
        switch self {
        case .color: "Colour"
        case .type: "Type"
        case .space: "Spacing"
        case .radius: "Radius"
        case .shadow: "Shadow"
        }
    }
    /// The value a new token starts with, day and night.
    var starter: (day: DJSON, night: DJSON) {
        switch self {
        case .color: (.string("#2f6fec"), .string("#5b8ff5"))
        case .type:
            (
                .object(["size": .number(16), "weight": .number(400), "line": .number(24)]),
                .object(["size": .number(16), "weight": .number(400), "line": .number(24)])
            )
        case .space: (.number(16), .number(16))
        case .radius: (.number(8), .number(8))
        case .shadow:
            (
                .array([
                    .object([
                        "x": .number(0), "y": .number(4), "blur": .number(12), "spread": .number(0),
                        "color": .string("#00000029"),
                    ])
                ]),
                .array([
                    .object([
                        "x": .number(0), "y": .number(4), "blur": .number(12), "spread": .number(0),
                        "color": .string("#00000029"),
                    ])
                ])
            )
        }
    }
}

enum TokenRules {
    /// The Core's rule: lowercase segments joined by `.` or `-`, 1 to 64 bytes, starting with a letter.
    static func isTokenName(_ s: String) -> Bool {
        let b = Array(s.utf8)
        func ok(_ c: UInt8) -> Bool { (97...122).contains(c) || (48...57).contains(c) }
        guard (1...64).contains(b.count), (97...122).contains(b[0]), ok(b[b.count - 1]) else { return false }
        guard b.allSatisfy({ ok($0) || $0 == 46 || $0 == 45 }) else { return false }
        return !["..", "--", ".-", "-."].contains { s.contains($0) }
    }

    /// Nil when `short` can be added to `group`, else why not in words.
    static func problem(short: String, group: TokenGroup, existing: [SystemToken], renaming: String? = nil) -> String? {
        let t = short.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return nil }
        let full = "\(group.rawValue).\(t)"
        if !isTokenName(full) { return "Use lowercase letters, digits, dots and dashes: primary, brand-blue." }
        if full != renaming, existing.contains(where: { $0.name == full }) {
            return "There is already a token called \(full)."
        }
        return nil
    }

    /// Rename = remove the old name and add the same values under the new one, in one batch (one undo step).
    static func renameOps(_ t: SystemToken, to name: String) -> [[String: DJSON]] {
        [
            ["op": .string("token"), "name": .string(t.name), "value": .null],
            [
                "op": .string("token"), "name": .string(name),
                "value": .object(["kind": .string(t.kind), "day": t.day, "night": t.night]),
            ],
        ]
    }
}

extension DesignEditor {
    @discardableResult
    func renameToken(_ t: SystemToken, to name: String) -> Bool { apply(TokenRules.renameOps(t, to: name)) }
}

/// "Add token": group, name and values, then one write.
struct AddTokenSheet: View {
    let editor: DesignEditor
    let done: () -> Void
    @State private var group = TokenGroup.color
    @State private var short = ""
    @State private var day = TokenGroup.color.starter.day
    @State private var night = TokenGroup.color.starter.night

    private var problem: String? { TokenRules.problem(short: short, group: group, existing: editor.systemTokens) }
    private var name: String { "\(group.rawValue).\(short.trimmingCharacters(in: .whitespaces))" }
    private var valid: Bool { !short.trimmingCharacters(in: .whitespaces).isEmpty && problem == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Add a token").coreFont(size: MacTextSize.headline, weight: .semibold)
            CoreSelect(
                "Group", selection: $group, options: TokenGroup.allCases.map { CoreSelectOption($0, $0.title) }
            )
            CoreTextField("Name", placeholder: "brand-blue", text: $short, error: problem, mono: true) { add() }
            if valid { Text(name).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).monospaced() }
            values
            HStack {
                Spacer()
                Button("Add") { add() }.buttonStyle(CoreButtonStyle(.prominent)).coreShortcut(.primary)
                    .disabled(!valid || !editor.attached)
                    .help(editor.attached ? "Add the token to this system" : "The system is still opening")
            }
        }
        .padding(Space.s4).frame(width: Space.s8 * 12)
        .onChange(of: group) { _, g in
            day = g.starter.day
            night = g.starter.night
        }
        .accessibilityIdentifier("design-add-token")
    }

    @ViewBuilder private var values: some View {
        switch group {
        case .color:
            field("Day") { ColorField(hex: day.string) { day = .string($0) } }
            field("Night") { ColorField(hex: night.string) { night = .string($0) } }
        case .space, .radius:
            HStack(spacing: Space.s2) {
                InlineNumber(label: "Day pt", value: day.double) { day = .number(max(0, $0 ?? 0)) }
                InlineNumber(label: "Night pt", value: night.double) { night = .number(max(0, $0 ?? 0)) }
            }
        case .type:
            HStack(spacing: Space.s1) {
                InlineNumber(label: "Size", value: day["size"]?.double) { set("size", .number(max(1, $0 ?? 16))) }
                InlineNumber(label: "Weight", value: day["weight"]?.double) {
                    set("weight", .number(min(1000, max(1, ($0 ?? 400).rounded()))))
                }
                InlineNumber(label: "Line", value: day["line"]?.double) { set("line", .number(max(0, $0 ?? 24))) }
            }
        case .shadow:
            let s = day.array?.first ?? .object([:])
            HStack(spacing: Space.s1) {
                InlineNumber(label: "Y", value: s["y"]?.double) { shadow("y", .number($0 ?? 0)) }
                InlineNumber(label: "Blur", value: s["blur"]?.double) { shadow("blur", .number(max(0, $0 ?? 0))) }
            }
        }
    }

    private func field<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(title).coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(GlassInk.secondary)
            c()
        }
    }

    /// A type token has one literal for both themes, so its day value is copied to night.
    private func set(_ key: String, _ v: DJSON) {
        day = TokenEditor.merge(day, key, v)
        night = day
    }

    private func shadow(_ key: String, _ v: DJSON) {
        let s = TokenEditor.merge(day.array?.first ?? .object([:]), key, v)
        day = .array([s])
        night = day
    }

    private func add() {
        guard valid, editor.attached else { return }
        if editor.setToken(name, kind: group.rawValue, day: day, night: night) { done() }
    }
}
