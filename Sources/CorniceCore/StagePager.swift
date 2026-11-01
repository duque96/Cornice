import Foundation
import Observation

/// Which page of the stage is visible.
@Observable
@MainActor
public final class StagePager {
    public private(set) var pageCount: Int = 1
    public var index: Int = 0

    public init() {}

    public func setPageCount(_ count: Int) {
        let clamped = max(1, count)
        guard clamped != pageCount else { return }

        pageCount = clamped
        index = min(index, clamped - 1)
    }

    public func advance(_ delta: Int) {
        index = min(max(0, index + delta), max(0, pageCount - 1))
    }
}

/// Turns a stream of trackpad deltas into page changes: one change per gesture,
/// after enough travel and with a cooldown so momentum does not skip pages.
public struct PagerGestureAccumulator: Sendable {
    public var threshold: CGFloat
    public var cooldown: TimeInterval

    private var accumulated: CGFloat = 0
    private var lastChange: Date = .distantPast

    public init(threshold: CGFloat = 30, cooldown: TimeInterval = 0.25) {
        self.threshold = threshold
        self.cooldown = cooldown
    }

    /// Returns +1 for the next page, -1 for the previous one, or nil.
    public mutating func feed(deltaX: CGFloat, now: Date) -> Int? {
        accumulated += deltaX

        guard abs(accumulated) >= threshold,
              now.timeIntervalSince(lastChange) >= cooldown
        else { return nil }

        let direction = accumulated > 0 ? 1 : -1
        accumulated = 0
        lastChange = now
        return direction
    }

    public mutating func reset() {
        accumulated = 0
    }
}
