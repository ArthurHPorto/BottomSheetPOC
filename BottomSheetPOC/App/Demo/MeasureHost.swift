import SwiftUI
import UIKit

final class MeasureHost: UIView {
    let hostingController = UIHostingController(rootView: AnyView(EmptyView()))
    var onHeight: (CGFloat) -> Void = { _ in }
    private var lastHeight: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        isAccessibilityElement = false
        hostingController.view.backgroundColor = .clear
        hostingController.view.isUserInteractionEnabled = false
        hostingController.view.alpha = 0
        addSubview(hostingController.view)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 0)
    }

    func setContent(_ content: AnyView) {
        hostingController.rootView = content
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        guard width > 1 else { return }
        let height = hostingController.sizeThatFits(in: CGSize(width: width, height: UIView.layoutFittingExpandedSize.height)).height
        guard height > 1, abs(height - lastHeight) > 0.5 else { return }
        lastHeight = height
        hostingController.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        let report = onHeight
        DispatchQueue.main.async {
            report(height)
        }
    }
}

