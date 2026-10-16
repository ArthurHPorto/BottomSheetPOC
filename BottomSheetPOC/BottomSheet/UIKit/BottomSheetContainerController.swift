import SwiftUI
import UIKit

/// Presents SwiftUI content with `UISheetPresentationController`.
///
/// SwiftUI animates each block's height with `BottomSheetMotion.active`.
/// The sheet copies that height on the next frame, so the frame and the
/// content stay on the same curve instead of running two animations.
final class BottomSheetContainerController<Content: View>: UIViewController, UISheetPresentationControllerDelegate {
    private let heightRelay = HeightRelay()
    private let hostingController: UIHostingController<BottomSheetRoot<Content>>

    private var configuration = BottomSheetConfiguration()
    private var sourceView: UIView?
    private var appliedOptions: SheetOptions?
    private var lastAppliedSelection: BottomSheetDetent?
    private var heightTracker = ContentHeightTracker()
    private var edgeGuard = EdgeAttachedGuard()
    private var backdrop = SheetBackdrop()
    private var hasAppeared = false
    private var didInstallRoot = false
    private var latestContent: Content?
    private var isApplyingHeight = false
    private var lastDetentValue: CGFloat = 0
    private var lastMaximumDetentValue: CGFloat = 0

    var onSelectedDetentChanged: (BottomSheetDetent) -> Void = { _ in }
    /// `UISheetPresentationControllerDelegate` selected-detent change.
    var onDetentChange: (BottomSheetDetent) -> Void = { _ in }
    /// `presentationControllerDidDismiss`, not SwiftUI's `.sheet(onDismiss:)`.
    var onDismiss: () -> Void = {}
    /// First rendered height, then each target height immediately before its transition.
    var onHeightChange: (CGFloat) -> Void = { _ in }

    /// Tokens da sheet. A configuração fica nesta função: quem apresenta a sheet
    /// não recebe nem envia um `BottomSheetConfiguration`.
    func designSystemConfiguration() -> BottomSheetConfiguration {
        var configuration = BottomSheetConfiguration()
        configuration.detents = [.content, .large]
        configuration.largestUndimmedDetent = .content
        configuration.prefersGrabberVisible = true
        configuration.preferredCornerRadius = 28
        configuration.prefersScrollingExpandsWhenScrolledToEdge = true
        return configuration
    }

