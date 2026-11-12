#if DEBUG
import CoreKit
import Foundation
import Shell

/// Debug only: the wizard and Add device by QR in a named state for the snapshot runner. Nothing leaves the app.
extension AppModel {
    public static let wizardScenes = [
        "choose", "install", "connect", "connect-filled", "connecting", "mismatch", "badinvite", "offline",
    ]

    public func debugWizard(_ scene: String) {
        phase = .firstRun
        useTypedCode = false
        let fp = Wire.b64(Data(repeating: 7, count: 32))
        let link = "ainkrad://connect?host=core.example.com&fp=\(fp)&secret=\(Wire.b64(Data(repeating: 9, count: 16)))"
        switch scene {
        case "choose": wizard.debugSet(.choose)
        case "install": wizard.debugSet(.install)
        case "connect": wizard.debugSet(.connect)
        case "connect-filled": wizard.debugSet(.connect, link: link)
        case "connecting": wizard.debugSet(.connecting, link: link)
        case "mismatch": wizard.debugSet(.failed(Failure(kind: .identityMismatch)), link: link)
        case "badinvite": wizard.debugSet(.failed(Failure(kind: .badInvite)), link: link)
        case "offline":
            wizard.debugSet(.failed(Failure(kind: .offline("core.example.com did not answer."))), link: link)
        default: break
        }
    }

    /// Add device (N17) on sample data, one step per scene. Nothing is made: the steps that need the Core show their
    /// waiting state.
    public static let addWizardScenes = ["what", "install-mac", "install-linux", "connect-mac", "access", "done"]

    public func debugAddWizard(_ scene: String) {
        shell.closeDialog()
        let kind: AddKind? =
            switch scene {
            case "what": nil
            case "install-linux": .linuxRunner
            case "access", "done": .phone
            default: .mac
            }
        let model = AddWizardModel(app: self, kind: kind)
        model.step =
            switch scene {
            case "what": .what
            case "connect-mac": .connect
            case "access": .access
            case "done": .done
            default: .install
            }
        shell.present(
            ShellDialog(id: "add-wizard", onClose: {}) {
                AddWizardView(app: self, model: model, close: { [weak self] in self?.shell.closeDialog() })
            })
    }

    /// Add device by QR on sample data (it cannot connect anything): the dialog, made at once.
    public func debugOpenInviteDevice() {
        invites = SampleInviteService(
            host: "core.example.com", coreFingerprint: Wire.b64(Data(repeating: 7, count: 32)))
        openInviteDevice()
    }
}
#endif
