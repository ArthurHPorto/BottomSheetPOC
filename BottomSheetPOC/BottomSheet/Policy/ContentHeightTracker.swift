import Foundation

enum HeightAnnouncement {
    /// The height used the first time the sheet renders.
    case rendered
    /// The height the sheet will animate toward, announced before that transition.
    case target
}

/// Decides when a measured height is new, and which height callback it is.
/// Foundation only: it does not touch the sheet.
struct ContentHeightTracker {
    private(set) var measuredContentHeight: CGFloat = 0
    private(set) var heightTarget: CGFloat = 0
    var resolvedDetentHeight: CGFloat = 0

    private var didReportInitialHeight = false
    private var heightTransitionActive = false
    private var lastAnnouncedHeight: CGFloat = 0
    private var lastHeightNoteTime: CFTimeInterval = 0

    /// `shouldApply` means the sheet should adopt `height` now.
    /// `announcement` is nil for intermediate frames of a transition already announced.
    mutating func note(
        height: CGFloat,
        scale: CGFloat,
        canTrack: Bool,
        now: CFTimeInterval
    ) -> (height: CGFloat, announcement: HeightAnnouncement?, shouldApply: Bool)? {
        let pixel: CGFloat = scale > 1 ? 1 / scale : 1
        let next = (height / pixel).rounded() * pixel
        guard next > 1, abs(next - heightTarget) >= pixel else { return nil }
        if now - lastHeightNoteTime > 0.12 {
            heightTransitionActive = false
        }
        lastHeightNoteTime = now
        heightTarget = next
        measuredContentHeight = next

        if !canTrack {
            return (next, announceRendered(next), false)
        }
        if !didReportInitialHeight {
            return (next, announceRendered(next), true)
        }
        if !heightTransitionActive {
            return (next, announceTarget(next), true)
        }
        return (next, nil, true)
    }

    /// After presentation, the height that arrived while the sheet was sliding in.
    mutating func announceCatchUp(_ height: CGFloat) -> HeightAnnouncement? {
        if !didReportInitialHeight {
            return announceRendered(height)
        }
        return announceTarget(height)
    }

    mutating func announceTarget(_ height: CGFloat) -> HeightAnnouncement? {
        guard didReportInitialHeight, height > 1 else { return nil }
        guard abs(height - lastAnnouncedHeight) >= 1 else { return nil }
        guard !heightTransitionActive else { return nil }
        heightTransitionActive = true
        lastAnnouncedHeight = height
        return .target
    }

    /// Stores a height measured before the sheet is on screen, without announcing it.
    mutating func seed(_ height: CGFloat) {
        guard height > 1, measuredContentHeight < 2 else { return }
        measuredContentHeight = height
        heightTarget = height
    }

    mutating func resetPresentation(keepingMeasuredHeight height: CGFloat) {
        heightTarget = height
        didReportInitialHeight = false
        heightTransitionActive = false
        lastAnnouncedHeight = 0
    }

    private mutating func announceRendered(_ height: CGFloat) -> HeightAnnouncement? {
        guard !didReportInitialHeight, height > 1 else { return nil }
        didReportInitialHeight = true
        lastAnnouncedHeight = height
        return .rendered
    }
}
