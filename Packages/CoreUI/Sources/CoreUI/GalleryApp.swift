#if DEBUG
import SwiftUI

/// The gallery's sections, in the sidebar's order.
public enum GallerySection: String, CaseIterable, Identifiable, Sendable {
    case foundations, styles, buttons, inputs, selection, status, feedback, data, surfaces, navigation
    public var id: String { rawValue }
    var title: String {
        switch self {
        case .foundations: "Foundations"
        case .styles: "Every style"
        case .buttons: "Buttons"
        case .inputs: "Inputs"
        case .selection: "Selection"
        case .status: "Status"
        case .feedback: "Feedback"
        case .data: "Data"
        case .surfaces: "Surfaces"
        case .navigation: "Navigation"
        }
    }
    var symbol: String {
        switch self {
        case .foundations: "paintpalette"
        case .styles: "square.grid.3x3"
        case .buttons: "button.horizontal"
        case .inputs: "character.cursor.ibeam"
        case .selection: "checklist"
        case .status: "tag"
        case .feedback: "bell"
        case .data: "chart.bar"
        case .surfaces: "square.on.square"
        case .navigation: "sidebar.left"
        }
    }
    var sub: String {
        switch self {
        case .foundations: "Colours, type, spacing, corners, motion and wallpapers"
        case .styles: "Every core control on one screen, plus the worst case"
        case .buttons: "Every kind, size and state"
        case .inputs: "Fields, steppers, sliders, selects and menus"
        case .selection: "Switches, checkboxes, radios, segments and tiles"
        case .status: "Badges, counts, chips and icon tiles"
        case .feedback: "Notices, banners, toasts, progress and empty states"
        case .data: "Meters, sparks, heat and slots"
        case .surfaces: "Wells, frames, sheets, dialogs and panes"
        case .navigation: "Headers, steps, sections and rows"
        }
    }
}

/// The component gallery (Ahmed, 2026-11-15): every element in every style and state, drawn over the real wallpaper
/// inside a real pane. The bar at the top sets the app's own Theme, Accent, Wallpaper and Content background, so each
/// element can be checked under every style. Debug only: Debug, CoreUI Gallery (⌥⌘G).
public struct CoreUIGallery: View {
    @State var section: GallerySection
    @State var theme: String
    @Bindable var accent = AccentPrefs.shared
    @Bindable var wallpaper = WallpaperPrefs.shared
    @Bindable var look = LookPrefs.shared
    let sidebar: Bool

    // State the examples share.
    @State var toast: ToastItem?
    @State var confirm = false
    @State var destructive = false
    @State var fieldText = "linux-01"
    @State var emptyText = ""
    @State var secret = "sk-ant-0000"
    @State var selectPick = "claude"
    @State var choice = "b"
    @State var checks: Set<String> = ["read", "terminal"]
    @State var segment = "all"
    @State var count = 3
    @State var switchOn = true
    @State var switchOff = false
    @State var slider = 0.6
    @State var mode = SurfaceMode.blurred
    @State var menuOpen = true
    // Scenarios the Mac can ask for, forced here so they can be checked without System Settings.
    @State var contrast: Bool
    @State var solid: Bool
    @State var rtl: Bool
    static let selectOptions = [
        CoreSelectOption("claude", "Claude Code", symbol: "sparkle", note: "default"),
        CoreSelectOption("codex", "Codex", symbol: "chevron.left.forwardslash.chevron.right"),
        CoreSelectOption("opencode", "OpenCode", symbol: "terminal"),
    ]

    /// `theme`: "night", "day", or "app" to follow the app.
    public init(
        section: GallerySection = .foundations, theme: String = "app", sidebar: Bool = true, contrast: Bool = false,
        solid: Bool = false, rtl: Bool = false
    ) {
        _section = State(initialValue: section)
        _theme = State(initialValue: theme)
        _contrast = State(initialValue: contrast)
        _solid = State(initialValue: solid)
        _rtl = State(initialValue: rtl)
        self.sidebar = sidebar
    }

