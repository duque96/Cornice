import AppKit

// MARK: - Geometry model

/// Everything the surface needs to know about the screen it lives on.
///
/// Coordinates are Cocoa screen coordinates (origin bottom-left, global across displays).
public struct ScreenGeometry: Sendable, Equatable {
    public enum Mode: String, Sendable {
        /// A real notch reported by the display.
        case hardware
        /// A drawn notch on a display that has none.
        case simulated
        /// Nothing to attach to.
        case none
    }

    public let displayID: CGDirectDisplayID
    public let screenFrame: CGRect
    public let notchRect: CGRect?
    public let cornerRadius: CGFloat
    public let mode: Mode

    public init(
        displayID: CGDirectDisplayID,
        screenFrame: CGRect,
        notchRect: CGRect?,
        cornerRadius: CGFloat,
        mode: Mode
    ) {
        self.displayID = displayID
        self.screenFrame = screenFrame
        self.notchRect = notchRect
        self.cornerRadius = cornerRadius
        self.mode = mode
    }
}

public protocol NotchGeometryProviding: Sendable {
    func geometry(for screen: NSScreen) -> ScreenGeometry
}

// MARK: - Pure math

/// All the arithmetic behind the notch, isolated from AppKit so it can be tested.
public enum NotchGeometryMath {
    public static let defaultNotchSize = CGSize(width: 200, height: 32)
    public static let minimumNotchWidth: CGFloat = 60

    /// The notch rectangle sits flush with the top edge and is bounded by the two
    /// auxiliary menu-bar areas that macOS reports on either side of it.
    public static func hardwareNotchRect(
        screenFrame: CGRect,
        safeAreaTop: CGFloat,
        leftArea: CGRect?,
        rightArea: CGRect?
    ) -> CGRect? {
        guard safeAreaTop > 0,
              let left = leftArea,
              let right = rightArea
        else { return nil }

        let width = right.minX - left.maxX
        guard width >= minimumNotchWidth else { return nil }

        return CGRect(
            x: left.maxX,
            y: screenFrame.maxY - safeAreaTop,
            width: width,
            height: safeAreaTop
        )
    }

    public static func simulatedNotchRect(
        screenFrame: CGRect,
        size: CGSize = defaultNotchSize
    ) -> CGRect {
        CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// A forgiving rectangle around the collapsed notch: aiming at 0pt is not realistic.
    public static func hotZone(notchRect: CGRect, tolerance: CGFloat = 14) -> CGRect {
        CGRect(
            x: notchRect.minX - tolerance,
            y: notchRect.minY - tolerance,
            width: notchRect.width + tolerance * 2,
            height: notchRect.height + tolerance * 2
        )
    }

    /// While open, the surface keeps itself alive as long as the pointer is inside.
    public static func openZone(expandedRect: CGRect, tolerance: CGFloat = 4) -> CGRect {
        CGRect(
            x: expandedRect.minX - tolerance,
            y: expandedRect.minY - tolerance,
            width: expandedRect.width + tolerance * 2,
            height: expandedRect.height + tolerance * 2
        )
    }

    /// The expanded panel hangs from the top edge, centred on the notch.
    public static func expandedRect(
        screenFrame: CGRect,
        notchRect: CGRect,
        size: CGSize
    ) -> CGRect {
        CGRect(
            x: notchRect.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}

// MARK: - Providers

public struct HardwareNotchGeometry: NotchGeometryProviding {
    public init() {}

    public func geometry(for screen: NSScreen) -> ScreenGeometry {
        let notchRect = NotchGeometryMath.hardwareNotchRect(
            screenFrame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            leftArea: screen.auxiliaryTopLeftArea,
            rightArea: screen.auxiliaryTopRightArea
        )

        return ScreenGeometry(
            displayID: screen.corniceDisplayID,
            screenFrame: screen.frame,
            notchRect: notchRect,
            cornerRadius: notchRect.map { min(10, $0.height / 3) } ?? 0,
            mode: notchRect == nil ? .none : .hardware
        )
    }
}

public struct SimulatedNotchGeometry: NotchGeometryProviding {
    public var size: CGSize

    public init(size: CGSize = NotchGeometryMath.defaultNotchSize) {
        self.size = size
    }

    public func geometry(for screen: NSScreen) -> ScreenGeometry {
        let notchRect = NotchGeometryMath.simulatedNotchRect(screenFrame: screen.frame, size: size)

        return ScreenGeometry(
            displayID: screen.corniceDisplayID,
            screenFrame: screen.frame,
            notchRect: notchRect,
            cornerRadius: min(10, size.height / 3),
            mode: .simulated
        )
    }
}

/// Prefers a real notch; falls back to drawing one so the app works on any Mac.
public struct AutomaticNotchGeometry: NotchGeometryProviding {
    private let hardware = HardwareNotchGeometry()
    private let simulated = SimulatedNotchGeometry()

    public init() {}

    public func geometry(for screen: NSScreen) -> ScreenGeometry {
        let hw = hardware.geometry(for: screen)
        return hw.mode == .hardware ? hw : simulated.geometry(for: screen)
    }
}

// MARK: - Display selection

public enum NotchDisplay {
    /// The screen holding the notch, else the main screen.
    public static func target(in screens: [NSScreen], preferred: CGDirectDisplayID? = nil) -> NSScreen? {
        if let preferred, let match = screens.first(where: { $0.corniceDisplayID == preferred }) {
            return match
        }
        if let notched = screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notched
        }
        return NSScreen.main ?? screens.first
    }
}

public extension NSScreen {
    var corniceDisplayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
