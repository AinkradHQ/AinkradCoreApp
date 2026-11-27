import AppKit
import CoreUI
import Observation
import Projects
import SwiftUI
import WebKit

/// Loads one package into the sandbox (see MockupSandbox.swift for the security model) and tracks what the page shows.
@MainActor @Observable
final class MockupViewerModel {
    enum Phase: Equatable {
        case loading, ready
        case failed(String)
    }
    let doc: String
    let source: any MockupSource
    let review = MockupReview()
    private(set) var phase = Phase.loading
    private(set) var package: MockupPackage?
    /// The package path of the page now shown; follows click-through.
    private(set) var page = ""
    private(set) var blocked = false
    private(set) var web: WKWebView?
    var dark = true { didSet { web?.appearance = NSAppearance(named: dark ? .darkAqua : .aqua) } }
    var zoom2x = false { didSet { web?.pageZoom = zoom2x ? 2 : 1 } }
    var pinMode = false
    var selected: UUID?
    @ObservationIgnored private var handler: MockupSchemeHandler?
    @ObservationIgnored private var navigation: MockupNavigation?

    init(doc: String, source: any MockupSource) {
        self.doc = doc
        self.source = source
    }

    func load() async {
        phase = .loading
        do {
            let pkg = try await source.package(doc)
            guard let first = pkg.screens.first else { throw MockupFailure.noScreen }
            let handler = MockupSchemeHandler(package: pkg, source: source)
            let nav = MockupNavigation(package: pkg)
            nav.onPage = { [weak self] in self?.page = $0 }
            nav.onBlocked = { [weak self] _ in self?.blocked = true }
            let web = try await MockupSandbox.makeWebView(handler: handler, navigation: nav)
            web.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            package = pkg
            self.handler = handler
            navigation = nav
            self.web = web
            phase = .ready
            show(first)
        } catch let f as MockupFailure {
            phase = .failed(f.sentence)
        } catch {
            phase = .failed("The mockup could not be loaded.")
        }
    }

    func show(_ screen: MockupPackage.Screen, state: String? = nil) {
        guard let url = MockupSandbox.url(screen.path, state: state ?? screen.states.first) else { return }
        page = screen.path
        blocked = false
        selected = nil
        web?.load(URLRequest(url: url))
    }

    var screen: MockupPackage.Screen? { package?.screens.first { $0.path.lowercased() == page.lowercased() } }
    /// What review is keyed by: the manifest screen when the page is one, else the page path.
    var screenKey: String { screen?.path ?? page }
}

/// Hosts the sandboxed web view. The view is made once by the model; SwiftUI only places it.
struct MockupWebView: NSViewRepresentable {
    let web: WKWebView
    func makeNSView(context: Context) -> WKWebView { web }
    func updateNSView(_ view: WKWebView, context: Context) {}
}

/// The open mockup: its page in the sandbox, with the review layer (pins, approve) drawn over it in SwiftUI.
struct MockupStage: View {
    let model: DesignModel
    let doc: DesignDoc
    @State private var viewer: MockupViewerModel?
    @State private var screensOpen = false

