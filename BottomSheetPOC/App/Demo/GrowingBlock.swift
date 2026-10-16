import SwiftUI
import UIKit

/// Grows and fades a block in layout, so the next rows are pushed instead of covered.
///
/// The height is stepped on the display link. SwiftUI's own insertion animation was
/// being cancelled by the sheet update, and it also drew the new card on top of the
/// rows that had not moved yet.
struct GrowingBlock<Content: View>: View {
    var shown: Bool
    var startsCollapsed: Bool
    var motion: BottomSheetMotion
    /// Lets the owner drop `startsCollapsed`, so a reopened sheet does not replay the entrance.
    var onSettled: () -> Void
    var onCollapsed: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var natural: CGFloat = 0
    @State private var displayed: CGFloat
    @State private var didStartIntro = false
    @State private var collapsing = false
    @State private var didReportCollapse = false
    @State private var driver = BlockMotionDriver()

    init(
        shown: Bool,
        startsCollapsed: Bool,
        motion: BottomSheetMotion,
        onSettled: @escaping () -> Void,
        onCollapsed: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.shown = shown
        self.startsCollapsed = startsCollapsed
        self.motion = motion
        self.onSettled = onSettled
        self.onCollapsed = onCollapsed
        self.content = content
        _displayed = State(initialValue: 0)
    }

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .top)
            .frame(height: layoutHeight, alignment: .top)
            .clipped()
            .opacity(reveal)
            .background {
                BlockHeightMeasurer(content: AnyView(content()), onHeight: noteHeight)
            }
            .onChange(of: shown, perform: noteShown)
    }

    /// `nil` keeps the first layout of a block that is already visible.
    private var layoutHeight: CGFloat? {
        if !startsCollapsed, displayed <= 1, natural <= 1 {
            return nil
        }
        return max(displayed, 0)
    }

    private var reveal: Double {
        guard natural > 1 else { return displayed > 1 ? 1 : 0 }
        return min(max(Double(displayed / natural), 0), 1)
    }

    private func noteHeight(_ value: CGFloat) {
        guard value > 1 else { return }
        let changed = abs(value - natural) > 0.5
        natural = value
        guard !collapsing else { return }
        if startsCollapsed, !didStartIntro {
            didStartIntro = true
            start(from: 0, to: value, removing: false)
            return
        }
        guard changed || abs(displayed - value) > 0.5 else { return }
        if driver.isRunning {
            start(from: displayed, to: value, removing: false)
        } else {
            displayed = value
        }
    }

    private func noteShown(_ isShown: Bool) {
        if isShown {
            collapsing = false
            didReportCollapse = false
            start(from: displayed, to: max(natural, displayed), removing: false)
        } else {
            collapsing = true
            start(from: displayed, to: 0, removing: true)
        }
    }

    private func start(from: CGFloat, to: CGFloat, removing: Bool) {
        driver.onChange = { value in
            displayed = value
        }
        driver.onFinish = {
            if removing {
                reportCollapsed()
            } else if startsCollapsed {
                onSettled()
            }
        }
        driver.start(from: from, to: to, motion: motion)
    }

    private func reportCollapsed() {
        guard !didReportCollapse else { return }
        didReportCollapse = true
        onCollapsed()
    }
}


/// Measures the block without adding that height to the sheet.
struct BlockHeightMeasurer: UIViewRepresentable {
    var content: AnyView
    var onHeight: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MeasureHost {
        let host = MeasureHost()
        host.onHeight = onHeight
        host.setContent(content)
        return host
    }

    func updateUIView(_ uiView: MeasureHost, context: Context) {
        uiView.onHeight = onHeight
        uiView.setContent(content)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MeasureHost, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: 0)
    }

    final class Coordinator {}
}

