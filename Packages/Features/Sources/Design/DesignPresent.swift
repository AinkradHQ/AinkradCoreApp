import AppKit
import CoreUI
import SwiftUI
import UniformTypeIdentifiers

/// Present (the Mockup): one screen of a design inside a device, on a background, clickable as a prototype. A click on a
/// layer that has a prototype link (Inspector, Prototype) moves to that screen; ← → step through the screens; Esc goes
/// back to editing. Export PNG saves the device shot. The screen is drawn by a second canvas (its own viewer editor) that
/// never edits: presenting turns the engine's pointer into taps.
enum PresentDevice: String, CaseIterable, Identifiable {
    case phone, tablet, laptop, browser, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .phone: "iPhone"
        case .tablet: "iPad"
        case .laptop: "MacBook"
        case .browser: "Browser"
        case .none: "No device"
        }
    }
    var symbol: String {
        switch self {
        case .phone: "iphone"
        case .tablet: "ipad"
        case .laptop: "laptopcomputer"
        case .browser: "macwindow"
        case .none: "rectangle"
        }
    }
    /// The device a screen of this width reads as.
    static func fitting(_ w: CGFloat) -> PresentDevice { w < 600 ? .phone : w < 1100 ? .tablet : .browser }
}

enum PresentBackground: String, CaseIterable, Identifiable {
    case night, day, accent, paper
    var id: String { rawValue }
    var title: String {
        switch self {
        case .night: "Night"
        case .day: "Day"
        case .accent: "Accent"
        case .paper: "Paper"
        }
    }
}

@MainActor @Observable
final class DesignPresenter {
    let doc: DesignDoc
    let viewer: DesignEditor
    private(set) var frame: String?
    var device: PresentDevice
    var background = PresentBackground.night
    /// A short fade while moving between screens.
    private(set) var switching = false
    /// What the stage can show: the design is still opening, it has screens, it has none, or it never opened.
    enum Phase: Equatable { case opening, ready, empty, failed }
    private(set) var phase = Phase.opening
    #if DEBUG
    /// Snapshots only.
    func debugPhase(_ p: Phase) { phase = p }
    #endif
    /// The export size (1× to 3×).
    var exportScale = 2
    @ObservationIgnored private weak var model: DesignModel?

    init(model: DesignModel, doc: DesignDoc, frame: String?, size: CGSize?) {
        self.model = model
        self.doc = doc
        self.frame = frame
        viewer = DesignEditor(doc: doc.id, service: nil)
        device = PresentDevice.fitting(size?.width ?? 390)
    }

    /// The screens to step through: the page's top-level frames, in order.
    var frames: [DesignLayer] { Self.screens(in: viewer) }

    /// The screens of a design: the first page's top-level frames, in order.
    static func screens(in editor: DesignEditor) -> [DesignLayer] {
        guard let page = editor.layers.children(of: nil).first else { return [] }
        return editor.layers.children(of: page.id).filter { $0.type == "frame" || $0.type == "component" }
    }

    /// The screen a layer is on (itself when it is one), or nil when it is on none of them.
    func screen(containing id: String) -> String? {
        let tops = Set(frames.map(\.id))
        var at: String? = id
        while let i = at {
            if tops.contains(i) { return i }
            at = viewer.layers[i]?.parent
        }
        return nil
    }

    func canStep(_ by: Int) -> Bool {
        let all = frames
        guard let i = all.firstIndex(where: { $0.id == current?.id }) else { return false }
        return all.indices.contains(i + by)
    }
    var current: DesignLayer? { frame.flatMap { viewer.layers[$0] } ?? frames.first }
    var size: CGSize? { current.flatMap { DesignComposer.rect(of: $0.id, in: viewer) }?.size }

