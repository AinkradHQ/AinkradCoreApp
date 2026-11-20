import CoreUI
import Foundation
import Observation
import SwiftUI

/// E12-6 (D-34): crash reports are ON by default. The report holds no personal content (see `CrashReport`); it goes to our
/// own server. This is the one switch, in the first-run welcome and in Settings, Privacy.
@MainActor @Observable
public final class CrashReportPrefs {
    public static let shared = CrashReportPrefs()
    private nonisolated static let key = "ainkrad.crashReports"
    public var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: Self.key) } }
    private init() { enabled = Self.isEnabled }
    /// Readable from anywhere (a crash handler runs off the main actor). Unset means on.
    public nonisolated static var isEnabled: Bool { (UserDefaults.standard.object(forKey: key) as? Bool) ?? true }
}

/// The switch and the words that say what is sent.
public struct CrashReportsSwitch: View {
    @Bindable private var prefs = CrashReportPrefs.shared
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            CoreSwitch("Send crash reports", isOn: $prefs.enabled)
            Text(
                "If Ainkrad crashes, it sends the app version, the macOS version and where it stopped, to Ainkrad's own server. No names, files, Core addresses or anything you typed."
            )
            .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }
}