    init(content: Content) {
        hostingController = UIHostingController(
            rootView: BottomSheetRoot(content: content, relay: heightRelay)
        )
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        edgesForExtendedLayout = .all
        hostingController.sizingOptions = []
        hostingController.view.backgroundColor = .clear
        hostingController.view.clipsToBounds = true
        hostingController.view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        hostingController.view.setContentHuggingPriority(.defaultLow, for: .vertical)
        heightRelay.onChange = { [weak self] height in
            self?.noteContentHeight(height)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configuration = designSystemConfiguration()
        applyBackground()
        view.clipsToBounds = true
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hostingController.didMove(toParent: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        attachSheetIfNeeded()
        refreshMetricsIfNeeded()
        avoidEdgeAttachedFlashIfNeeded()
        applyBackground()
    }

    /// The presentation `HostingView` stays clear and only covers part of its
    /// parent with content. On iPhone Duo the uncovered strip shows the sheet
    /// material. The opaque color belongs on that parent, `_UIDropShadowClippingView`.
    private func applyBackground() {
        backdrop.apply(
            color: UIColor(configuration.backgroundColor),
            root: view,
            hosted: hostingController.view
        )
    }

    /// A floating sheet switches to the edge-attached shape for one exact detent value.
    /// The guard learns that value. This method only asks UIKit to resolve the detents again.
    private func avoidEdgeAttachedFlashIfNeeded() {
        guard let window = view.window, let sheet = resolvedSheet else { return }
        let bottom = view.convert(view.bounds, to: window).maxY
        guard edgeGuard.valueToAvoid(
            hasAppeared: hasAppeared,
            isBeingPresented: isBeingPresented,
            isBeingDismissed: isBeingDismissed,
            isShowingContentDetent: isShowingContentDetent,
            bottom: bottom,
            windowHeight: window.bounds.height,
            lastDetentValue: lastDetentValue,
            lastMaximumDetentValue: lastMaximumDetentValue
        ) != nil else { return }
        UIView.performWithoutAnimation {
            sheet.invalidateDetents()
            sheet.containerView?.layoutIfNeeded()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hasAppeared = true
        attachSheetIfNeeded()
        catchUpAfterTransition()
        if heightTracker.measuredContentHeight < 2 {
            let estimated = estimateHeight(width: currentWidth)
            if estimated > 1 {
                noteContentHeight(estimated)
            }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || presentingViewController == nil {
            heightTracker.resetPresentation(keepingMeasuredHeight: heightTracker.measuredContentHeight)
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyBackground()
    }

    func update(
        content: Content,
        selection: BottomSheetDetent?,
        sourceView: UIView?,
        width: CGFloat
    ) {
        configuration = designSystemConfiguration()
        self.sourceView = sourceView
        latestContent = content
        // Replacing rootView after the sheet is up throws away the in-flight
        // SwiftUI insertion animation and snaps every row into place.
        if !didInstallRoot {
            installRoot(content)
        }
        applyBackground()
        isModalInPresentation = configuration.isModalInPresentation

        if heightTracker.measuredContentHeight < 2 {
            let estimated = estimateHeight(width: width, content: content)
            heightTracker.seed(estimated)
        }

        let options = SheetOptions(configuration)
        if options != appliedOptions {
            appliedOptions = options
            applyChrome(animated: hasAppeared && resolvedSheet != nil)
        }
        applySelection(selection)
        publishPreferredContentSize(width: width)
    }

    func noteContentHeight(_ height: CGFloat) {
        // The content has a fixed vertical size inside a `ScrollView`, so this is its
        // ideal height. Taller content is capped by the detent resolver and scrolls.
        let scale = view.window?.screen.scale ?? UIScreen.main.scale
        let canTrack = hasAppeared
            && resolvedSheet != nil
            && !isBeingPresented
            && !isBeingDismissed
            && isShowingContentDetent
        guard let decision = heightTracker.note(
            height: height,
            scale: scale,
            canTrack: canTrack,
            now: CACurrentMediaTime()
        ) else { return }
        if decision.announcement != nil {
            onHeightChange(decision.height)
        }
        if decision.shouldApply {
            applyTrackedHeight()
        }
    }

    /// Heights that changed while the sheet was sliding in were not applied, so the
    /// sheet would snap on the first frame after. Announce the target, then animate.
    private func catchUpAfterTransition() {
        guard let sheet = resolvedSheet, isShowingContentDetent, heightTracker.measuredContentHeight > 1 else { return }
        guard abs(heightTracker.measuredContentHeight - heightTracker.resolvedDetentHeight) > 0.5 else { return }
        if let _ = heightTracker.announceCatchUp(heightTracker.measuredContentHeight) {
            onHeightChange(heightTracker.measuredContentHeight)
        }
        sheet.animateChanges {
            sheet.invalidateDetents()
        }
    }

    /// Applies the latest height without animation, in the same turn as the measurement.
    /// The content already animates, so a second sheet animation would lag the rows.
    /// `layoutIfNeeded` commits that height before the frame is shown. Without it the
    /// sheet catches up a frame later and shivers against the rows.
    private func applyTrackedHeight() {
        guard !isApplyingHeight, let sheet = resolvedSheet else { return }
        isApplyingHeight = true
        defer { isApplyingHeight = false }
        var passes = 0
        repeat {
            passes += 1
            let applied = heightTracker.measuredContentHeight
            UIView.performWithoutAnimation {
                sheet.invalidateDetents()
                sheet.containerView?.layoutIfNeeded()
            }
            let scale = view.window?.screen.scale ?? UIScreen.main.scale
            let pixel: CGFloat = scale > 1 ? 1 / scale : 1
            if abs(heightTracker.measuredContentHeight - applied) < pixel || passes == 2 {
                break
            }
        } while true
    }

    /// The sheet SwiftUI presented, whether this controller is the presented
    /// controller or a child of it.
    private var resolvedSheet: UISheetPresentationController? {
        var controller: UIViewController? = self
        while let current = controller {
            if let sheet = current.sheetPresentationController {
                return sheet
            }
            controller = current.parent
        }
        return nil
    }

    /// Keeps the last controls above the home indicator. The window inset stays
    /// put while the sheet moves. The view's own inset animates with it, and
    /// feeding that back into the content restarts the detent mid-gesture.
    private var bottomContentInset: CGFloat {
        if let bottom = view.window?.safeAreaInsets.bottom, bottom > 0 {
            return bottom
        }
        return view.safeAreaInsets.bottom
    }

    private func installRoot(_ content: Content) {
        heightRelay.grabberInset = effectiveGrabberInset
        heightRelay.bottomInset = bottomContentInset
        hostingController.rootView = BottomSheetRoot(content: content, relay: heightRelay)
        didInstallRoot = true
    }

    /// Insets update in place. Replacing `rootView` throws away the blocks that are mid-animation.
    private func refreshMetricsIfNeeded() {
        guard didInstallRoot else { return }
        let grabber = effectiveGrabberInset
        let bottom = bottomContentInset
        if heightRelay.grabberInset != grabber {
            heightRelay.grabberInset = grabber
        }
        if heightRelay.bottomInset != bottom {
            heightRelay.bottomInset = bottom
        }
    }

    private func attachSheetIfNeeded() {
        guard let sheet = resolvedSheet, sheet.delegate !== self else { return }
        sheet.delegate = self
        applyChrome(animated: false)
    }

    private var effectiveGrabberInset: CGFloat {
        configuration.prefersGrabberVisible ? max(configuration.grabberContentInset, 0) : 0
    }

    private var currentWidth: CGFloat {
        if view.bounds.width > 1 {
            return view.bounds.width
        }
        if let width = view.window?.bounds.width, width > 1 {
            return width
        }
        return UIScreen.main.bounds.width
    }

    private var isShowingContentDetent: Bool {
        guard let identifier = resolvedSheet?.selectedDetentIdentifier else { return true }
        return identifier == BottomSheetDetent.content.uiKitIdentifier
    }

    private func pushDetentHeight() {
        guard let sheet = resolvedSheet else { return }
        let detents = makeDetents()
        let identifiers = detents.map(\.identifier)
        if sheet.detents.map(\.identifier) != identifiers {
            sheet.detents = detents
        } else {
            sheet.invalidateDetents()
        }
    }

    private func applyChrome(animated: Bool) {
        guard let sheet = resolvedSheet else { return }
        performChanges(animated: animated) {
            sheet.prefersGrabberVisible = configuration.prefersGrabberVisible
            sheet.prefersScrollingExpandsWhenScrolledToEdge = configuration.prefersScrollingExpandsWhenScrolledToEdge
            sheet.prefersEdgeAttachedInCompactHeight = configuration.prefersEdgeAttachedInCompactHeight
            sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = configuration.widthFollowsPreferredContentSizeWhenEdgeAttached
            sheet.preferredCornerRadius = configuration.preferredCornerRadius
            sheet.sourceView = configuration.centersOnSourceView ? sourceView : nil
            installDetents(preservingSelection: true)
            applyUndimmed(on: sheet)
            if let selection = lastAppliedSelection {
                sheet.selectedDetentIdentifier = selection.uiKitIdentifier
            }
        }
        sheet.delegate = self
    }

    private func applySelection(_ selection: BottomSheetDetent?) {
        guard selection != lastAppliedSelection else { return }
        lastAppliedSelection = selection
        guard let sheet = resolvedSheet else { return }
        let animated = hasAppeared && !isBeingPresented
        if animated, let height = transitionTargetHeight(for: selection), heightTracker.announceTarget(height) != nil {
            onHeightChange(height)
        }
        performChanges(animated: animated) {
            sheet.selectedDetentIdentifier = selection?.uiKitIdentifier
        }
    }

    /// Point height the sheet will animate toward for a detent change.
    private func transitionTargetHeight(for selection: BottomSheetDetent?) -> CGFloat? {
        switch selection {
        case .content:
            return heightTracker.measuredContentHeight > 1 ? heightTracker.measuredContentHeight : nil
        case .large:
            return lastMaximumDetentValue > 1 ? lastMaximumDetentValue : nil
        case .medium:
            return lastMaximumDetentValue > 1 ? lastMaximumDetentValue * 0.5 : nil
        case .height(let value):
            return value
        case .fraction(let value):
            return lastMaximumDetentValue > 1 ? lastMaximumDetentValue * min(max(value, 0), 1) : nil
        case nil:
            return nil
        }
    }

    private func installDetents(preservingSelection: Bool) {
        guard let sheet = resolvedSheet else { return }
        let selected = preservingSelection ? sheet.selectedDetentIdentifier : nil
        let detents = makeDetents()
        let identifiers = detents.map(\.identifier)
        if sheet.detents.map(\.identifier) != identifiers {
            sheet.detents = detents
        } else {
            sheet.invalidateDetents()
        }
        if let selected, identifiers.contains(selected) {
            sheet.selectedDetentIdentifier = selected
        }
        applyUndimmed(on: sheet)
    }

    private func applyUndimmed(on sheet: UISheetPresentationController) {
        sheet.largestUndimmedDetentIdentifier = configuration.largestUndimmedDetent?.uiKitIdentifier
    }

    private func performChanges(animated: Bool, _ changes: () -> Void) {
        guard let sheet = resolvedSheet else {
            changes()
            return
        }
        if animated {
            sheet.animateChanges(changes)
        } else {
            changes()
        }
    }

    /// Only the width is published. A preferred height makes SwiftUI size the hosted
    /// view to it, and the sheet stops following the content.
    private func publishPreferredContentSize(width: CGFloat) {
        guard let preferredWidth = configuration.preferredContentWidth, width > 1 else { return }
        let size = CGSize(width: preferredWidth, height: 0)
        guard preferredContentSize != size else { return }
        preferredContentSize = size
    }

    private func makeDetents() -> [UISheetPresentationController.Detent] {
        let maxHeight = view.window?.bounds.height ?? UIScreen.main.bounds.height
        return DetentMapping.uiKitDetents(
            from: configuration.detents,
            maxHeight: maxHeight,
            contentHeight: heightTracker.measuredContentHeight
        ) { [weak self] maximum in
            guard let self else { return 1 }
            let height = self.heightTracker.measuredContentHeight
            var value = height > 1 ? min(height, maximum) : 1
            if self.edgeGuard.avoidedDetentValues.contains(value) {
                value -= 1
            }
            if height > 1 {
                self.heightTracker.resolvedDetentHeight = height
            }
            self.lastDetentValue = value
            self.lastMaximumDetentValue = maximum
            return value
        }
    }

    private func normalizedDetents() -> [BottomSheetDetent] {
        configuration.detents.isEmpty ? [.content] : configuration.detents
    }

    private func estimateHeight(width: CGFloat, content: Content? = nil) -> CGFloat {
        let resolvedWidth = width > 1 ? width : currentWidth
        let root = BottomSheetHeightProbe(
            grabberInset: effectiveGrabberInset,
            bottomInset: bottomContentInset,
            content: content ?? hostingController.rootView.content
        )
        let probe = UIHostingController(rootView: root)
        probe.sizingOptions = [.intrinsicContentSize]
        probe.view.bounds = CGRect(x: 0, y: 0, width: resolvedWidth, height: 1)
        probe.view.setNeedsLayout()
        probe.view.layoutIfNeeded()

        let fitted = probe.sizeThatFits(in: CGSize(width: resolvedWidth, height: 0))
        let intrinsic = probe.view.intrinsicContentSize.height
        let candidates = [fitted.height, intrinsic].filter { $0.isFinite && $0 > 1 && $0 < 7_500 }
        guard let best = candidates.min() else { return 0 }
        return ceil(best)
    }

    func sheetPresentationControllerDidChangeSelectedDetentIdentifier(_ sheetPresentationController: UISheetPresentationController) {
        guard
            let identifier = sheetPresentationController.selectedDetentIdentifier,
            let detent = normalizedDetents().first(where: { $0.uiKitIdentifier == identifier })
        else {
            return
        }
        lastAppliedSelection = detent
        onSelectedDetentChanged(detent)
        onDetentChange(detent)
        configuration.onDetentChange?(detent)
    }

    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        configuration.adaptiveStyle?.modalStyle ?? .none
    }

    func adaptivePresentationStyle(
        for controller: UIPresentationController,
        traitCollection: UITraitCollection
    ) -> UIModalPresentationStyle {
        adaptivePresentationStyle(for: controller)
    }

    func presentationController(
        _ presentationController: UIPresentationController,
        willPresentWithAdaptiveStyle style: UIModalPresentationStyle,
        transitionCoordinator: UIViewControllerTransitionCoordinator?
    ) {
        guard let mapped = BottomSheetAdaptiveStyle(style) else { return }
        configuration.onAdaptivePresentation?(mapped)
    }

    func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
        configuration.shouldDismiss?() ?? true
    }

    func presentationControllerWillDismiss(_ presentationController: UIPresentationController) {
        configuration.onWillDismiss?()
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        onDismiss()
    }

    func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
        configuration.onDidAttemptToDismiss?()
    }
}

