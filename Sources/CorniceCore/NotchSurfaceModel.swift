import Foundation
import Observation
import SwiftUI

/// What the surface is doing right now.
public enum NotchState: String, Sendable {
    /// Collapsed and click-through: looks exactly like the hardware notch.
    case dormant
    /// The pointer entered the hot zone; waiting out the opening delay.
    case armed
    /// Expanded and interactive.
    case open
}

/// Timing for the opening and closing transitions.
///
/// Editable in the options window and persisted by `SettingsStore`.
public struct NotchMotion: Codable, Sendable, Equatable {
    /// Spring response in seconds: higher is slower.
    public var openResponse: Double
    public var openDamping: Double
    public var closeResponse: Double
    public var closeDamping: Double
    /// Content fades in only once the silhouette has grown.
    public var contentDelay: Double
    public var contentDuration: Double

    public init(
        openResponse: Double = 0.30,
        openDamping: Double = 0.90,
        closeResponse: Double = 0.24,
        closeDamping: Double = 0.96,
        contentDelay: Double = 0.24,
        contentDuration: Double = 0.16
    ) {
        self.openResponse = openResponse
        self.openDamping = openDamping
        self.closeResponse = closeResponse
        self.closeDamping = closeDamping
        self.contentDelay = contentDelay
        self.contentDuration = contentDuration
    }

    public var open: Animation {
        .spring(response: openResponse, dampingFraction: openDamping)
    }

    public var close: Animation {
        .spring(response: closeResponse, dampingFraction: closeDamping)
    }

    /// Content fades in only after the silhouette has grown.
    public var contentIn: Animation {
        .easeOut(duration: contentDuration).delay(contentDelay)
    }

    /// On the way out the content must leave immediately, with the silhouette.
    public var contentOut: Animation {
        .easeOut(duration: contentDuration * 0.6)
    }

    /// How long to wait before removing the window from the screen.
    public var settleDelay: Duration {
        .milliseconds(Int((closeResponse * 1.4 + 0.14) * 1000))
    }
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
    public var motion: NotchMotion
    /// Set by the controller: lets the panel draw a settings button.
    @ObservationIgnored public var onOpenSettings: (() -> Void)?
    /// The stage content injected by the app (the widget area).
    @ObservationIgnored public var widgetContent: AnyView?

    public init(
        notchSize: CGSize,
        expandedSize: CGSize,
        notchCornerRadius: CGFloat,
        mode: ScreenGeometry.Mode,
        motion: NotchMotion = NotchMotion()
    ) {
        self.notchSize = notchSize
        self.expandedSize = expandedSize
        self.notchCornerRadius = notchCornerRadius
        self.mode = mode
        self.motion = motion
    }

    public var isOpen: Bool { state == .open }

    /// The size of the silhouette at this instant (animation is SwiftUI's job).
    public var surfaceSize: CGSize { isOpen ? expandedSize : notchSize }
}
