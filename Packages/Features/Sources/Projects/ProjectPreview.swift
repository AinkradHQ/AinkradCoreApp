import AppKit
import CoreUI
import Observation
import SwiftUI
import WebKit

/// The last picture of each project's live view, kept on disk (Application Support/Ainkrad/ProjectPreviews/<id>.png) so the
/// gallery's cards show the running app even after it stops. The live view of the space is where pictures are taken
/// (`WKWebView.takeSnapshot`); the gallery only reads them. Reading and writing happen off the main thread.
@MainActor @Observable
final class PreviewStore {
    static let shared = PreviewStore()
    private var images: [Int64: NSImage] = [:]
    private var asked: Set<Int64> = []
    /// The Core the pictures belong to (its host): a project id is only unique inside one Core, so a picture of one Core's
    /// project 3 is never shown for another Core's. Set with the connection.
    private(set) var core = "local"
    /// The widest a kept picture is: the cards and the stage show it small.
    static let maxWidth: CGFloat = 640
    @ObservationIgnored private let dir: URL? = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
    ).first?.appendingPathComponent("Ainkrad/ProjectPreviews", isDirectory: true)

    /// The file of a picture: `<core>-<id>.png`, the Core's host made safe for a file name.
    static func fileName(core: String, id: Int64) -> String {
        let safe = String(core.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? $0 : "_" })
        return "\(safe.isEmpty ? "local" : safe)-\(id).png"
    }

    /// Pictures of another Core are not this one's: the ones in memory go.
    func use(core: String?) {
        let next = core ?? "local"
        guard next != self.core else { return }
        self.core = next
        images = [:]
        asked = []
    }

    /// The picture, or nil while none is known (the view draws the illustration). Reading starts the disk load once.
    func image(_ id: Int64) -> NSImage? {
        if images[id] == nil, !asked.contains(id) { Task { await load(id) } }
        return images[id]
    }

    private func load(_ id: Int64) async {
        guard !asked.contains(id), let url = dir?.appendingPathComponent(Self.fileName(core: core, id: id)) else {
            return
        }
        asked.insert(id)
        let core = core
        let data = await Task.detached(priority: .utility) { try? Data(contentsOf: url) }.value
        if images[id] == nil, core == self.core, let data, let img = NSImage(data: data) { images[id] = img }
    }

    /// A new picture of the live view: shrunk, shown at once, written to disk in the background.
    func save(_ image: NSImage, for id: Int64) {
        let image = Self.scaled(image)
        asked.insert(id)
        images[id] = image
        guard let dir, let tiff = image.tiffRepresentation else { return }
        let file = dir.appendingPathComponent(Self.fileName(core: core, id: id))
        Task.detached(priority: .utility) {
            guard let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? png.write(to: file, options: .atomic)
        }
    }

    /// The picture of a project that is gone (deleted for good): its id may be given to a new one.
    func remove(_ id: Int64) {
        images[id] = nil
        asked.insert(id)
        guard let url = dir?.appendingPathComponent(Self.fileName(core: core, id: id)) else { return }
        Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: url) }
    }

    /// `image` at most `maxWidth` wide (the snapshot of a wide page is far bigger than any card).
    static func scaled(_ image: NSImage) -> NSImage {
        let w = image.size.width
        guard w > maxWidth else { return image }
        let size = NSSize(width: maxWidth, height: image.size.height * maxWidth / w)
        let out = NSImage(size: size)
        out.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        out.unlockFocus()
        return out
    }

    #if DEBUG
    /// Snapshots only: a picture that is never written to disk.
    func seed(_ image: NSImage, for id: Int64) {
        asked.insert(id)
        images[id] = image
    }
    func forget() {
        images = [:]
        asked = Set(1...1000)
    }
    #endif
}

/// What a project's picture shows when it was never opened: its colour and first letter, calm.
struct PreviewIllustration: View {
    let name: String
    let colour: ProjectColour
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [colour.fill.opacity(0.32), colour.fill.opacity(0.08)], startPoint: .topLeading,
                endPoint: .bottomTrailing)
            Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                .coreFont(size: Space.s8 * 2, weight: .semibold).foregroundStyle(.white.opacity(0.9))
                .frame(width: Space.s8 * 3, height: Space.s8 * 3)
                .background(colour.fill.opacity(0.85), in: coreShape(Radius.pane))
        }
        .accessibilityHidden(true)
    }
}

/// A project's picture: the last snapshot of its live view (kept in colour, a little quieter when it is not running), else a
/// picture of its kind. The picture never sets the size of what holds it: it is laid over a clear base and clipped.
struct ProjectPicture: View {
    let project: ProjectItem
    let colour: ProjectColour
    /// False on the space's stage, where the words sit over the picture: no snapshot means no illustration there.
    var illustrate = true
    var body: some View {
        let running = project.tag == .running
        let quiet = running || project.archived == false && project.tag == .starting
        if project.kind == .web, let img = PreviewStore.shared.image(project.id) {
            Color.clear
                .overlay(alignment: .top) { Image(nsImage: img).resizable().scaledToFill() }
                .grayscale(project.archived ? 1 : (running ? 0 : 0.6)).opacity(running ? 1 : 0.8)
                .clipped().accessibilityHidden(true)
        } else if illustrate {
            if project.kind == .web {
                PreviewIllustration(name: project.name, colour: colour).opacity(quiet ? 1 : 0.8)
            } else {
                KindPicture(kind: project.kind, hue: colour.fill, animated: false).scaleEffect(1.45)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .grayscale(project.archived ? 1 : 0).opacity(quiet ? 1 : 0.8)
            }
        }
    }
}

