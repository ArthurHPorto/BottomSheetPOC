import SwiftUI
import UIKit

/// The UIKit sheet controller, presented by SwiftUI's `.sheet`.
struct BottomSheetRepresentable<SheetContent: View>: UIViewControllerRepresentable {
    var selectedDetent: Binding<BottomSheetDetent?>?
    var onDetentChange: ((BottomSheetDetent) -> Void)?
    var onDismiss: (() -> Void)?
    var onHeightChange: ((CGFloat) -> Void)?
    var content: () -> SheetContent

    func makeUIViewController(context: Context) -> BottomSheetContainerController<SheetContent> {
        let controller = BottomSheetContainerController(content: content())
        context.coordinator.onDetentChange = onDetentChange
        context.coordinator.onDismiss = onDismiss
        context.coordinator.onHeightChange = onHeightChange
        context.coordinator.attach(controller, selectedDetent: selectedDetent)
        return controller
    }

    func updateUIViewController(_ controller: BottomSheetContainerController<SheetContent>, context: Context) {
        context.coordinator.onDetentChange = onDetentChange
        context.coordinator.onDismiss = onDismiss
        context.coordinator.onHeightChange = onHeightChange
        context.coordinator.attach(controller, selectedDetent: selectedDetent)
        let width = controller.view.bounds.width > 1
            ? controller.view.bounds.width
            : UIScreen.main.bounds.width
        controller.update(
            content: content(),
            selection: selectedDetent?.wrappedValue,
            sourceView: nil,
            width: width
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var onDetentChange: ((BottomSheetDetent) -> Void)?
        var onDismiss: (() -> Void)?
        var onHeightChange: ((CGFloat) -> Void)?

        func attach(
            _ controller: BottomSheetContainerController<SheetContent>,
            selectedDetent: Binding<BottomSheetDetent?>?
        ) {
            controller.onSelectedDetentChanged = { detent in
                selectedDetent?.wrappedValue = detent
            }
            controller.onDetentChange = { [weak self] detent in
                self?.onDetentChange?(detent)
            }
            controller.onDismiss = { [weak self] in
                self?.onDismiss?()
            }
            controller.onHeightChange = { [weak self] height in
                self?.onHeightChange?(height)
            }
        }
    }
}

private struct BottomSheetModifier<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    var selectedDetent: Binding<BottomSheetDetent?>?
    var onDismiss: (() -> Void)?
    var onDetentChange: ((BottomSheetDetent) -> Void)?
    var onHeightChange: ((CGFloat) -> Void)?
    var content: () -> SheetContent

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            BottomSheetRepresentable(
                selectedDetent: selectedDetent,
                onDetentChange: onDetentChange,
                onDismiss: onDismiss,
                onHeightChange: onHeightChange,
                content: self.content
            )
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

private struct BottomSheetItemModifier<Item: Identifiable, SheetContent: View>: ViewModifier {
    @Binding var item: Item?
    var selectedDetent: Binding<BottomSheetDetent?>?
    var onDismiss: (() -> Void)?
    var onDetentChange: ((BottomSheetDetent) -> Void)?
    var onHeightChange: ((CGFloat) -> Void)?
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
                onDismiss: onDismiss,
                onDetentChange: onDetentChange,
                onHeightChange: onHeightChange
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
    /// Presents the UIKit bottom sheet. SwiftUI only presents it and supplies the content.
    func bottomSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        selectedDetent: Binding<BottomSheetDetent?>? = nil,
        onDismiss: (() -> Void)? = nil,
        onDetentChange: ((BottomSheetDetent) -> Void)? = nil,
        onHeightChange: ((CGFloat) -> Void)? = nil,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        modifier(
            BottomSheetModifier(
                isPresented: isPresented,
                selectedDetent: selectedDetent,
                onDismiss: onDismiss,
                onDetentChange: onDetentChange,
                onHeightChange: onHeightChange,
                content: content
            )
        )
    }

    /// Presents the UIKit bottom sheet for a non-nil identifiable item.
    func bottomSheet<Item: Identifiable, SheetContent: View>(
        item: Binding<Item?>,
        selectedDetent: Binding<BottomSheetDetent?>? = nil,
        onDismiss: (() -> Void)? = nil,
        onDetentChange: ((BottomSheetDetent) -> Void)? = nil,
        onHeightChange: ((CGFloat) -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> SheetContent
    ) -> some View {
        modifier(
            BottomSheetItemModifier(
                item: item,
                selectedDetent: selectedDetent,
                onDismiss: onDismiss,
                onDetentChange: onDetentChange,
                onHeightChange: onHeightChange,
                content: content
            )
        )
    }
}
