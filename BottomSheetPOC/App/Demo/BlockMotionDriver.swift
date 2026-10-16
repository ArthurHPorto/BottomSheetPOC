import SwiftUI
import UIKit

/// Plays `BottomSheetMotion` by writing progress every frame, so the sheet can follow it.
final class BlockMotionDriver {
    private var link: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private var from: CGFloat = 0
    private var to: CGFloat = 1
    private var motion: BottomSheetMotion = .spring
    var onChange: ((CGFloat) -> Void)?
    var onFinish: (() -> Void)?
    var isRunning: Bool { link != nil }

    func start(from: CGFloat, to: CGFloat, motion: BottomSheetMotion) {
        self.from = from
        self.to = to
        self.motion = motion
        startTime = CACurrentMediaTime()
        link?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func step() {
        let elapsed = CACurrentMediaTime() - startTime
        let unit = motion.unitProgress(elapsed: elapsed)
        onChange?(from + (to - from) * unit)
        guard elapsed >= motion.settlesAfter else { return }
        onChange?(to)
        link?.invalidate()
        link = nil
        let finish = onFinish
        onChange = nil
        onFinish = nil
        finish?()
    }

    deinit {
        link?.invalidate()
    }
}

