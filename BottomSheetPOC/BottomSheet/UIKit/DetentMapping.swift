import SwiftUI
import UIKit

enum DetentMapping {
    static func ordered(
        _ detents: [BottomSheetDetent],
        maxHeight: CGFloat,
        contentHeight: CGFloat
    ) -> [BottomSheetDetent] {
        let source = detents.isEmpty ? [.content] : detents
        return source.sorted { lhs, rhs in
            let left = lhs.ordering(maxHeight: maxHeight, contentHeight: contentHeight)
            let right = rhs.ordering(maxHeight: maxHeight, contentHeight: contentHeight)
            if left.height != right.height {
                return left.height < right.height
            }
            return left.tieBreak < right.tieBreak
        }
    }

    static func uiKitDetents(
        from detents: [BottomSheetDetent],
        maxHeight: CGFloat,
        contentHeight: CGFloat,
        content: @escaping (_ maximum: CGFloat) -> CGFloat
    ) -> [UISheetPresentationController.Detent] {
        var seen = Set<String>()
        let mapped = ordered(detents, maxHeight: maxHeight, contentHeight: contentHeight).compactMap { detent -> UISheetPresentationController.Detent? in
            guard seen.insert(detent.identifier).inserted else { return nil }
            return uiKitDetent(detent, content: content)
        }
        return mapped.isEmpty ? [.large()] : mapped
    }

    static func uiKitDetent(
        _ detent: BottomSheetDetent,
        content: @escaping (_ maximum: CGFloat) -> CGFloat
    ) -> UISheetPresentationController.Detent {
        switch detent {
        case .medium:
            return .medium()
        case .large:
            return .large()
        case .fraction(let value):
            let fraction = min(max(value, 0), 1)
            return .custom(identifier: detent.uiKitIdentifier) { context in
                context.maximumDetentValue * fraction
            }
        case .height(let value):
            let height = max(value, 1)
            return .custom(identifier: detent.uiKitIdentifier) { context in
                min(height, context.maximumDetentValue)
            }
        case .content:
            return .custom(identifier: detent.uiKitIdentifier) { context in
                content(context.maximumDetentValue)
            }
        }
    }
}

extension BottomSheetDetent {
    var uiKitIdentifier: UISheetPresentationController.Detent.Identifier {
        switch self {
        case .medium:
            return .medium
        case .large:
            return .large
        default:
            return UISheetPresentationController.Detent.Identifier(identifier)
        }
    }

    func ordering(maxHeight: CGFloat, contentHeight: CGFloat) -> (height: CGFloat, tieBreak: Int) {
        switch self {
        case .content:
            return (contentHeight > 1 ? contentHeight : 0, 0)
        case .height(let height):
            return (max(height, 0), 1)
        case .fraction(let value):
            return (maxHeight * min(max(value, 0), 1), 2)
        case .medium:
            return (maxHeight * 0.5, 3)
        case .large:
            return (maxHeight, 4)
        }
    }
}

extension BottomSheetAdaptiveStyle {
    var modalStyle: UIModalPresentationStyle {
        switch self {
        case .none:
            return .none
        case .pageSheet:
            return .pageSheet
        case .formSheet:
            return .formSheet
        case .fullScreen:
            return .fullScreen
        case .overFullScreen:
            return .overFullScreen
        }
    }

    init?(_ style: UIModalPresentationStyle) {
        switch style {
        case .none:
            self = .none
        case .pageSheet:
            self = .pageSheet
        case .formSheet:
            self = .formSheet
        case .fullScreen:
            self = .fullScreen
        case .overFullScreen:
            self = .overFullScreen
        default:
            return nil
        }
    }
}

struct SheetOptions: Equatable {
    var detents: [BottomSheetDetent]
    var largestUndimmedDetent: BottomSheetDetent?
    var prefersGrabberVisible: Bool
    var prefersScrollingExpandsWhenScrolledToEdge: Bool
    var prefersEdgeAttachedInCompactHeight: Bool
    var widthFollowsPreferredContentSizeWhenEdgeAttached: Bool
    var preferredCornerRadius: CGFloat?
    var preferredContentWidth: CGFloat?
    var centersOnSourceView: Bool
    var isModalInPresentation: Bool
    var backgroundDescription: String
    var grabberContentInset: CGFloat
    var adaptiveStyle: BottomSheetAdaptiveStyle?

    init(_ configuration: BottomSheetConfiguration) {
        detents = configuration.detents
        largestUndimmedDetent = configuration.largestUndimmedDetent
        prefersGrabberVisible = configuration.prefersGrabberVisible
        prefersScrollingExpandsWhenScrolledToEdge = configuration.prefersScrollingExpandsWhenScrolledToEdge
        prefersEdgeAttachedInCompactHeight = configuration.prefersEdgeAttachedInCompactHeight
        widthFollowsPreferredContentSizeWhenEdgeAttached = configuration.widthFollowsPreferredContentSizeWhenEdgeAttached
        preferredCornerRadius = configuration.preferredCornerRadius
        preferredContentWidth = configuration.preferredContentWidth
        centersOnSourceView = configuration.centersOnSourceView
        isModalInPresentation = configuration.isModalInPresentation
        backgroundDescription = String(describing: configuration.backgroundColor)
        grabberContentInset = configuration.grabberContentInset
        adaptiveStyle = configuration.adaptiveStyle
    }
}
