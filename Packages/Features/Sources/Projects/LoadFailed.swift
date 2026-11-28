import CoreUI
import SwiftUI

/// A read that failed, said as that: never an empty list. "Unable to load the activity." with the reason and Try Again.
struct LoadFailed: View {
    let what: String
    var why: String?
    let retry: () -> Void

    var body: some View {
        CoreNotice(symbol: "exclamationmark.triangle", title: "Unable to load \(what).", text: why.map(GalleryView.plain) ?? "", tone: .fail) {
            Button("Try Again", action: retry).buttonStyle(CoreButtonStyle(.secondary, size: .small))
        }
    }
}