    /// Once the viewer's canvas is up and has the document: presenting on, the screen fitted.
    func ready() async {
        for _ in 0..<100 {
            viewer.reload()
            if viewer.attached && viewer.loaded { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard viewer.attached, viewer.loaded else {
            phase = .failed
            return
        }
        guard current != nil else {
            phase = .empty
            return
        }
        phase = .ready
        viewer.present { [weak self] id in self?.tap(id) }
        show()
        // The canvas fits the whole page when its first content lands; fit the screen again after that.
        try? await Task.sleep(for: .milliseconds(400))
        show()
    }

    /// The screen's view changed size (device, window): fit again once the canvas has its new size.
    func refit() {
        Task {
            try? await Task.sleep(for: .milliseconds(60))
            show()
        }
    }

    private func show() {
        guard let c = current, let r = DesignComposer.rect(of: c.id, in: viewer) else { return }
        frame = c.id
        viewer.fit(r)
    }

    /// A tap: the link on the tapped layer, or on the nearest layer above it that has one.
    func tap(_ id: String?) {
        var at = id
        while let i = at {
            if let to = viewer.node(of: i)?.props["link"]?["to"]?.string {
                guard viewer.layers[to] != nil else { return tell("That screen was removed.") }
                // A link to a layer inside a screen goes to that screen.
                guard let top = screen(containing: to) else {
                    return tell("That link goes to a screen on another page.")
                }
                return go(top)
            }
            at = viewer.layers[i]?.parent
        }
    }

    private func tell(_ words: String) { model?.host.shell.showToast(words, kind: .warn) }

    func step(_ by: Int) {
        let all = frames
        guard canStep(by), let i = all.firstIndex(where: { $0.id == current?.id }) else { return }
        go(all[i + by].id)
    }

    /// Saves the current screen alone as a PNG, drawn by the engine (`de_export_png`), at `exportScale`×. The backdrop's
    /// theme picks the day or night tokens.
    func exportPNG() {
        guard let node = current?.id else { return }
        switch viewer.exportPNG(node: node, scale: exportScale, night: background == .night) {
        case .png(let png):
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.png]
            panel.nameFieldStringValue = "\(doc.name) – \(current?.title ?? "screen")@\(exportScale)x.png"
            panel.begin { [weak self] r in
                guard r == .OK, let url = panel.url else { return }
                do {
                    try png.write(to: url)
                    self?.model?.host.shell.showToast("Saved \(url.lastPathComponent)")
                } catch {
                    self?.tell("The PNG could not be saved: \(error.localizedDescription)")
                }
            }
        case .tooLarge: tell("That screen is too large to export at \(exportScale)×. Try a smaller size.")
        case .failed: tell("The screen could not be exported.")
        }
    }

    func go(_ id: String) {
        guard id != frame else { return }
        Task {
            withAnimation(Motion.out(Motion.hover)) { switching = true }
            try? await Task.sleep(for: .milliseconds(140))
            // A screen of another kind (a phone after a desktop) takes its own device.
            if let w = DesignComposer.rect(of: id, in: viewer)?.width, let old = size?.width,
                PresentDevice.fitting(w) != PresentDevice.fitting(old)
            {
                device = .fitting(w)
            }
            frame = id
            show()
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation(Motion.out(Motion.ui)) { switching = false }
        }
    }

    func close() {
        viewer.present(nil)
        withAnimation(Motion.out(Motion.ui)) { model?.presenter = nil }
    }
}

extension DesignModel {
    /// Presents a design: the selected (or first) screen in a device.
    func present(_ d: DesignDoc) {
        let editor = editors[d.id]
        let frame = editor?.targetFrame()?.id ?? editor.flatMap { DesignPresenter.screens(in: $0).first?.id }
        let size = frame.flatMap { f in editor.flatMap { DesignComposer.rect(of: f, in: $0) } }?.size
        withAnimation(Motion.out(Motion.ui)) {
            presenter = DesignPresenter(model: self, doc: d, frame: frame, size: size)
        }
    }
}

/// The present screen over the whole open item.
struct DesignPresentView: View {
    let model: DesignModel
    @Bindable var presenter: DesignPresenter
    @Environment(\.coreAccent) private var paneAccent

