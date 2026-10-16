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

