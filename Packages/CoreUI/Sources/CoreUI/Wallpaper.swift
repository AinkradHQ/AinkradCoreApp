import AppKit
import Observation
import SwiftUI

/// The desktop background (Ahmed, 2026-11-15): Settings, Appearance. Twenty-four wallpapers, twelve photos and twelve
/// rendered landscapes, each with a night and a day version; Sky, Plain and the person's own picture after them.
/// Images live in the app's `Wallpapers/` folder as `wall-<name>-<day|night>.heic` (5K) and `-thumb.jpg`.
///
/// Added in 0.10 (E2-7, D-12). Photos: free to use under the Unsplash License (unsplash.com/license), no people, graded
/// to a night and a day version and cropped to 16:10. Source page, photographer:
/// - reef: unsplash.com/photos/HYHYGLs-Rp8, NEOM (images.unsplash.com/photo-1708649290066-5f617003b93f)
/// - lavender: unsplash.com/photos/nD9tEn63suc, Antony BEC (photo-1600759487717-62bbb608106e)
/// - glacier: unsplash.com/photos/9K7780JqW5Q, Pavol Svantner (photo-1619165822011-f5f9e5f7bd97)
/// - bloom: unsplash.com/photos/TzoWpI57mGw, Fred Amini (photo-1774479341808-def72e8236ac)
/// - aurora: unsplash.com/photos/LtnPejWDSAY, Lightscape (photo-1531366936337-7c912a4589a7)
/// - canyon: unsplash.com/photos/RYtiT3b7XW4, Peter Olexa (photo-1599496507927-9056debd0f0a)
/// Rendered (dusk, lagoon, ember, zenith, orchid, crimson) are procedural, made by `scripts/gen-wallpapers.py`.
public enum CoreWallpaper: String, CaseIterable, Sendable {
    case ridge, lake, mirage, forest, tide, coast, meadow, peaks, mirror, dunes, mesa, hills
    case reef, lavender, glacier, bloom, aurora, canyon, dusk, lagoon, ember, zenith, orchid, crimson
    case sky, plain, picture

    public static let standard = CoreWallpaper.ridge
    /// Everything but the custom picture, in the order Settings shows them.
    public static let presets = allCases.filter { $0 != .picture }

    public var title: String { self == .picture ? "Your picture" : rawValue.capitalized }
    /// Which tab of Settings, Appearance, Wallpaper lists it (E2-4).
    public var group: WallpaperGroup {
        switch self {
        case .picture: .picture
        case .lake, .forest, .coast, .peaks, .dunes, .hills, .reef, .lavender, .glacier, .bloom, .aurora, .canyon: .photos
        default: .generated
        }
    }
    /// The wallpapers of one tab, in the order Settings shows them.
    public static func presets(in group: WallpaperGroup) -> [CoreWallpaper] { allCases.filter { $0.group == group } }

    /// The two wallpapers drawn from files: every case but Sky, Plain and the picture.
    var isFile: Bool { ![.sky, .plain, .picture].contains(self) }
}

/// The tabs of the wallpaper page: photos, the ones drawn for Ainkrad (and Sky and Plain), and the person's own picture.
public enum WallpaperGroup: String, CaseIterable, Sendable {
    case photos, generated, picture
    public var title: String {
        switch self {
        case .photos: "Photos"
        case .generated: "Generated"
        case .picture: "Your picture"
        }
    }
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
        guard panel.runModal() == .OK, let url = panel.url else { return }
        adoptPicture(at: url)
    }

    /// Keeps a copy of an image file and shows it (a chosen file, or one dropped on the page).
    public func adoptPicture(at url: URL) {
        guard let image = NSImage(contentsOf: url), let dest = Self.target else { return }
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
