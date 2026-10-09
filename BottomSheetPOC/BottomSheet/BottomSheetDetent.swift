import Foundation

/// Resting heights supported by the bottom sheet.
///
/// Values map onto `UISheetPresentationController.Detent`. `.content` tracks the
/// SwiftUI view and animates when that view grows or shrinks.
enum BottomSheetDetent: Hashable {
    /// About half the screen. Inactive in compact height.
    case medium
    /// The system full height.
    case large
    /// A fraction of the maximum detent, clamped to `0...1`.
    case fraction(CGFloat)
    /// A fixed height in points, measured inside the sheet safe area.
    case height(CGFloat)
    /// The measured height of the SwiftUI content.
    case content

    var identifier: String {
        switch self {
        case .medium:
            return "medium"
        case .large:
            return "large"
        case .content:
            return "content"
        case .fraction(let value):
            return String(format: "fraction-%.4f", value)
        case .height(let value):
            return String(format: "height-%.2f", value)
        }
    }
}
