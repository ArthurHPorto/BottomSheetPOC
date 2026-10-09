import SwiftUI
import UIKit

struct BottomSheetPresenter<SheetContent: View>: UIViewRepresentable {
    @Binding var isPresented: Bool
    var selectedDetent: Binding<BottomSheetDetent?>?
    var configuration: BottomSheetConfiguration
    var onDismiss: (() -> Void)?
    var content: () -> SheetContent

    func makeUIView(context: Context) -> BottomSheetAnchorView {
        let view = BottomSheetAnchorView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.onWindowChange = { [weak coordinator = context.coordinator] in
            coordinator?.reconcile()
        }
        return view
    }

    func updateUIView(_ uiView: BottomSheetAnchorView, context: Context) {
        context.coordinator.bind(
            isPresented: $isPresented,
            selectedDetent: selectedDetent,
            configuration: configuration,
            onDismiss: onDismiss,
            content: content,
            anchor: uiView
        )
        uiView.onWindowChange = { [weak coordinator = context.coordinator] in
            coordinator?.reconcile()
        }
        if context.coordinator.container != nil {
            context.coordinator.pushContent()
        }
        context.coordinator.reconcile()
    }

    static func dismantleUIView(_ uiView: BottomSheetAnchorView, coordinator: Coordinator) {
        uiView.onWindowChange = nil
        coordinator.shutdown()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var isPresented = Binding.constant(false)
        var selectedDetent: Binding<BottomSheetDetent?>?
        var configuration = BottomSheetConfiguration()
        var onDismiss: (() -> Void)?
        var content: () -> SheetContent = { fatalError("Bottom sheet content was not set") }
        weak var anchor: UIView?
        var container: BottomSheetContainerController<SheetContent>?
        private var phase: Phase = .idle
        private var didRetryWindow = false

        enum Phase {
            case idle
            case presenting
            case presented
            case dismissing
        }

        func bind(
            isPresented: Binding<Bool>,
            selectedDetent: Binding<BottomSheetDetent?>?,
            configuration: BottomSheetConfiguration,
            onDismiss: (() -> Void)?,
            content: @escaping () -> SheetContent,
            anchor: UIView
        ) {
            self.isPresented = isPresented
            self.selectedDetent = selectedDetent
            self.configuration = configuration
            self.onDismiss = onDismiss
            self.content = content
            self.anchor = anchor
        }

        func reconcile() {
            guard anchor?.window != nil else {
                guard isPresented.wrappedValue, !didRetryWindow else { return }
                didRetryWindow = true
                DispatchQueue.main.async { [weak self] in
                    self?.reconcile()
                }
                return
            }
            didRetryWindow = false
            if isPresented.wrappedValue {
                if container == nil {
                    guard phase != .presenting else { return }
                    beginPresenting()
                } else if phase != .dismissing {
                    pushContent()
                }
            } else if container != nil, phase != .dismissing {
                phase = .dismissing
                beginDismissing()
            }
        }

        func pushContent() {
            guard let container, let anchor else { return }
            container.update(
                content: content(),
                configuration: configuration,
                selection: selectedDetent?.wrappedValue,
                sourceView: sourceView(for: anchor),
                width: availableWidth(from: anchor)
            )
            wire(container)
        }

        func shutdown() {
            container?.dismiss(animated: false)
            container = nil
            phase = .idle
        }

        private func beginPresenting() {
            guard isPresented.wrappedValue else {
                phase = .idle
                return
            }
            guard let anchor, let presenter = anchor.nearestViewController(), presenter.view.window != nil else {
                phase = .idle
                return
            }
            if let presented = presenter.presentedViewController, !presented.isBeingDismissed {
                phase = .idle
                return
            }
            phase = .presenting

            let container = BottomSheetContainerController(content: content())
            self.container = container
            wire(container)
            container.update(
                content: content(),
                configuration: configuration,
                selection: selectedDetent?.wrappedValue,
                sourceView: sourceView(for: anchor),
                width: availableWidth(from: anchor)
            )
            presenter.present(container, animated: true) { [weak self] in
                guard let self else { return }
                if self.isPresented.wrappedValue {
                    self.phase = .presented
                    self.pushContent()
                } else {
                    self.phase = .dismissing
                    self.beginDismissing()
                }
            }
        }

        private func beginDismissing() {
            guard let container, container.presentingViewController != nil, !container.isBeingDismissed else {
                finishDismiss(fromUser: false)
                return
            }
            container.dismiss(animated: true) { [weak self] in
                self?.finishDismiss(fromUser: false)
            }
        }

        private func finishDismiss(fromUser: Bool) {
            guard phase != .idle else { return }
            phase = .idle
            container = nil
            if fromUser {
                isPresented.wrappedValue = false
            }
            onDismiss?()
        }

        private func wire(_ container: BottomSheetContainerController<SheetContent>) {
            container.shouldDismiss = { [weak self] in
                self?.configuration.shouldDismiss?() ?? true
            }
            container.onWillDismiss = { [weak self] in
                self?.configuration.onWillDismiss?()
            }
            container.onDidAttemptToDismiss = { [weak self] in
                self?.configuration.onDidAttemptToDismiss?()
            }
            container.onAdaptivePresentation = { [weak self] style in
                self?.configuration.onAdaptivePresentation?(style)
            }
            container.onSelectedDetentChanged = { [weak self] detent in
                self?.selectedDetent?.wrappedValue = detent
                self?.configuration.onDetentChange?(detent)
            }
            container.onUserDismiss = { [weak self] in
                self?.finishDismiss(fromUser: true)
            }
        }

        private func sourceView(for anchor: UIView) -> UIView? {
            guard configuration.centersOnSourceView else { return nil }
            return anchor.nearestViewController()?.view
        }

        private func availableWidth(from anchor: UIView) -> CGFloat {
            if let width = anchor.window?.bounds.width, width > 1 {
                return width
            }
            if let width = anchor.window?.windowScene?.screen.bounds.width, width > 1 {
                return width
            }
            return UIScreen.main.bounds.width
        }
    }
}