extension ProjectsModel {
    /// Where the running app can be seen from this Mac. On a Core with the preview route (API 110) that is the private preview,
    /// served through the signed API from the app's own URL scheme, so a running project shows live with the public link off.
    /// On an older Core it is the public link while it runs and the link is on, as before.
    func previewURL(for project: ProjectItem) -> URL? {
        guard project.tag == .running else { return nil }
        if core110, previewFetch != nil { return PreviewProxy.url() }
        guard project.expose else { return nil }
        return URL(string: "https://\(project.link)")
    }
}

/// The state of the live view in the space.
@MainActor @Observable
final class LiveWebModel {
    enum State: Equatable {
        case loading, live
        case failed(String)
    }
    var state = State.loading
    /// The one web view of the project, kept while its space is open: the Overview and the Live site page show this same view
    /// (one cookie jar, no reload on a switch of page).
    @ObservationIgnored var web: WKWebView?
    @ObservationIgnored var isPreview = false

    /// A picture of what the page shows now, once it has something to show.
    func snapshot(into id: Int64) {
        guard state == .live, let web else { return }
        web.takeSnapshot(with: WKSnapshotConfiguration()) { image, _ in
            guard let image else { return }
            Task { @MainActor in PreviewStore.shared.save(image, for: id) }
        }
    }
}

/// The running app in a web view. Links to other sites open in the browser; the page itself stays here.
struct LiveWebView: NSViewRepresentable {
    let url: URL
    let model: LiveWebModel
    /// The project's preview (the private one, when `url` is of the app's own scheme): its id, how to send a signed request and
    /// the Core's host, for redirects.
    var preview: (project: Int64, coreHost: String?, fetch: PreviewFetch)?
    /// The page zoom: the stage lays the site out at a device width and shrinks it to fit the frame.
    var zoom: CGFloat = 1

    func makeCoordinator() -> Coordinator { Coordinator(model: model, url: url) }

    func makeNSView(context: Context) -> WKWebView {
        let wantsPreview = url.scheme == PreviewProxy.scheme
        if let kept = model.web, model.isPreview == wantsPreview {
            kept.navigationDelegate = context.coordinator
            if kept.url == nil || model.state != .live { load(kept) }
            return kept
        }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        if url.scheme == PreviewProxy.scheme, let p = preview {
            let handler = PreviewSchemeHandler(project: p.project, coreHost: p.coreHost, fetch: p.fetch)
            let model = model
            handler.onProblem = { words in model.state = .failed(words) }
            config.setURLSchemeHandler(handler, forURLScheme: PreviewProxy.scheme)
        }
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.setValue(false, forKey: "drawsBackground")
        model.web = web
        model.isPreview = wantsPreview
        load(web)
        return web
    }

    private func load(_ web: WKWebView) {
        web.load(URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 20))
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        if abs(web.pageZoom - zoom) > 0.001 { web.pageZoom = zoom }
        if web.url?.host != url.host, web.url != url, !web.isLoading {
            model.state = .loading
            web.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let model: LiveWebModel
        let origin: URL
        init(model: LiveWebModel, url: URL) {
            self.model = model
            origin = url
        }
        func webView(_ w: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                // A page the Core could not show already said why; the words stay until Try Again.
                if case .failed = model.state { return }
                model.state = .live
            }
        }
        func webView(_ w: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
        func webView(_ w: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            fail(error)
        }
        private func fail(_ error: Error) {
            let code = (error as NSError).code
            if code == NSURLErrorCancelled { return }
            let why = (error as NSError).localizedDescription
            Task { @MainActor in model.state = .failed(why) }
        }
        func webView(
            _ w: WKWebView, decidePolicyFor action: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            switch Self.decide(action.request.url, from: origin, mainFrame: action.targetFrame?.isMainFrame ?? true) {
            case .allow: decisionHandler(.allow)
            case .browser(let url):
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            case .block: decisionHandler(.cancel)
            }
        }

        enum Navigation: Equatable {
            case allow, block
            case browser(URL)
        }

        /// What a navigation of the page may do: stay on the page's own origin (the preview scheme, or the project's host), a
        /// web link elsewhere goes to the browser, and anything else (a script moving the stage to a file, another scheme)
        /// is refused. A frame inside the page is its own business; only the page itself is held to this.
        static func decide(_ url: URL?, from origin: URL, mainFrame: Bool) -> Navigation {
            guard mainFrame else { return .allow }
            guard let url, let scheme = url.scheme?.lowercased() else { return .block }
            if scheme == "about" { return .allow }
            let web = ["http", "https"]
            let same = scheme == origin.scheme?.lowercased() || (web.contains(scheme) && web.contains(origin.scheme ?? ""))
            if same, url.host?.lowercased() == origin.host?.lowercased() { return .allow }
            return web.contains(scheme) ? .browser(url) : .block
        }
    }
}
