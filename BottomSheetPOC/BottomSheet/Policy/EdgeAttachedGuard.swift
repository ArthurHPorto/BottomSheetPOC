import Foundation

/// Learns the one detent value that makes a floating sheet flash into the
/// edge-attached shape, and remembers it so the sheet can skip that value.
struct EdgeAttachedGuard {
    private(set) var hasSeenFloatingSheet = false
    private(set) var avoidedDetentValues = Set<CGFloat>()

    /// The detent value to skip on this layout, when the sheet has just attached
    /// through a threshold it already passed while floating.
    mutating func valueToAvoid(
        hasAppeared: Bool,
        isBeingPresented: Bool,
        isBeingDismissed: Bool,
        isShowingContentDetent: Bool,
        bottom: CGFloat,
        windowHeight: CGFloat,
        lastDetentValue: CGFloat,
        lastMaximumDetentValue: CGFloat
    ) -> CGFloat? {
        guard hasAppeared, !isBeingPresented, !isBeingDismissed, isShowingContentDetent else { return nil }
        if bottom < windowHeight - 0.5 {
            hasSeenFloatingSheet = true
            return nil
        }
        guard hasSeenFloatingSheet, abs(bottom - windowHeight) < 0.5 else { return nil }
        guard lastDetentValue > 1, lastDetentValue < lastMaximumDetentValue - 0.5 else { return nil }
        guard avoidedDetentValues.insert(lastDetentValue).inserted else { return nil }
        return lastDetentValue
    }
}
