import SwiftUI

/// Where an edge-attached sheet prefers to sit. Applied on iOS 27 and later.
enum BottomSheetPlacement: Equatable {
    case automatic
    case leading
    case center
    case trailing
}

/// How the sheet adapts in a compact size class.
///
/// `nil` keeps the system sheet. Any other value is forwarded from
/// `UIAdaptivePresentationControllerDelegate`.
enum BottomSheetAdaptiveStyle: Equatable {
    case none
    case pageSheet
    case formSheet
    case fullScreen
    case overFullScreen
}

/// Material painted behind a detent. Applied on iOS 26.1 and later.
enum BottomSheetDetentMaterial: Equatable {
    case systemChrome
    case systemMaterial
    case systemThinMaterial
    case systemUltraThinMaterial
    case systemThickMaterial
}

/// Everything SwiftUI is allowed to customize. Presentation itself stays in UIKit.
struct BottomSheetConfiguration {
    /// Detents from shortest to tallest after layout. At least one is required.
    var detents: [BottomSheetDetent] = [.content]

    /// Largest detent that leaves the background undimmed. `nil` dims every detent.
    var largestUndimmedDetent: BottomSheetDetent?

    var prefersGrabberVisible = true
    var prefersScrollingExpandsWhenScrolledToEdge = true
    var prefersEdgeAttachedInCompactHeight = false
    var widthFollowsPreferredContentSizeWhenEdgeAttached = false

    /// `nil` keeps the system corner radius.
    var preferredCornerRadius: CGFloat?

    /// Used when `widthFollowsPreferredContentSizeWhenEdgeAttached` is true.
    var preferredContentWidth: CGFloat?

    /// On iOS 17 and later this stays `true` so detents, not page sizing, own the height.
    var prefersPageSizing = true

    var preferredPlacement: BottomSheetPlacement = .automatic

    /// Centers the sheet over the presenting view. Ignored while a placement is explicit on iOS 27+.
    var centersOnSourceView = false

    var isModalInPresentation = false
    var backgroundColor: Color = Color(uiColor: .systemBackground)
    var detentMaterial: BottomSheetDetentMaterial?

    /// Extra space above the SwiftUI content while the grabber is visible.
    var grabberContentInset: CGFloat = 16

    var adaptiveStyle: BottomSheetAdaptiveStyle?

    /// Return `false` to block an interactive dismiss.
    var shouldDismiss: (() -> Bool)?

    var onWillDismiss: (() -> Void)?
    var onDidAttemptToDismiss: (() -> Void)?
    var onDetentChange: ((BottomSheetDetent) -> Void)?
    var onAdaptivePresentation: ((BottomSheetAdaptiveStyle) -> Void)?
}
