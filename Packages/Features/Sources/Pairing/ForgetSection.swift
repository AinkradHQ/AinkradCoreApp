import CoreUI
import SwiftUI

/// Settings → Core → Forget this Core: what forgetting does, as three plain facts, and the one action (it asks again before
/// anything happens). Wipes this Mac's keys for the Core and returns to the Connect screen.
struct ForgetSection: View {
    @Bindable var app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(spacing: Space.s4) {
                IconTile("link.badge.plus", hue: GlassInk.blue, size: 56).shadow(
                    color: GlassInk.blue.opacity(0.45), radius: 14)
                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        app.service == nil
                            ? "Not connected to a Core" : "This Mac is paired with \(app.shell.home.coreName)"
                    )
                    .font(.system(size: MacTextSize.large, weight: .bold))
                    Text("Forget it to pair with another Core, or to start this one over from a new code.")
                        .foregroundStyle(GlassInk.secondary)
                }
                Spacer(minLength: Space.s3)
                AppActionTile(title: "Forget this Core", symbol: "trash", key: "", hue: GlassInk.red, prominent: true) {
                    app.confirmForget = true
                }
                .accessibilityIdentifier("forget-core")
            }
            .padding(Space.s4)
            .background(GlassInk.blue.opacity(0.08), in: coreShape(Radius.cardMac))
            .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.blue.opacity(0.35), lineWidth: 1) }
            HStack(alignment: .top, spacing: Space.s3) {
                fact("key.slash", GlassInk.red, "This Mac's keys", "Deleted from this Mac.")
                fact("qrcode", GlassInk.orange, "To come back", "A new pairing code from an admin device.")
                fact("externaldrive.badge.checkmark", GlassInk.green, "Your Core and its data", "Not touched.")
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(GlassInk.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fact(_ symbol: String, _ hue: Color, _ title: String, _ line: String) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            IconTile(symbol, hue: hue, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: MacTextSize.headline, weight: .semibold))
                Text(line).foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
        .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
    }
}
