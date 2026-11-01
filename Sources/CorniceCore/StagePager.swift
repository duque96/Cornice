import Foundation
import Observation

/// Which page of the stage is visible, plus the interactive drag offset.
@Observable
@MainActor
public final class StagePager {
    public private(set) var pageCount: Int = 1
    public var index: Int = 0

    /// Horizontal offset of the current page in points. Negative means "dragging
    /// towards the next page".
    public private(set) var offset: CGFloat = 0
    /// While true, the neighbouring pages are mounted so they can slide in.
    public private(set) var isDragging = false

    public init() {}

    public func setPageCount(_ count: Int) {
        let clamped = max(1, count)
        guard clamped != pageCount else { return }

        pageCount = clamped
        index = min(index, clamped - 1)
        offset = 0
    }

    // MARK: - Drag

    public func beginDrag() {
        isDragging = true
    }

    public func drag(by delta: CGFloat, limit: CGFloat) {
        guard limit > 0 else { return }

        let proposed = offset + delta
        let atStart = index == 0 && proposed > 0
        let atEnd = index == pageCount - 1 && proposed < 0

        // Rubber-band when there is no page in that direction.
        offset = (atStart || atEnd)
            ? proposed * 0.35
            : min(max(proposed, -limit), limit)
    }

    /// Which way the drag would settle: +1 next, -1 previous, nil to snap back.
    public func pendingStep(limit: CGFloat, fraction: CGFloat = 0.22) -> Int? {
        let threshold = max(40, limit * fraction)
        if offset <= -threshold { return 1 }
        if offset >= threshold { return -1 }
        return nil
    }

    public func commit(step: Int) {
        index = min(max(0, index + step), max(0, pageCount - 1))
        offset = 0
    }

    public func cancelDrag() {
        offset = 0
    }

    public func endInteraction() {
        offset = 0
        isDragging = false
    }

    /// Jumps to a page (used by the dots).
    public func select(_ page: Int) {
        index = min(max(0, page), max(0, pageCount - 1))
        offset = 0
    }
}
