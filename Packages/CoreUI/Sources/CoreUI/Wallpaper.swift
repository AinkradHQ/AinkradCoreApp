import AppKit
import Observation
import SwiftUI

/// The desktop background (Ahmed, 2026-11-15): Settings, Appearance. Plain by default, calm for long days.
public enum CoreWallpaper: String, CaseIterable, Sendable {
    case plain, soft, sky, picture

    public var title: String {
        switch self {
        case .plain: "Plain"
        case .soft: "Soft"
        case .sky: "Sky"
        case .picture: "Your picture"
        }
    }
}

@MainActor @Observable
public final class WallpaperPrefs {
    public static let shared = WallpaperPrefs()
    public var choice: CoreWallpaper { didSet { d.set(choice.rawValue, forKey: "look.wallpaper") } }
    /// The copy of the chosen picture, kept in Application Support so moving the original does not lose it.
    public private(set) var picture: NSImage?
    private let d = UserDefaults.standard

    private init() {
        choice = CoreWallpaper(rawValue: d.string(forKey: "look.wallpaper") ?? "") ?? .plain
        picture = Self.file.flatMap { NSImage(contentsOf: $0) }
        if choice == .picture, picture == nil { choice = .plain }
    }

    /// Asks for an image, keeps a copy and shows it. Cancel leaves everything as it was.
    public func choosePicture() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url), let dest = Self.target
        else { return }
        try? FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: dest)
        guard (try? FileManager.default.copyItem(at: url, to: dest)) != nil else { return }
        picture = image
        choice = .picture
    }

    private static var target: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: Bundle.main.bundleIdentifier ?? "com.ainkrad.core").appending(path: "wallpaper")
    }
    private static var file: URL? { target.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil } }
}

/// The wallpaper in force, filling its space. `choice` and `day` are for thumbnails; nil follows the setting and the
/// appearance it is drawn in.
public struct WallpaperView: View {
    let choice: CoreWallpaper?
    let day: Bool?
    @Environment(\.colorScheme) private var scheme
    public init(_ choice: CoreWallpaper? = nil, day: Bool? = nil) {
        self.choice = choice
        self.day = day
    }

    public var body: some View {
        let prefs = WallpaperPrefs.shared
        let isDay = day ?? (scheme == .light)
        Color.clear.overlay {
            switch choice ?? prefs.choice {
            // Neutral graphite and paper, as on ainkrad.io: no tint, no stars.
            case .plain:
                isDay ? Color(red: 0.949, green: 0.953, blue: 0.961) : Color(red: 0.055, green: 0.059, blue: 0.067)
            case .soft:
                LinearGradient(
                    colors: isDay
                        ? [Color(red: 0.973, green: 0.976, blue: 0.98), Color(red: 0.902, green: 0.91, blue: 0.925)]
                        : [Color(red: 0.094, green: 0.102, blue: 0.118), Color(red: 0.039, green: 0.043, blue: 0.051)],
                    startPoint: .top, endPoint: .bottom)
            case .sky:
                Image(isDay ? "HomeSkyDay" : "HomeSky", bundle: .main).resizable().scaledToFill()
                    .overlay(isDay ? GlassInk.daySkyVeil : .clear)
            case .picture:
                if let p = prefs.picture {
                    Image(nsImage: p).resizable().scaledToFill()
                } else {
                    isDay ? Color(red: 0.949, green: 0.953, blue: 0.961) : Color(red: 0.055, green: 0.059, blue: 0.067)
                }
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}
