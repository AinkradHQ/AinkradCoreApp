import AppKit
import Observation
import SwiftUI

/// The desktop background (Ahmed, 2026-11-15): Settings, Appearance. Twelve wallpapers, six photos and six rendered
/// landscapes, each with a night and a day version; Sky, Plain and the person's own picture after them.
/// Images live in the app's `Wallpapers/` folder as `wall-<name>-<day|night>.heic` (5K) and `-thumb.jpg`.
public enum CoreWallpaper: String, CaseIterable, Sendable {
    case ridge, lake, mirage, forest, tide, coast, meadow, peaks, mirror, dunes, mesa, hills, sky, plain, picture

    public static let standard = CoreWallpaper.ridge
    /// Everything but the custom picture, in the order Settings shows them.
    public static let presets = allCases.filter { $0 != .picture }

    public var title: String { self == .picture ? "Your picture" : rawValue.capitalized }
    /// The two wallpapers drawn from files: every case but Sky, Plain and the picture.
    var isFile: Bool { ![.sky, .plain, .picture].contains(self) }
}

/// Decoded wallpapers, kept so a redraw never decodes again. Thumbnails are small; a full image is ~37 MB decoded, and
/// only the ones actually shown are loaded.
@MainActor
enum WallpaperCache {
    private static var images: [String: NSImage] = [:]
    static func image(_ wall: CoreWallpaper, day: Bool, thumb: Bool) -> NSImage? {
        let name = "wall-\(wall.rawValue)-\(day ? "day" : "night")\(thumb ? "-thumb" : "")"
        if let hit = images[name] { return hit }
        guard let url = Bundle.main.url(forResource: name, withExtension: thumb ? "jpg" : "heic"),
            let img = NSImage(contentsOf: url)
        else { return nil }
        images[name] = img
        return img
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
        choice = CoreWallpaper(rawValue: d.string(forKey: "look.wallpaper") ?? "") ?? .standard
        picture = Self.file.flatMap { NSImage(contentsOf: $0) }
        if choice == .picture, picture == nil { choice = .standard }
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

/// The wallpaper in force, filling its space. `choice` and `day` are for thumbnails (`thumb` loads the small file); nil
/// follows the setting and the appearance it is drawn in.
public struct WallpaperView: View {
    let choice: CoreWallpaper?
    let day: Bool?
    let thumb: Bool
    @Environment(\.colorScheme) private var scheme
    public init(_ choice: CoreWallpaper? = nil, day: Bool? = nil, thumb: Bool = false) {
        self.choice = choice
        self.day = day
        self.thumb = thumb
    }

    public var body: some View {
        let prefs = WallpaperPrefs.shared
        let isDay = day ?? (scheme == .light)
        let wall = choice ?? prefs.choice
        Color.clear.overlay {
            if wall.isFile, let img = WallpaperCache.image(wall, day: isDay, thumb: thumb) {
                Image(nsImage: img).resizable().scaledToFill()
            } else if wall == .sky {
                Image(isDay ? "HomeSkyDay" : "HomeSky", bundle: .main).resizable().scaledToFill()
                    .overlay(isDay ? GlassInk.daySkyVeil : .clear)
            } else if wall == .picture, let p = prefs.picture {
                Image(nsImage: p).resizable().scaledToFill()
            } else {
                // Plain: neutral graphite and paper, as on ainkrad.io.
                isDay ? Color(red: 0.949, green: 0.953, blue: 0.961) : Color(red: 0.055, green: 0.059, blue: 0.067)
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}