    public var body: some View {
        HStack(alignment: .top, spacing: Space.s4) {
            if sidebar { sideList.frame(width: Space.s8 * 7) }
            VStack(alignment: .leading, spacing: 0) {
                styleBar.padding(Space.s5)
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s4) { content }
                        .padding([.horizontal, .bottom], Space.s5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .modifier(GalleryScenario(contrast: contrast, solid: solid, rtl: rtl))
                }
            }
            .coreFrame(part: .panes)
        }
        .padding(Space.s4)
        .background { WallpaperView().ignoresSafeArea() }
        #if os(macOS)
        .background(UnifiedTitleBar())
        #endif
        .coreTheme()
        .preferredColorScheme(theme == "night" ? .dark : theme == "day" ? .light : nil)
        .coreToast($toast)
        .coreConfirm(
            "Close this session?", isPresented: $confirm, message: "The AI session stops and its work is kept.",
            confirmTitle: "Close"
        ) { toast = ToastItem("Session closed", undo: {}) }
        .coreConfirm(
            "Delete this terminal?", isPresented: $destructive, message: "This cannot be undone from here.",
            confirmTitle: "Delete", destructive: true
        ) { toast = ToastItem("Terminal deleted", undo: {}) }
    }

    private var sideList: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text("Components").coreFont(size: MacTextSize.title, weight: .semibold).padding(Space.s3)
            ForEach(GallerySection.allCases) { s in
                CoreRow(s.title, symbol: s.symbol, selected: section == s) { section = s }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s2)
        .coreFrame(part: .panes)
    }

    /// The app's own style settings, so every element can be seen under each of them.
    private var styleBar: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Text(section.title).coreFont(size: MacTextSize.large, weight: .semibold)
                Text(section.sub).coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
            }
            HStack(alignment: .bottom, spacing: Space.s4) {
                CoreSegmented(
                    "Theme",
                    segments: [CoreSegment("night", "Night"), CoreSegment("day", "Day"), CoreSegment("app", "App")],
                    selection: $theme
                )
                .frame(width: Space.s8 * 7)
                CoreSelect(
                    "Accent", selection: $accent.accent,
                    options: CoreAccent.allCases.map { CoreSelectOption($0, $0.title) }
                )
                .frame(width: Space.s8 * 5)
                CoreSelect(
                    "Wallpaper", selection: $wallpaper.choice,
                    options: CoreWallpaper.presets.map { CoreSelectOption($0, $0.title) }
                )
                .frame(width: Space.s8 * 5)
                SurfaceModeTabs(mode: $look.mode)
                CoreSwitch("Glass", isOn: $look.glass)
                Spacer(minLength: 0)
            }
            HStack(spacing: Space.s5) {
                CoreSwitch("Increase contrast", isOn: $contrast)
                CoreSwitch("Reduce transparency", isOn: $solid)
                CoreSwitch("Right to left", isOn: $rtl)
            }
            Text(
                "Theme, Accent, Wallpaper and the background are the app's own settings: changing them here changes them "
                    + "everywhere. The three switches apply only inside this gallery."
            )
            .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
        }
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .foundations: foundations
        case .styles: styles
        case .buttons: buttons
        case .inputs: inputs
        case .selection: selection
        case .status: status
        case .feedback: feedback
        case .data: data
        case .surfaces: surfaces
        case .navigation: navigation
        }
    }
}

/// The Mac's accessibility asks, forced on the gallery's content only.
struct GalleryScenario: ViewModifier {
    let contrast: Bool
    let solid: Bool
    let rtl: Bool
    @Environment(\.corePalette) private var palette
    @Environment(\.coreSolidOnly) private var inheritedSolid
    @Environment(\.layoutDirection) private var direction
    func body(content: Content) -> some View {
        content
            .environment(\.corePalette, contrast ? palette.contrast(.increased) : palette)
            .environment(\.coreSolidOnly, solid || inheritedSolid)
            .environment(\.layoutDirection, rtl ? .rightToLeft : direction)
    }
}

/// One component: its type name, what it is for, then its variants.
struct GSpec<Content: View>: View {
    let name: String
    let note: String
    let content: Content
    init(_ name: String, _ note: String, @ViewBuilder content: () -> Content) {
        self.name = name
        self.note = note
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).coreFont(size: MacTextSize.title, weight: .semibold, design: .monospaced)
                Text(note).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            }
            content
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .coreWell()
    }
}

/// One variant with its caption under it.
struct GVariant<Content: View>: View {
    let label: String
    let content: Content
    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            content
            Text(label).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
        }
    }
}

/// The pinned interaction states every control is shown in.
let galleryStates: [(String, CoreInteraction?)] = [
    ("Rest", nil), ("Hover", .hover), ("Pressed", .pressed), ("Focus", .focused),
]

#if os(macOS)
import AppKit

/// Makes the window's title bar the same surface as the gallery: transparent, content running underneath it.
struct UnifiedTitleBar: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ nsView: NSView, context: Context) {}
    private final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
        }
    }
}
#endif
#endif
