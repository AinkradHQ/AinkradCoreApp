import SwiftUI

extension Text {
    /// A literal looks its words up in this module's own String Catalog (`Bundle.module`), not the app's.
    init(_ key: LocalizedStringKey) { self.init(key, tableName: nil, bundle: .module, comment: nil) }
}
