import CoreKit
import CoreUI
import Foundation
import Observation
import Shell
import SwiftUI

/// What `GET /me` and the session say about this Core and this device.
struct CoreAbout: Equatable, Sendable {
    let server: String
    let apiMajor: String
    let apiMinor: Int
    let build: String?
    let device: String
    let scopes: [String]
    var isAdmin: Bool { scopes.contains("admin") }
}

/// Settings, Core, Devices (top of the page): read again whenever a connection opens. The model owns no business logic, only the last answer.
@MainActor @Observable
final class AboutModel {
    enum State: Equatable {
        case idle, loading
        case ready(CoreAbout)
        case failed(String)
    }
    private(set) var state: State = .idle
    @ObservationIgnored private var fetch: (@Sendable () async throws -> CoreAbout)?

    func use(_ fetch: (@Sendable () async throws -> CoreAbout)?) {
        self.fetch = fetch
        state = fetch == nil ? .idle : .loading
    }

    /// The scopes, once read; nil until then.
    var about: CoreAbout? { if case .ready(let a) = state { a } else { nil } }

    @discardableResult
    func reload() async -> CoreAbout? {
        guard let fetch else { return nil }
        if about == nil { state = .loading }
        do {
            let a = try await fetch()
            state = .ready(a)
            return a
        } catch {
            state = .failed(CoreError.unwrapping(error)?.localizedDescription ?? "The Core did not answer.")
            return nil
        }
    }

    #if DEBUG
    func debugSet(_ s: State) { state = s }
    #endif
}

enum AboutWords {
    /// Scopes in the order the app lists them, then any this build does not know.
    static func scopes(_ held: [String]) -> [String] {
        ScopeText.all.filter(held.contains) + ["runner"].filter(held.contains)
            + held.filter { !ScopeText.all.contains($0) && $0 != "runner" }
    }
    static func api(_ a: CoreAbout) -> String { "\(a.apiMajor).\(a.apiMinor)" }
}

/// Which Core this is and what this Mac may do on it: the block at the top of Settings, Devices.
struct AboutBlock: View {
    let app: AppModel

    var body: some View {
        let model = app.about
        VStack(alignment: .leading, spacing: Space.s4) {
            switch model.state {
            case .idle: EmptyView()
            case .loading: LoadNote(state: .loading) {}
            case .failed(let m): LoadNote(state: .failed(m)) { Task { await model.reload() } }
            case .ready(let a): details(a)
            }
        }
        .foregroundStyle(GlassInk.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await model.reload() }
        .accessibilityIdentifier("about-core")
    }

    private func details(_ a: CoreAbout) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top, spacing: Space.s3) {
                fact("shippingbox.fill", GlassInk.blue, "Core version", a.server, help: a.build.map { "Build \($0)" })
                fact("number", GlassInk.blue, "API", "Minor \(a.apiMinor)", help: "API \(AboutWords.api(a))")
                fact("laptopcomputer", GlassInk.blue, "This device", a.device, help: nil)
            }
            .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("What this device may do").coreFont(size: MacTextSize.headline, weight: .semibold)
                ForEach(AboutWords.scopes(a.scopes), id: \.self) { s in
                    HStack(spacing: Space.s2) {
                        Image(systemName: ScopeText.symbol(s)).foregroundStyle(ScopeText.hue(s)).frame(width: 22)
                            .accessibilityHidden(true)
                        Text(ScopeText.text(s))
                        Spacer(minLength: 0)
                    }
                    .help(s)
                }
                if !a.isAdmin {
                    Label(
                        "This device can't open the admin pages: settings, secrets, audit, ops and lockouts are hidden.",
                        systemImage: "lock"
                    )
                    .foregroundStyle(GlassInk.secondary).coreFont(size: MacTextSize.meta)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
            .background(GlassInk.well, in: coreShape(Radius.cardMac))
            .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
        }
    }

    private func fact(_ symbol: String, _ hue: Color, _ title: String, _ value: String, help: String?) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Label(title, systemImage: symbol).coreFont(size: MacTextSize.meta, weight: .semibold)
                .foregroundStyle(GlassInk.ink(hue))
            Text(value).coreFont(size: MacTextSize.title, weight: .semibold).lineLimit(2)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .topLeading)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
        .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
        .help(help ?? title)
    }
}
