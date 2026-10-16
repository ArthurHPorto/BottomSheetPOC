import UIKit

/// Paints an opaque fill on the parent of the presentation hosting view.
/// That parent is the full sheet width. The hosting view stays clear, so on
/// iPhone Duo the uncovered strip would otherwise show the sheet material.
struct SheetBackdrop {
    private var fillView: UIView?

    mutating func apply(color: UIColor, root: UIView, hosted: UIView) {
        root.backgroundColor = color
        hosted.backgroundColor = color
        guard let clipping = clippingView(from: root) else { return }
        let fill: UIView
        if let existing = fillView, existing.superview === clipping {
            fill = existing
        } else {
            fillView?.removeFromSuperview()
            let view = UIView()
            view.isUserInteractionEnabled = false
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            clipping.insertSubview(view, at: 0)
            fillView = view
            fill = view
        }
        let target = clipping.bounds
        if fill.frame != target {
            UIView.performWithoutAnimation {
                fill.frame = target
            }
        }
        fill.backgroundColor = color
    }

    private func clippingView(from view: UIView) -> UIView? {
        var current: UIView? = view
        while let next = current?.superview {
            let name = NSStringFromClass(type(of: next))
            if name.contains("PresentationHostingController"), name.contains("HostingView") {
                return next.superview
            }
            current = next
        }
        return nil
    }
}
