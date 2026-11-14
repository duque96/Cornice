import Foundation

/// Turns raw scroll-wheel deltas into page steps.
///
/// Trackpads send phased, precise deltas and keep using the drag model. Mice send
/// line-based deltas with no phase, often several events per notch, so they need
/// accumulation plus a cooldown: otherwise a single notch either does nothing
/// (each event is too small to commit a drag) or fires one page per event.
public struct WheelPagingState {
    public static let threshold: CGFloat = 20
    public static let cooldown: TimeInterval = 0.30
    /// Mice that idle for longer than this start a new gesture.
    public static let idleReset: TimeInterval = 0.40
    /// A line-based notch is ~1–3 lines; roughly 10 points per line.
    public static let lineToPoints: CGFloat = 10

    private var accumulated: CGFloat = 0
    private var lastEvent: TimeInterval = 0
    private var cooldownUntil: TimeInterval = 0

    public init() {}

    /// +1 for the next page, -1 for the previous one, nil while the gesture is
    /// too short or still cooling down.
    public mutating func step(delta: CGFloat, precise: Bool, at time: TimeInterval) -> Int? {
        guard time >= cooldownUntil else { return nil }

        if time - lastEvent > Self.idleReset {
            accumulated = 0
        }
        lastEvent = time
        accumulated += precise ? delta : delta * Self.lineToPoints

        guard abs(accumulated) >= Self.threshold else { return nil }

        let step = accumulated < 0 ? 1 : -1
        accumulated = 0
        cooldownUntil = time + Self.cooldown
        return step
    }
}
