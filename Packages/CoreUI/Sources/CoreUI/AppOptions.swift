import Observation
import SwiftUI

/// One app's own options (E2-4): small choices kept per Mac in UserDefaults under `appopt.<app>.<key>`. Settings writes them and
/// the app reads the same value where it acts, so a switch in Settings really changes the app. Reading inside a view body
/// re-draws it when a value changes.
@MainActor @Observable
public final class AppOptions {
    private static var all: [String: AppOptions] = [:]
    /// The one instance for an app id ("lore", "leyline", "design", "projects", "accounts", "connections", ...).
    public static func shared(_ app: String) -> AppOptions {
        if let o = all[app] { return o }
        let o = AppOptions(app: app)
        all[app] = o
        return o
    }

    private let app: String
    @ObservationIgnored private let d: UserDefaults
    /// Bumped by every write, so views that read a value are redrawn.
    private var revision = 0

    public init(app: String, defaults: UserDefaults = .standard) {
        self.app = app
        d = defaults
    }

    private func key(_ k: String) -> String { "appopt.\(app).\(k)" }

    public func bool(_ k: String, _ fallback: Bool) -> Bool {
        _ = revision
        return d.object(forKey: key(k)) as? Bool ?? fallback
    }

    public func string(_ k: String, _ fallback: String) -> String {
        _ = revision
        return d.string(forKey: key(k)) ?? fallback
    }

    public func set(_ k: String, _ value: Bool) {
        d.set(value, forKey: key(k))
        revision += 1
    }

    public func set(_ k: String, _ value: String) {
        d.set(value, forKey: key(k))
        revision += 1
    }

    public func flag(_ k: String, _ fallback: Bool) -> Binding<Bool> {
        Binding(get: { self.bool(k, fallback) }, set: { self.set(k, $0) })
    }

    public func text(_ k: String, _ fallback: String) -> Binding<String> {
        Binding(get: { self.string(k, fallback) }, set: { self.set(k, $0) })
    }
}

/// A switch row of an app's Options tab.
public struct OptionSwitchRow: View {
    let title: String
    let sub: String?
    let symbol: String?
    let isOn: Binding<Bool>
    public init(_ title: String, sub: String? = nil, symbol: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.sub = sub
        self.symbol = symbol
        self.isOn = isOn
    }
    public var body: some View {
        CoreRow(title, subtitle: sub, symbol: symbol, trailing: { CoreSwitch(title, isOn: isOn) })
    }
}

/// A pick-one row of an app's Options tab, as a menu.
public struct OptionSelectRow<Value: Hashable>: View {
    let title: String
    let sub: String?
    let symbol: String?
    let selection: Binding<Value>
    let options: [CoreSelectOption<Value>]
    public init(
        _ title: String, sub: String? = nil, symbol: String? = nil, selection: Binding<Value>,
        options: [CoreSelectOption<Value>]
    ) {
        self.title = title
        self.sub = sub
        self.symbol = symbol
        self.selection = selection
        self.options = options
    }
    public var body: some View {
        CoreRow(
            title, subtitle: sub, symbol: symbol,
            trailing: { CoreSelect(nil, selection: selection, options: options).frame(width: Space.s8 * 4) })
    }
}

/// A pick-one row for two or three short choices, as a segmented control.
public struct OptionSegmentRow<Value: Hashable & Sendable>: View {
    let title: String
    let sub: String?
    let symbol: String?
    let selection: Binding<Value>
    let segments: [CoreSegment<Value>]
    public init(
        _ title: String, sub: String? = nil, symbol: String? = nil, selection: Binding<Value>,
        segments: [CoreSegment<Value>]
    ) {
        self.title = title
        self.sub = sub
        self.symbol = symbol
        self.selection = selection
        self.segments = segments
    }
    public var body: some View {
        CoreRow(
            title, subtitle: sub, symbol: symbol,
            trailing: { CoreSegmented(title, segments: segments, selection: selection) })
    }
}
