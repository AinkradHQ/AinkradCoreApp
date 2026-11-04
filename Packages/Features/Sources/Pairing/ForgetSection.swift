import CoreUI
import SwiftUI

/// Settings → Core → Forget this Core: wipes this Mac's keys for the Core and returns to the Connect screen (after a confirmation).
struct ForgetSection: View {
    @Bindable var app: AppModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text(
                "This Mac stops being paired with the Core. Its keys for it are deleted from this Mac, and you will need a new pairing code to connect again. The Core and its data are not touched."
            )
            .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Forget this Core…") { app.confirmForget = true }
                    .buttonStyle(CoreButtonStyle(.secondary))
                    .accessibilityIdentifier("forget-core")
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