    var body: some View {
        VStack(spacing: 0) {
            bar
            GeometryReader { g in
                ZStack {
                    PresentBackdrop(kind: presenter.background, ink: GlassInk.accent(paneAccent))
                    if presenter.phase == .empty || presenter.phase == .failed {
                        CoreStateCard(
                            symbol: presenter.phase == .empty ? "rectangle.dashed" : "exclamationmark.triangle",
                            title: presenter.phase == .empty ? "Nothing to present" : "The design did not open",
                            line: presenter.phase == .empty
                                ? "This design has no screens yet. Draw a frame or ask AI, then present again."
                                : "Go back and open it again.",
                            primary: CoreAction("Back to editing") { presenter.close() })
                    } else if let canvas = model.canvasView(presenter.doc, editor: presenter.viewer) {
                        DeviceFrame(
                            device: presenter.device, screen: presenter.size ?? CGSize(width: 390, height: 844),
                            room: g.size, title: presenter.current?.title ?? ""
                        ) {
                            canvas.opacity(presenter.switching ? 0.0 : 1)
                                .onGeometryChange(for: CGSize.self) {
                                    $0.size
                                } action: { _ in
                                    presenter.refit()
                                }
                        }
                        .animation(Motion.out(Motion.ui), value: presenter.device)
                    }
                }
            }
            .clipShape(coreShape(Radius.pane))
            .padding(.horizontal, Space.s4).padding(.bottom, Space.s4)
        }
        .task { await presenter.ready() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("design-present")
    }

    private var bar: some View {
        AppHeader {
            Button {
                presenter.close()
            } label: {
                Label("Edit", systemImage: "chevron.left")
            }
            .buttonStyle(CoreButtonStyle(.plain, size: .small))
            .environment(\.coreKeycap, "esc")
            .help("Back to editing  Esc")
            Text(presenter.current?.title ?? presenter.doc.name).coreFont(size: MacTextSize.title, weight: .semibold)
                .lineLimit(1)
            if presenter.phase == .ready,
                let i = presenter.frames.firstIndex(where: { $0.id == presenter.current?.id })
            {
                Text("\(i + 1) of \(presenter.frames.count)").foregroundStyle(GlassInk.secondary).monospacedDigit()
            }
        } actions: {
            CoreIconButton(symbol: "chevron.left", label: "Previous screen  ←") { presenter.step(-1) }
                .disabled(presenter.phase != .ready || !presenter.canStep(-1))
                .help(presenter.canStep(-1) ? "Previous screen  ←" : "This is the first screen")
            CoreIconButton(symbol: "chevron.right", label: "Next screen  →") { presenter.step(1) }
                .disabled(presenter.phase != .ready || !presenter.canStep(1))
                .help(presenter.canStep(1) ? "Next screen  →" : "This is the last screen")
            CoreSegmented(
                "Device",
                segments: PresentDevice.allCases.map { CoreSegment($0, "", symbol: $0.symbol) },
                selection: $presenter.device
            )
            .help("The device the screen is shown in")
            InlineMenu(
                label: "Backdrop", value: presenter.background.title,
                choices: PresentBackground.allCases.map(\.title)
            ) { t in presenter.background = PresentBackground.allCases.first { $0.title == t } ?? .night }
            .frame(width: Space.s8 * 5)
            InlineMenu(
                label: "Size", value: "\(presenter.exportScale)×", choices: ["1×", "2×", "3×"]
            ) { t in presenter.exportScale = Int(t.dropLast()) ?? 2 }
            .frame(width: Space.s8 * 3)
            .help("The PNG's size: 1×, 2× or 3× the screen")
            AppActionTile(
                title: "Export PNG", symbol: "square.and.arrow.up", key: "", hue: GlassInk.accent(paneAccent),
                prominent: true
            ) {
                presenter.exportPNG()
            }
            .disabled(presenter.phase != .ready)
            .help(presenter.phase == .ready ? "Save this screen as a PNG" : "There is no screen to export")
        }
    }
}

/// The room behind the device.
struct PresentBackdrop: View {
    let kind: PresentBackground
    let ink: Color
    var body: some View {
        switch kind {
        case .night:
            LinearGradient(colors: [Color(white: 0.09), Color(white: 0.16)], startPoint: .top, endPoint: .bottom)
        case .day:
            LinearGradient(colors: [Color(white: 0.95), Color(white: 0.86)], startPoint: .top, endPoint: .bottom)
        case .accent:
            LinearGradient(
                colors: [ink.opacity(0.9), ink.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .paper:
            Color(red: 0.96, green: 0.94, blue: 0.9)
        }
    }
}

/// A device drawn around the screen, sized to the room with the screen's own aspect.
struct DeviceFrame<Screen: View>: View {
    let device: PresentDevice
    let screen: CGSize
    let room: CGSize
    let title: String
    @ViewBuilder let content: Screen

    /// The screen size on the stage: the frame's aspect, as large as fits with room for the device around it.
    private var shown: CGSize {
        let pad: CGFloat = device == .laptop ? 0.22 : device == .none ? 0.08 : 0.14
        let maxW = room.width * (1 - pad)
        let maxH = room.height * (1 - pad) - (device == .browser ? 36 : 0)
        let k = min(maxW / max(screen.width, 1), maxH / max(screen.height, 1))
        return CGSize(width: screen.width * k, height: screen.height * k)
    }

    var body: some View {
        let s = shown
        Group {
            switch device {
            case .phone: phone(s)
            case .tablet: tablet(s)
            case .laptop: laptop(s)
            case .browser: browser(s)
            case .none: glass(s, radius: 6)
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 30, y: 16)
    }

    /// The canvas fills the screen edge to edge: the engine fits a rect with a 5 % margin, so the view is 1/0.9 larger
    /// than the screen and clipped to it.
    private func glass(_ s: CGSize, radius: CGFloat) -> some View {
        content
            .frame(width: s.width / 0.9, height: s.height / 0.9)
            .frame(width: s.width, height: s.height)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    private func phone(_ s: CGSize) -> some View {
        let m = min(s.width, s.height)
        let b = m * 0.045
        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: m * 0.16, style: .continuous).fill(Color(white: 0.07))
                .frame(width: s.width + b * 2, height: s.height + b * 2)
            glass(s, radius: m * 0.13).padding(b)
            RoundedRectangle(cornerRadius: m * 0.04, style: .continuous).fill(.black)
                .frame(width: m * 0.3, height: m * 0.085).padding(.top, b + m * 0.03)
        }
    }

    private func tablet(_ s: CGSize) -> some View {
        let b = max(s.width, s.height) * 0.03
        return ZStack {
            RoundedRectangle(cornerRadius: b * 2.2, style: .continuous).fill(Color(white: 0.08))
                .frame(width: s.width + b * 2, height: s.height + b * 2)
            glass(s, radius: b * 1.1)
        }
    }

    private func laptop(_ s: CGSize) -> some View {
        let b = s.width * 0.02
        return VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: b * 1.5, style: .continuous).fill(Color(white: 0.06))
                    .frame(width: s.width + b * 2, height: s.height + b * 3)
                glass(s, radius: 2).offset(y: b * 0.4)
            }
            // The base: a thin slab, wider than the lid, with the notch for the opening.
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: b, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.78), Color(white: 0.55)], startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: s.width * 1.16, height: b * 1.6)
                RoundedRectangle(cornerRadius: b * 0.5, style: .continuous).fill(Color(white: 0.45))
                    .frame(width: s.width * 0.16, height: b * 0.5)
            }
        }
    }

    private func browser(_ s: CGSize) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach([Color.red, .yellow, .green], id: \.self) { c in
                    Circle().fill(c.opacity(0.85)).frame(width: 11, height: 11)
                }
                Text(title).coreFont(size: MacTextSize.meta).foregroundStyle(Color(white: 0.4)).lineLimit(1)
                    .frame(maxWidth: s.width * 0.5).frame(height: 22)
                    .background(Color(white: 0.92), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .frame(maxWidth: .infinity)
                Color.clear.frame(width: 45, height: 1)
            }
            .padding(.horizontal, 12).frame(width: s.width, height: 36)
            .background(Color(white: 0.97))
            glass(s, radius: 0)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
