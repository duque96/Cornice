import CoreGraphics

/// The hover state machine, with no timers and no AppKit.
///
/// The controller owns the clock; this type only decides what should happen next.
/// Keeping it pure is what makes the interaction testable.
public struct NotchInteractionMachine: Sendable {
    public enum Command: Equatable, Sendable {
        case none
        /// Start the opening timer.
        case scheduleOpen
        /// The pointer left before opening: drop the timer.
        case cancelScheduled
        /// Start the closing timer.
        case scheduleClose
        /// The opening timer fired.
        case open
        /// The closing timer fired.
        case collapse
    }

    public private(set) var state: NotchState
    private var closeScheduled = false

    public init(state: NotchState = .dormant) {
        self.state = state
        self.closeScheduled = state == .open
    }

    public mutating func pointerMoved(at point: CGPoint, notch: CGRect, panel: CGRect) -> Command {
        let hot = NotchGeometryMath.hotZone(notchRect: notch)
        let openZone = NotchGeometryMath.openZone(expandedRect: panel)

        switch state {
        case .dormant:
            guard hot.contains(point) else { return .none }
            state = .armed
            return .scheduleOpen

        case .armed:
            guard !hot.contains(point) else { return .none }
            state = .dormant
            return .cancelScheduled

        case .open:
            if openZone.contains(point) {
                closeScheduled = false
                return .cancelScheduled
            }
            guard !closeScheduled else { return .none }
            closeScheduled = true
            return .scheduleClose
        }
    }

    public mutating func openDeadlineReached() -> Command {
        guard state == .armed else { return .none }
        state = .open
        closeScheduled = false
        return .open
    }

    public mutating func closeDeadlineReached() -> Command {
        guard state == .open, closeScheduled else { return .none }
        state = .dormant
        closeScheduled = false
        return .collapse
    }

    /// Used by the debug affordance and by `stop()`.
    public mutating func reset(to newState: NotchState) {
        state = newState
        closeScheduled = newState == .open
    }
}