final class BottomSheetAnchorView: UIView {
    var onWindowChange: (() -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChange?()
    }
}

private extension UIResponder {
    func nearestViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController {
                return controller
            }
            responder = current.next
        }
        return nil
    }
}

private struct BottomSheetModifier<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    var selectedDetent: Binding<BottomSheetDetent?>?
    var configuration: BottomSheetConfiguration
    var onDismiss: (() -> Void)?
    var content: () -> SheetContent

    func body(content: Content) -> some View {
        content.background {
            BottomSheetPresenter(
                isPresented: $isPresented,
                selectedDetent: selectedDetent,
                configuration: configuration,
                onDismiss: onDismiss,
                content: self.content
            )
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

private struct BottomSheetItemModifier<Item: Identifiable, SheetContent: View>: ViewModifier {
    @Binding var item: Item?
    var selectedDetent: Binding<BottomSheetDetent?>?
    var configuration: BottomSheetConfiguration
    var onDismiss: (() -> Void)?
    var content: (Item) -> SheetContent
    @State private var cachedItem: Item?

    func body(content: Content) -> some View {
        content
            .bottomSheet(
                isPresented: Binding(
                    get: { item != nil },
                    set: { isPresented in
                        if !isPresented {
                            item = nil
                        }
                    }
                ),
                selectedDetent: selectedDetent,
                configuration: configuration,
                onDismiss: onDismiss
            ) {
                if let value = item ?? cachedItem {
                    self.content(value)
                }
            }
            .onChange(of: item?.id) { _ in
                if let item {
                    cachedItem = item
                }
            }
    }
}

extension View {
    /// Presents a UIKit bottom sheet. SwiftUI supplies the content and configuration only.
    func bottomSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        selectedDetent: Binding<BottomSheetDetent?>? = nil,
        configuration: BottomSheetConfiguration = BottomSheetConfiguration(),
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        modifier(
            BottomSheetModifier(
                isPresented: isPresented,
                selectedDetent: selectedDetent,
                configuration: configuration,
                onDismiss: onDismiss,
                content: content
            )
        )
    }

    /// Presents a UIKit bottom sheet for a non-nil identifiable item.
    func bottomSheet<Item: Identifiable, SheetContent: View>(
        item: Binding<Item?>,
        selectedDetent: Binding<BottomSheetDetent?>? = nil,
        configuration: BottomSheetConfiguration = BottomSheetConfiguration(),
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> SheetContent
    ) -> some View {
        modifier(
            BottomSheetItemModifier(
                item: item,
                selectedDetent: selectedDetent,
                configuration: configuration,
                onDismiss: onDismiss,
                content: content
            )
        )
    }
}
