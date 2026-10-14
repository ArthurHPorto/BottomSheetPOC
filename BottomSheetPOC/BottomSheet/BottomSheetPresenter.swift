import SwiftUI
import UIKit

/// The UIKit sheet controller, presented by SwiftUI's `.sheet`.
struct BottomSheetRepresentable<SheetContent: View>: UIViewControllerRepresentable {
    var selectedDetent: Binding<BottomSheetDetent?>?
    var configuration: BottomSheetConfiguration
    var content: () -> SheetContent

    func makeUIViewController(context: Context) -> BottomSheetContainerController<SheetContent> {
        let controller = BottomSheetContainerController(content: content())
        context.coordinator.attach(controller, selectedDetent: selectedDetent, configuration: configuration)
        return controller
    }

    func updateUIViewController(_ controller: BottomSheetContainerController<SheetContent>, context: Context) {
        context.coordinator.attach(controller, selectedDetent: selectedDetent, configuration: configuration)
        let width = controller.view.bounds.width > 1
            ? controller.view.bounds.width
            : UIScreen.main.bounds.width
        controller.update(
            content: content(),
            configuration: configuration,
            selection: selectedDetent?.wrappedValue,
            sourceView: nil,
            width: width
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        func attach(
            _ controller: BottomSheetContainerController<SheetContent>,
            selectedDetent: Binding<BottomSheetDetent?>?,
            configuration: BottomSheetConfiguration
        ) {
            controller.shouldDismiss = { configuration.shouldDismiss?() ?? true }
            controller.onWillDismiss = { configuration.onWillDismiss?() }
            controller.onDidAttemptToDismiss = { configuration.onDidAttemptToDismiss?() }
            controller.onAdaptivePresentation = { configuration.onAdaptivePresentation?($0) }
            controller.onSelectedDetentChanged = { detent in
                selectedDetent?.wrappedValue = detent
                configuration.onDetentChange?(detent)
            }
        }
    }
}

private struct BottomSheetModifier<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    var selectedDetent: Binding<BottomSheetDetent?>?
    var configuration: BottomSheetConfiguration
    var onDismiss: (() -> Void)?
    var content: () -> SheetContent

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented, onDismiss: onDismiss) {
            BottomSheetRepresentable(
                selectedDetent: selectedDetent,
                configuration: configuration,
                content: self.content
            )
            .ignoresSafeArea(edges: .bottom)
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
    /// Presents the UIKit bottom sheet. SwiftUI only presents it and supplies the content.
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

    /// Presents the UIKit bottom sheet for a non-nil identifiable item.
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
