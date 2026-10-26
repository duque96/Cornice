import Foundation
import Observation

/// What the surface is doing right now.
public enum NotchState: String, Sendable {
    /// Collapsed and click-through: looks exactly like the hardware notch.
    case dormant
    /// The pointer entered the hot zone; waiting out the opening delay.
    case armed
    /// Expanded and interactive.
    case open
}

/// Observable state owned by the controller and read by SwiftUI.
@Observable
@MainActor
public final class NotchSurfaceModel {
    public var state: NotchState = .dormant
    public var notchSize: CGSize
    public var expandedSize: CGSize
    public var notchCornerRadius: CGFloat
    public var mode: ScreenGeometry.Mode

    public init(
        notchSize: CGSize,
        expandedSize: CGSize,
        notchCornerRadius: CGFloat,
        mode: ScreenGeometry.Mode
    ) {
        self.notchSize = notchSize
        self.expandedSize = expandedSize
        self.notchCornerRadius = notchCornerRadius
        self.mode = mode
    }

    public var isOpen: Bool { state == .open }

    /// The size of the silhouette at this instant (animation is SwiftUI's job).
    public var surfaceSize: CGSize { isOpen ? expandedSize : notchSize }
}
