import Foundation

/// Where the sheet sits inside the presenting view.
///
/// On iPhone the system keeps the sheet at the bottom. On iPhone Duo,
/// `leading`, `center`, and `trailing` place it on an edge.
/// `automatic` lets the system choose.
///
/// `withDuo` sets a different position for each hinge state. `closed` is the
/// outer screen, `partiallyOpen` is half open, and `fullyOpen` is open as far
/// as the device allows. A phone without a hinge keeps the system placement.
enum BottomSheetPlacement: Equatable {
    case automatic
    case leading
    case center
    case trailing
    indirect case withDuo(
        closed: BottomSheetPlacement,
        partiallyOpen: BottomSheetPlacement,
        fullyOpen: BottomSheetPlacement
    )

    /// A position UIKit can apply. A nested `withDuo` falls back to `automatic`.
    var leaf: BottomSheetPlacement {
        switch self {
        case .withDuo:
            return .automatic
        default:
            return self
        }
    }
}
