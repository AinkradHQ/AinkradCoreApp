import AppKit
import CoreImage.CIFilterBuiltins
import CoreUI
import SwiftUI

/// A QR code for the pairing payload. The image is data (dark modules on a light field, with its own quiet zone), so it is the
/// one thing here that does not take theme colours: scanners need that contrast.
struct QRImage: View {
    let text: String
    @Environment(\.corePalette) private var palette

    var body: some View {
        Group {
            if let image = Self.render(text) {
                Image(nsImage: image).interpolation(.none).resizable().scaledToFit()
                    .padding(Space.s2)
                    .background(Color(nsColor: .white), in: coreShape(Radius.cardMac))
            }
        }
        .accessibilityLabel("QR code for this pairing")
    }

    static func render(_ text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let out = filter.outputImage else { return nil }
        let scaled = out.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
