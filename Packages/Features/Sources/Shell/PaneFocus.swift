import SwiftUI

extension View {
    /// A pane takes key focus back when everything the shell showed over it (launcher, dialog, sheet, bell, Settings) has gone,
    /// so Esc and the arrow keys reach it again. Without this the field that held focus under the cover leaves it with nobody.
    /// `retake` is what the pane does on appear (focus its list, or its composer).
    /// Only the pane `pane` itself, showing in the workspace and active, takes focus: a hidden Home or a sibling split must not.
    public func retakeFocus(
        after shell: ShellModel, pane: String, _ retake: @escaping @MainActor () -> Void
    ) -> some View {
        onChange(of: shell.coverOpen) { _, open in
            // One turn later: the cover's own field is still leaving while this runs.
            if !open { Task { @MainActor in if shell.isFront(pane) { retake() } } }
        }
    }
}
