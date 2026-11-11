import CoreUI
import SwiftUI

/// Settings, Mac, You: the name Home greets you with. Kept on this Mac only; the one place to change it after setup.
struct YouSection: View {
    @Bindable var profile: UserProfile
    @State private var draft = ""

    var body: some View {
        GlassSection(
            "Your name", sub: "Home greets you with it. It stays on this Mac.", symbol: "person", hue: GlassInk.blue
        ) {
            CoreTextField("Your name", placeholder: "Ahmed", text: $draft, onSubmit: save)
                .onChange(of: draft) { _, new in profile.set(new) }
        }
        .foregroundStyle(GlassInk.primary)
        .onAppear { draft = profile.name }
    }

    private func save() { profile.set(draft) }
}
