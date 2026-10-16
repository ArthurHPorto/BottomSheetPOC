import SwiftUI
import UIKit

struct SheetBlock: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var detail: String
    var startsCollapsed: Bool = false
    var shown: Bool = true
}