    var body: some View {
        Group {
            if let viewer {
                content(viewer)
            } else if model.mockups == nil {
                CoreNotice(
                    symbol: "bolt.slash", title: "Not connected", text: "Connect to a Core to review this mockup.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: doc.id) {
            guard let source = model.mockups else { return }
            let v = MockupViewerModel(doc: doc.id, source: source)
            viewer = v
            await v.load()
        }
        .accessibilityIdentifier("mockup-stage")
    }

    @ViewBuilder private func content(_ v: MockupViewerModel) -> some View {
        switch v.phase {
        case .loading:
            CoreWorkingBar().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let sentence):
            CoreNotice(
                symbol: "exclamationmark.triangle", title: "Cannot show this mockup", text: sentence, tone: .warn
            ) {
                Button("Try Again") { Task { await v.load() } }.buttonStyle(.coreSecondary)
            }
        case .ready:
            VStack(spacing: Space.s2) {
                controls(v)
                HStack(alignment: .top, spacing: Space.s2) {
                    if let web = v.web {
                        MockupWebView(web: web)
                            .clipShape(coreShape(Radius.cardMac))
                            .overlay { PinLayer(viewer: v, readOnly: model.readOnly) }
                            .accessibilityLabel("Mockup page")
                    }
                    PinList(viewer: v, readOnly: model.readOnly).frame(width: Space.s8 * 8)
                }
            }
        }
    }

    private func controls(_ v: MockupViewerModel) -> some View {
        HStack(spacing: Space.s2) {
            CoreDropdown(
                items: (v.package?.screens ?? []).map { s in
                    CoreDropdownItem(s.name, symbol: "doc", checked: s.path == v.screen?.path) { v.show(s) }
                },
                isPresented: $screensOpen
            ) {
                Label(v.screen?.name ?? "Screens", systemImage: "rectangle.on.rectangle")
            }
            .help("Choose a screen of this mockup")
            CoreSegmented(
                "Theme", segments: [CoreSegment(false, "Day"), CoreSegment(true, "Night")],
                selection: Binding(get: { v.dark }, set: { v.dark = $0 }))
            CoreSegmented(
                "Scale", segments: [CoreSegment(false, "1×"), CoreSegment(true, "2×")],
                selection: Binding(get: { v.zoom2x }, set: { v.zoom2x = $0 }))
            if v.blocked {
                Label("Blocked a link out of the mockup", systemImage: "hand.raised").foregroundStyle(
                    GlassInk.secondary)
            }
            Spacer(minLength: 0)
            Button {
                v.pinMode.toggle()
            } label: {
                Label(v.pinMode ? "Done Pinning" : "Add Pin", systemImage: "mappin")
            }
            .buttonStyle(.coreSecondary)
            .disabled(model.readOnly)
            .help("Click a point of the page to leave a note there")
            // The Core's approvals and comments belong to a design's frames, so a mockup page has nowhere to save one:
            // the review lasts while this mockup is open, and the words say so instead of claiming "Approved".
            if v.review.isApproved(v.screenKey) {
                Label("Reviewed (not saved)", systemImage: "checkmark.circle").foregroundStyle(GlassInk.secondary)
                    .help("Kept only while this mockup is open. The Core cannot save a mockup review yet.")
            } else {
                Button("Mark Reviewed") { v.review.approve(v.screenKey) }
                    .buttonStyle(.coreProminent)
                    .help(
                        "Mark this screen reviewed. Kept only while this mockup is open; the Core cannot save it yet.")
            }
        }
        .frame(minHeight: MacSize.controlMd)
    }
}

/// The pins over the page. In pin mode a click on the page drops a pin (the page gets no click); otherwise only the markers
/// take clicks and everything else reaches the mockup, so click-through works.
private struct PinLayer: View {
    let viewer: MockupViewerModel
    let readOnly: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if viewer.pinMode && !readOnly {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture(coordinateSpace: .local) { p in
                            let pin = viewer.review.add(
                                on: viewer.screenKey, x: p.x / max(geo.size.width, 1), y: p.y / max(geo.size.height, 1))
                            viewer.selected = pin.id
                            viewer.pinMode = false
                        }
                }
                ForEach(Array(viewer.review.pins(on: viewer.screenKey).enumerated()), id: \.element.id) { i, pin in
                    Button {
                        viewer.selected = pin.id
                    } label: {
                        CountBadge(i + 1, tone: pin.resolved ? .quiet : pin.id == viewer.selected ? .needsYou : .accent)
                    }
                    .buttonStyle(.plain)
                    .position(x: pin.x * geo.size.width, y: pin.y * geo.size.height)
                    .help(pin.text.isEmpty ? "Pin \(i + 1)" : pin.text)
                    .accessibilityLabel("Pin \(i + 1)")
                }
            }
        }
    }
}

/// The notes of the shown screen; the selected one is editable.
private struct PinList: View {
    let viewer: MockupViewerModel
    let readOnly: Bool

    var body: some View {
        let pins = viewer.review.pins(on: viewer.screenKey)
        Island("Notes") {
            if pins.isEmpty {
                Text("No notes yet. Use Add Pin, then click the page. Notes last while this mockup is open.")
                    .foregroundStyle(GlassInk.secondary).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        ForEach(Array(pins.enumerated()), id: \.element.id) { i, pin in
                            CoreRow(
                                pin.text.isEmpty ? "Pin \(i + 1)" : pin.text,
                                symbol: pin.resolved ? "checkmark" : "mappin",
                                action: { viewer.selected = pin.id })
                            if pin.id == viewer.selected { editor(pin) }
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
    }

    private func editor(_ pin: MockupPin) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            CoreTextField(
                "Note", placeholder: "What should change here?",
                text: Binding(get: { pin.text }, set: { viewer.review.edit(pin.id, text: $0) }), autofocus: true)
            HStack(spacing: Space.s2) {
                Button(pin.resolved ? "Reopen" : "Resolve") { viewer.review.resolve(pin.id, !pin.resolved) }
                    .buttonStyle(.coreSecondary)
                Button("Delete") {
                    viewer.review.remove(pin.id)
                    viewer.selected = nil
                }
                .buttonStyle(.coreQuietDanger)
            }
            .disabled(readOnly)
        }
        .padding(Space.s2)
        .coreWell(radius: Radius.cardMac)
    }
}
