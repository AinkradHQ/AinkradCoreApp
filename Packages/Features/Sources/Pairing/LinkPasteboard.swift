import AppKit

/// Where a copied connect link goes. The link holds a one-time owner secret, so it is written as concealed and transient
/// (clipboard managers skip both) and the model takes it back.
@MainActor
protocol LinkPasteboard: AnyObject {
    var changeCount: Int { get }
    /// Replaces the pasteboard's contents with `text`; returns the change count right after.
    func write(secret text: String) -> Int
    func clear()
}

@MainActor
final class SystemLinkPasteboard: LinkPasteboard {
    static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    private let board: NSPasteboard
    init(_ board: NSPasteboard = .general) { self.board = board }

    var changeCount: Int { board.changeCount }
    func write(secret text: String) -> Int {
        board.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: Self.concealed)
        item.setData(Data(), forType: Self.transient)
        board.writeObjects([item])
        return board.changeCount
    }
    func clear() { board.clearContents() }
}
