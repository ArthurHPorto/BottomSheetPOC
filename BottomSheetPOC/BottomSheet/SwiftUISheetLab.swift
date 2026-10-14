import SwiftUI
import UIKit

struct SheetLabPresentation<SheetContent: View>: ViewModifier {
    var engine: SheetLabEngine
    @Binding var isPresented: Bool
    @Binding var selectedDetent: BottomSheetDetent?
    var configuration: BottomSheetConfiguration
    var motion: BottomSheetMotion
    @ViewBuilder var content: () -> SheetContent

    @ViewBuilder
    func body(content: Content) -> some View {
        switch engine {
        case .uikit:
            content.bottomSheet(
                isPresented: $isPresented,
                selectedDetent: $selectedDetent,
                configuration: configuration
            ) {
                self.content()
            }
        case .height:
            content.sheet(isPresented: $isPresented) {
                HeightDetentSheet(motion: motion) {
                    self.content()
                }
            }
        case .fitted:
            content.sheet(isPresented: $isPresented) {
                FittedDetentSheet {
                    self.content()
                }
            }
        case .introspect:
            content.sheet(isPresented: $isPresented) {
                IntrospectDetentSheet(motion: motion) {
                    self.content()
                }
            }
        }
    }
}

enum SheetLabEngine: String, CaseIterable, Identifiable {
    case uikit
    case height
    case fitted
    case introspect

    var id: String { rawValue }

    var title: String {
        switch self {
        case .uikit: "UIKit"
        case .height: "Altura"
        case .fitted: "Fitted"
        case .introspect: "Sheet+UIKit"
        }
    }

    static func resolvedFromLaunchArguments() -> SheetLabEngine {
        let arguments = ProcessInfo.processInfo.arguments
        guard
            let index = arguments.firstIndex(of: "-BottomSheetEngine"),
            arguments.indices.contains(arguments.index(after: index))
        else {
            return .uikit
        }
        return SheetLabEngine(rawValue: arguments[arguments.index(after: index)]) ?? .uikit
    }
}

/// SwiftUI `.sheet` whose detent is `.height`, updated with the active motion.
struct HeightDetentSheet<Content: View>: View {
    var motion: BottomSheetMotion
    @ViewBuilder var content: () -> Content
    @State private var measuredHeight: CGFloat = 180

    var body: some View {
        measuredContent
            .presentationDetents([.height(max(measuredHeight, 80)), .large])
            .presentationDragIndicator(.visible)
            .modifier(LabCornerRadius())
            .animation(motion.animation, value: measuredHeight)
    }

    private var measuredContent: some View {
        content()
            .fixedSize(horizontal: false, vertical: true)
            .background(LabHeightReader())
            .onPreferenceChange(LabHeightPreferenceKey.self) { next in
                let resolved = ceil(next)
                guard resolved > 1, abs(resolved - measuredHeight) >= 1 else { return }
                withAnimation(motion.animation) {
                    measuredHeight = resolved
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// iOS 18+ sheet that sizes itself to the fitted content.
struct FittedDetentSheet<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .presentationDragIndicator(.visible)
            .modifier(LabCornerRadius())
            .modifier(LabFittedSizing())
    }
}

/// SwiftUI `.sheet` presents. UIKit then owns the content detent from inside.
struct IntrospectDetentSheet<Content: View>: View {
    var motion: BottomSheetMotion
    @ViewBuilder var content: () -> Content
    @State private var measuredHeight: CGFloat = 1

    var body: some View {
        content()
            .padding(.top, 16)
            .fixedSize(horizontal: false, vertical: true)
            .background(LabHeightReader())
            .onPreferenceChange(LabHeightPreferenceKey.self) { next in
                let resolved = ceil(next)
                guard resolved > 1 else { return }
                measuredHeight = resolved
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background {
                SheetDetentDriver(height: measuredHeight, motion: motion)
                    .frame(width: 0, height: 0)
            }
    }
}

private struct SheetDetentDriver: UIViewRepresentable {
    var height: CGFloat
    var motion: BottomSheetMotion

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.height = height
        context.coordinator.motion = motion
        context.coordinator.attach(from: uiView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UISheetPresentationControllerDelegate {
        var height: CGFloat = 1
        var motion: BottomSheetMotion = .spring
        private var appliedHeight: CGFloat = 0
        private var didInstallDetents = false
        private var animator: UIViewPropertyAnimator?
        private weak var sheet: UISheetPresentationController?

        func attach(from view: UIView) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view else { return }
                guard let sheet = view.enclosingSheetPresentationController() else { return }
                if self.sheet !== sheet {
                    self.sheet = sheet
                    sheet.delegate = self
                    sheet.prefersGrabberVisible = true
                    sheet.preferredCornerRadius = 28
                    self.installDetents(on: sheet, animated: false)
                }
                self.noteHeight(on: sheet)
            }
        }

        private func noteHeight(on sheet: UISheetPresentationController) {
            guard height > 1, abs(height - appliedHeight) >= 1 else { return }
            let canAnimate = appliedHeight > 1
            appliedHeight = height
            guard canAnimate else {
                installDetents(on: sheet, animated: false)
                return
            }
            animator?.stopAnimation(true)
            let animator = UIViewPropertyAnimator(duration: motion.duration, timingParameters: motion.timing)
            self.animator = animator
            animator.addAnimations { [weak self, weak sheet] in
                guard let self, let sheet else { return }
                self.installDetents(on: sheet, animated: true)
            }
            animator.startAnimation()
        }

        private func installDetents(on sheet: UISheetPresentationController, animated: Bool) {
            let apply = {
                if !self.didInstallDetents {
                    let content = UISheetPresentationController.Detent.custom(identifier: .init("content")) { [weak self] context in
                        let resolved = self?.appliedHeight ?? 1
                        return min(max(resolved, 1), context.maximumDetentValue)
                    }
                    sheet.detents = [content, .large()]
                    sheet.selectedDetentIdentifier = .init("content")
                    self.didInstallDetents = true
                } else if animated {
                    sheet.invalidateDetents()
                }
            }
            if animated {
                sheet.animateChanges(apply)
            } else {
                UIView.performWithoutAnimation(apply)
            }
        }

        func sheetPresentationControllerDidChangeSelectedDetentIdentifier(_ sheetPresentationController: UISheetPresentationController) {
            let identifier = sheetPresentationController.selectedDetentIdentifier?.rawValue ?? "nil"
            print("LAB detent \(identifier)")
        }
    }
}

private struct LabHeightPreferenceKey: PreferenceKey {
    nonisolated static var defaultValue: CGFloat { 0 }
    nonisolated static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}

private struct LabHeightReader: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: LabHeightPreferenceKey.self, value: proxy.size.height)
        }
    }
}

private struct LabCornerRadius: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content.presentationCornerRadius(28)
        } else {
            content
        }
    }
}

private struct LabFittedSizing: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.presentationSizing(.fitted)
        } else {
            content
        }
    }
}

private extension UIView {
    func enclosingSheetPresentationController() -> UISheetPresentationController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController {
                var cursor: UIViewController? = controller
                while let candidate = cursor {
                    if let sheet = candidate.sheetPresentationController {
                        return sheet
                    }
                    cursor = candidate.parent
                }
            }
            responder = current.next
        }
        return nil
    }
}
