import Combine
import SwiftUI
import UIKit

/// One height curve for SwiftUI and for the sheet detent.
///
/// Add a case with `animation`, `duration`, and `timing`. `perform` publishes it
/// as `active` for the rest of the turn, so the content layout and `noteContentHeight`
/// read the same value.
enum BottomSheetMotion: String, CaseIterable, Identifiable {
    case spring
    case ease
    case quick
    case linear
    case bouncy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spring: "Mola"
        case .ease: "Ease"
        case .quick: "Rápida"
        case .linear: "Linear"
        case .bouncy: "Elástica"
        }
    }

    var duration: TimeInterval {
        switch self {
        case .spring: 0.45
        case .ease: 0.45
        case .quick: 0.18
        case .linear: 0.35
        case .bouncy: 0.55
        }
    }

    var animation: Animation {
        switch self {
        case .spring:
            .spring(response: duration, dampingFraction: 1)
        case .ease:
            .easeInOut(duration: duration)
        case .quick:
            .easeOut(duration: duration)
        case .linear:
            .linear(duration: duration)
        case .bouncy:
            .spring(response: duration, dampingFraction: 0.62)
        }
    }

    var timing: UITimingCurveProvider {
        switch self {
        case .spring:
            Self.springTiming(response: duration, dampingFraction: 1)
        case .ease:
            UICubicTimingParameters(animationCurve: .easeInOut)
        case .quick:
            UICubicTimingParameters(animationCurve: .easeOut)
        case .linear:
            UICubicTimingParameters(animationCurve: .linear)
        case .bouncy:
            Self.springTiming(response: duration, dampingFraction: 0.62)
        }
    }

    /// Curve used by the sheet until the next `perform`.
    static var active: BottomSheetMotion = .spring

    static func perform(_ motion: BottomSheetMotion, _ updates: () -> Void) {
        active = motion
        // The container must not animate the insert itself. A second layout
        // transition keeps the previous cards on top of the new ones.
        // Each block animates its own height with `motion.animation`, and the
        // sheet follows that measured height.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, updates)
    }

    static func resolvedFromLaunchArguments() -> BottomSheetMotion {
        let arguments = ProcessInfo.processInfo.arguments
        guard
            let index = arguments.firstIndex(of: "-BottomSheetMotion"),
            arguments.indices.contains(arguments.index(after: index))
        else {
            return .spring
        }
        return BottomSheetMotion(rawValue: arguments[arguments.index(after: index)]) ?? .spring
    }

    /// 0 at the start and 1 when settled. Springs may pass 1 while they bounce.
    func unitProgress(elapsed: TimeInterval) -> CGFloat {
        let time = max(elapsed, 0)
        switch self {
        case .linear:
            return min(CGFloat(time / duration), 1)
        case .ease:
            let t = min(CGFloat(time / duration), 1)
            return t * t * (3 - 2 * t)
        case .quick:
            let t = min(CGFloat(time / duration), 1)
            return 1 - (1 - t) * (1 - t)
        case .spring:
            return Self.springProgress(elapsed: time, response: duration, dampingFraction: 1)
        case .bouncy:
            return Self.springProgress(elapsed: time, response: duration, dampingFraction: 0.62)
        }
    }

    var settlesAfter: TimeInterval {
        self == .bouncy ? duration * 2.6 : duration * 1.15
    }

    private static func springProgress(elapsed: TimeInterval, response: TimeInterval, dampingFraction: CGFloat) -> CGFloat {
        let omega = 2 * Double.pi / response
        let time = max(elapsed, 0)
        if dampingFraction >= 0.999 {
            let decay = exp(-omega * time)
            return CGFloat(1 - decay * (1 + omega * time))
        }
        let zeta = Double(dampingFraction)
        let damped = omega * sqrt(1 - zeta * zeta)
        let decay = exp(-zeta * omega * time)
        let value = 1 - decay * (cos(damped * time) + (zeta * omega / damped) * sin(damped * time))
        return CGFloat(value)
    }

    /// SwiftUI `spring(response:dampingFraction:)` as UIKit mass-spring constants.
    private static func springTiming(response: TimeInterval, dampingFraction: CGFloat) -> UISpringTimingParameters {
        let omega = 2 * CGFloat.pi / CGFloat(response)
        let stiffness = omega * omega
        let damping = 2 * dampingFraction * sqrt(stiffness)
        return UISpringTimingParameters(
            mass: 1,
            stiffness: stiffness,
            damping: damping,
            initialVelocity: .zero
        )
    }
}

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
    private var measuredContentHeight: CGFloat = 0
    private var heightTarget: CGFloat = 0
    private var hasAppeared = false
    private var didInstallRoot = false
    private var latestContent: Content?
    private var isApplyingHeight = false
    private var resolvedDetentHeight: CGFloat = 0
    private var lastDetentValue: CGFloat = 0
    private var lastMaximumDetentValue: CGFloat = 0
    private var avoidedDetentValues = Set<CGFloat>()
    private var hasSeenFloatingSheet = false

    var shouldDismiss: () -> Bool = { true }
    var onWillDismiss: () -> Void = {}
    var onDidAttemptToDismiss: () -> Void = {}
    var onSelectedDetentChanged: (BottomSheetDetent) -> Void = { _ in }
    var onAdaptivePresentation: (BottomSheetAdaptiveStyle) -> Void = { _ in }
    var onUserDismiss: () -> Void = {}

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
        view.backgroundColor = UIColor(configuration.backgroundColor)
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
    }

    /// A floating sheet switches to the edge-attached shape for one exact detent value,
    /// where its height plus the bottom inset equals the attached height (768 pt on a
    /// 874 pt screen). Growing through that value flashes the attached shape for a frame.
    /// The value is learned here, skipped by one point, and the layout is redone before
    /// the frame is committed.
    private func avoidEdgeAttachedFlashIfNeeded() {
        guard hasAppeared, !isBeingPresented, !isBeingDismissed, isShowingContentDetent else { return }
        guard let window = view.window, let sheet = resolvedSheet else { return }
        let bottom = view.convert(view.bounds, to: window).maxY
        if bottom < window.bounds.height - 0.5 {
            hasSeenFloatingSheet = true
            return
        }
        guard hasSeenFloatingSheet, abs(bottom - window.bounds.height) < 0.5 else { return }
        guard lastDetentValue > 1, lastDetentValue < lastMaximumDetentValue - 0.5 else { return }
        guard avoidedDetentValues.insert(lastDetentValue).inserted else { return }
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
        if measuredContentHeight < 2 {
            let estimated = estimateHeight(width: currentWidth)
            if estimated > 1 {
                noteContentHeight(estimated)
            }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || presentingViewController == nil {
            heightTarget = measuredContentHeight
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        let background = UIColor(configuration.backgroundColor)
        view.backgroundColor = background
        hostingController.view.backgroundColor = background
    }

    func update(
        content: Content,
        configuration: BottomSheetConfiguration,
        selection: BottomSheetDetent?,
        sourceView: UIView?,
        width: CGFloat
    ) {
        self.configuration = configuration
        self.sourceView = sourceView
        latestContent = content
        // Replacing rootView after the sheet is up throws away the in-flight
        // SwiftUI insertion animation and snaps every row into place.
        if !didInstallRoot {
            installRoot(content)
        }
        let background = UIColor(configuration.backgroundColor)
        view.backgroundColor = background
        hostingController.view.backgroundColor = background
        isModalInPresentation = configuration.isModalInPresentation

        if measuredContentHeight < 2 {
            let estimated = estimateHeight(width: width, content: content)
            if estimated > 1 {
                measuredContentHeight = estimated
                heightTarget = estimated
            }
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
        let next = ceil(height)
        guard next > 1, abs(next - heightTarget) >= 1 else { return }
        heightTarget = next
        measuredContentHeight = next
        let canTrack = hasAppeared
            && resolvedSheet != nil
            && !isBeingPresented
            && !isBeingDismissed
            && isShowingContentDetent
        guard canTrack else { return }
        applyTrackedHeight()
    }

    /// Heights that changed while the sheet was sliding in were not applied, so the
    /// sheet would snap on the first frame after. Animate that one catch-up instead.
    private func catchUpAfterTransition() {
        guard let sheet = resolvedSheet, isShowingContentDetent, measuredContentHeight > 1 else { return }
        guard abs(measuredContentHeight - resolvedDetentHeight) > 0.5 else { return }
        sheet.animateChanges {
            sheet.invalidateDetents()
        }
    }

    /// Applies the latest height without animation, in the same turn as the measurement.
    /// The content already animates, so a second sheet animation would lag the rows.
    private func applyTrackedHeight() {
        guard !isApplyingHeight, let sheet = resolvedSheet else { return }
        isApplyingHeight = true
        defer { isApplyingHeight = false }
        UIView.performWithoutAnimation {
            sheet.invalidateDetents()
        }
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

    /// Keeps the last controls above the home indicator. The view itself still
    /// paints through that inset, so the strip matches the rest of the sheet.
    private var bottomContentInset: CGFloat {
        let own = view.safeAreaInsets.bottom
        if own > 0 { return own }
        return view.window?.safeAreaInsets.bottom ?? 0
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
        performChanges(animated: hasAppeared && resolvedSheet != nil && !isBeingPresented) {
            sheet.selectedDetentIdentifier = selection?.uiKitIdentifier
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
        let ordered = normalizedDetents().sorted { lhs, rhs in
            let left = lhs.ordering(maxHeight: maxHeight, contentHeight: measuredContentHeight)
            let right = rhs.ordering(maxHeight: maxHeight, contentHeight: measuredContentHeight)
            if left.height != right.height {
                return left.height < right.height
            }
            return left.tieBreak < right.tieBreak
        }

        var seen = Set<String>()
        let detents = ordered.compactMap { detent -> UISheetPresentationController.Detent? in
            guard seen.insert(detent.identifier).inserted else { return nil }
            return uiKitDetent(for: detent)
        }
        return detents.isEmpty ? [.large()] : detents
    }

    private func normalizedDetents() -> [BottomSheetDetent] {
        configuration.detents.isEmpty ? [.content] : configuration.detents
    }

    private func uiKitDetent(for detent: BottomSheetDetent) -> UISheetPresentationController.Detent {
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
            return .custom(identifier: detent.uiKitIdentifier) { [weak self] context in
                guard let self else { return 1 }
                let height = self.measuredContentHeight
                var value = height > 1 ? min(height, context.maximumDetentValue) : 1
                if self.avoidedDetentValues.contains(value) {
                    value -= 1
                }
                if height > 1 {
                    self.resolvedDetentHeight = height
                }
                self.lastDetentValue = value
                self.lastMaximumDetentValue = context.maximumDetentValue
                return value
            }
        }
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
        onAdaptivePresentation(mapped)
    }

    func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
        shouldDismiss()
    }

    func presentationControllerWillDismiss(_ presentationController: UIPresentationController) {
        onWillDismiss()
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        onUserDismiss()
    }

    func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
        onDidAttemptToDismiss()
    }
}

private extension BottomSheetDetent {
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

private extension BottomSheetAdaptiveStyle {
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

private struct SheetOptions: Equatable {
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

private final class HeightRelay: ObservableObject {
    var onChange: (CGFloat) -> Void = { _ in }
    @Published var grabberInset: CGFloat = 0
    @Published var bottomInset: CGFloat = 0
}

private struct BottomSheetHeightProbe<Content: View>: View {
    var grabberInset: CGFloat
    var bottomInset: CGFloat
    var content: Content

    var body: some View {
        content
            .padding(.top, grabberInset)
            .padding(.bottom, bottomInset)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct BottomSheetRoot<Content: View>: View {
    var content: Content
    @ObservedObject var relay: HeightRelay

    var body: some View {
        ScrollView {
            content
                .padding(.top, relay.grabberInset)
                .padding(.bottom, relay.bottomInset)
                .fixedSize(horizontal: false, vertical: true)
                .background(heightReader)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// `onPreferenceChange` stops delivering once the sheet resizes inside its callback
    /// (the sheet stalled at a stale height while rows kept growing). `onChange` on the
    /// reader's own size keeps firing every frame.
    private var heightReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    relay.onChange(proxy.size.height)
                }
                .onChange(of: proxy.size.height) { value in
                    relay.onChange(value)
                }
        }
    }
}
