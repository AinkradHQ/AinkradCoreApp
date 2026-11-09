import SwiftUI

extension View {
    /// A pane takes key focus back when everything the shell showed over it (launcher, dialog, sheet, bell, Settings) has gone,
    /// so Esc and the arrow keys reach it again. Without this the field that held focus under the cover leaves it with nobody.
    /// `retake` is what the pane does on appear (focus its list, or its composer).
    public func retakeFocus(after shell: ShellModel, _ retake: @escaping @MainActor () -> Void) -> some View {
        onChange(of: shell.coverOpen) { _, open in
            // One turn later: the cover's own field is still leaving while this runs.
            if !open { Task { @MainActor in retake() } }
        }
    }
}
