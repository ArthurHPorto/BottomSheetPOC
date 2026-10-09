import SwiftUI
import UIKit

/// Presents SwiftUI content with `UISheetPresentationController`.
///
/// The content detent reads `measuredContentHeight`. When SwiftUI grows, that
/// value changes and `invalidateDetents()` runs inside `animateChanges(_:)`,
/// which is the iOS 16 animation path for a custom detent.
final class BottomSheetContainerController<Content: View>: UIViewController, UISheetPresentationControllerDelegate {
    private let heightRelay = HeightRelay()
    private let hostingController: UIHostingController<BottomSheetRoot<Content>>

    private var configuration = BottomSheetConfiguration()
    private var sourceView: UIView?
    private var appliedOptions: SheetOptions?
    private var lastAppliedSelection: BottomSheetDetent?
    private var measuredContentHeight: CGFloat = 0
    private var refreshScheduled = false
    private var hasAppeared = false

    var shouldDismiss: () -> Bool = { true }
    var onWillDismiss: () -> Void = {}
    var onDidAttemptToDismiss: () -> Void = {}
    var onSelectedDetentChanged: (BottomSheetDetent) -> Void = { _ in }
    var onAdaptivePresentation: (BottomSheetAdaptiveStyle) -> Void = { _ in }
    var onUserDismiss: () -> Void = {}

    init(content: Content) {
        hostingController = UIHostingController(
            rootView: BottomSheetRoot(grabberInset: 0, content: content, relay: heightRelay)
        )
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        hostingController.sizingOptions = [.intrinsicContentSize, .preferredContentSize]
        if #available(iOS 16.4, *) {
            hostingController.safeAreaRegions = []
        }
        hostingController.view.backgroundColor = .clear
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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hasAppeared = true
        if measuredContentHeight < 2 {
            let estimated = estimateHeight(width: currentWidth)
            if estimated > 1 {
                noteContentHeight(estimated)
            }
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        view.backgroundColor = UIColor(configuration.backgroundColor)
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
        hostingController.rootView = BottomSheetRoot(
            grabberInset: effectiveGrabberInset,
            content: content,
            relay: heightRelay
        )
        view.backgroundColor = UIColor(configuration.backgroundColor)
        isModalInPresentation = configuration.isModalInPresentation

        if measuredContentHeight < 2 {
            let estimated = estimateHeight(width: width, content: content)
            if estimated > 1 {
                measuredContentHeight = estimated
            }
        }

        let options = SheetOptions(configuration)
        if options != appliedOptions {
            appliedOptions = options
            applyChrome(animated: hasAppeared && presentingViewController != nil)
        }
        applySelection(selection)
        publishPreferredContentSize(width: width)
    }

    func noteContentHeight(_ height: CGFloat) {
        let next = ceil(height)
        guard next > 1, abs(next - measuredContentHeight) > 0.5 else { return }
        measuredContentHeight = next
        publishPreferredContentSize(width: currentWidth)
        scheduleDetentRefresh()
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

    private func scheduleDetentRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshScheduled = false
            self.refreshDetents(animated: self.hasAppeared && self.presentingViewController != nil && !self.isBeingPresented && !self.isBeingDismissed)
        }
    }

    private func refreshDetents(animated: Bool) {
        guard sheetPresentationController != nil else { return }
        performChanges(animated: animated) {
            self.installDetents(preservingSelection: true)
        }
    }

    private func applyChrome(animated: Bool) {
        guard let sheet = sheetPresentationController else { return }
        performChanges(animated: animated) {
            sheet.prefersGrabberVisible = configuration.prefersGrabberVisible
            sheet.prefersScrollingExpandsWhenScrolledToEdge = configuration.prefersScrollingExpandsWhenScrolledToEdge
            sheet.prefersEdgeAttachedInCompactHeight = configuration.prefersEdgeAttachedInCompactHeight
            sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = configuration.widthFollowsPreferredContentSizeWhenEdgeAttached
            sheet.preferredCornerRadius = configuration.preferredCornerRadius
            sheet.sourceView = configuration.centersOnSourceView ? sourceView : nil
            if #available(iOS 17.0, *) {
                sheet.prefersPageSizing = configuration.prefersPageSizing
            }
            if #available(iOS 27.0, *) {
                sheet.preferredPlacement = configuration.preferredPlacement.uiKitPlacement
            }
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
        guard let sheet = sheetPresentationController else { return }
        performChanges(animated: hasAppeared && presentingViewController != nil && !isBeingPresented) {
            sheet.selectedDetentIdentifier = selection?.uiKitIdentifier
        }
    }

    private func installDetents(preservingSelection: Bool) {
        guard let sheet = sheetPresentationController else { return }
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
        guard let sheet = sheetPresentationController else {
            changes()
            return
        }
        if animated {
            sheet.animateChanges(changes)
        } else {
            changes()
        }
    }

    private func publishPreferredContentSize(width: CGFloat) {
        guard measuredContentHeight > 1, width > 1 else { return }
        let resolvedWidth = configuration.preferredContentWidth ?? width
        let size = CGSize(width: resolvedWidth, height: measuredContentHeight)
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
            return styled(uiKitDetent(for: detent))
        }
        return detents.isEmpty ? [styled(.large())] : detents
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
                let height = self?.measuredContentHeight ?? 1
                guard height > 1 else { return 1 }
                return min(height, context.maximumDetentValue)
            }
        }
    }

    private func styled(_ detent: UISheetPresentationController.Detent) -> UISheetPresentationController.Detent {
        if #available(iOS 26.1, *), let material = configuration.detentMaterial {
            detent.backgroundEffect = material.makeEffect()
        }
        return detent
    }

    private func estimateHeight(width: CGFloat, content: Content? = nil) -> CGFloat {
        let resolvedWidth = width > 1 ? width : currentWidth
        let root = BottomSheetRoot(
            grabberInset: effectiveGrabberInset,
            content: content ?? hostingController.rootView.content,
            relay: HeightRelay()
        )
        let probe = UIHostingController(rootView: root)
        probe.sizingOptions = [.intrinsicContentSize, .preferredContentSize]
        if #available(iOS 16.4, *) {
            probe.safeAreaRegions = []
        }
        probe.view.bounds = CGRect(x: 0, y: 0, width: resolvedWidth, height: 1)
        probe.view.setNeedsLayout()
        probe.view.layoutIfNeeded()

        let compressed = probe.sizeThatFits(in: CGSize(width: resolvedWidth, height: 0))
        let proposed = probe.sizeThatFits(in: CGSize(width: resolvedWidth, height: 8_000))
        let intrinsic = probe.view.intrinsicContentSize.height
        let preferred = probe.preferredContentSize.height
        let candidates = [intrinsic, preferred, compressed.height, proposed.height]
        guard let best = candidates.first(where: { $0.isFinite && $0 > 1 && $0 < 7_500 }) else { return 0 }
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

private extension BottomSheetPlacement {
    @available(iOS 27.0, *)
    var uiKitPlacement: UISheetPresentationController.Placement {
        switch self {
        case .automatic:
            return .automatic
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
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

private extension BottomSheetDetentMaterial {
    func makeEffect() -> UIVisualEffect {
        let style: UIBlurEffect.Style
        switch self {
        case .systemChrome:
            style = .systemChromeMaterial
        case .systemMaterial:
            style = .systemMaterial
        case .systemThinMaterial:
            style = .systemThinMaterial
        case .systemUltraThinMaterial:
            style = .systemUltraThinMaterial
        case .systemThickMaterial:
            style = .systemThickMaterial
        }
        return UIBlurEffect(style: style)
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
    var prefersPageSizing: Bool
    var preferredPlacement: BottomSheetPlacement
    var centersOnSourceView: Bool
    var isModalInPresentation: Bool
    var backgroundDescription: String
    var detentMaterial: BottomSheetDetentMaterial?
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
        prefersPageSizing = configuration.prefersPageSizing
        preferredPlacement = configuration.preferredPlacement
        centersOnSourceView = configuration.centersOnSourceView
        isModalInPresentation = configuration.isModalInPresentation
        backgroundDescription = String(describing: configuration.backgroundColor)
        detentMaterial = configuration.detentMaterial
        grabberContentInset = configuration.grabberContentInset
        adaptiveStyle = configuration.adaptiveStyle
    }
}

private final class HeightRelay {
    var onChange: (CGFloat) -> Void = { _ in }
}

private struct BottomSheetHeightPreferenceKey: PreferenceKey {
    nonisolated static var defaultValue: CGFloat { 0 }

    nonisolated static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}

private struct BottomSheetRoot<Content: View>: View {
    var grabberInset: CGFloat
    var content: Content
    var relay: HeightRelay

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.top, grabberInset)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(heightReader)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onPreferenceChange(BottomSheetHeightPreferenceKey.self) { height in
            relay.onChange(height)
        }
    }

    private var heightReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: BottomSheetHeightPreferenceKey.self, value: proxy.size.height)
        }
    }
}
