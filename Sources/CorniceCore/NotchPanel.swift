import AppKit
import SwiftUI

/// Borderless, non-activating panel that floats above the menu bar.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    // Clicking the surface must never steal focus from the frontmost app.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that lets clicks through anywhere outside the current silhouette.
final class SurfaceHostingView: NSHostingView<NotchSurfaceView> {
    var surfaceSize: CGSize = .zero

    required init(rootView: NotchSurfaceView) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SurfaceHostingView does not support NSCoding")
    }

    /// The panel never becomes key, so clicks (the settings gear) only work if the
    /// first click is accepted by the view itself.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let originY = isFlipped ? 0 : bounds.height - surfaceSize.height
        let silhouette = CGRect(
            x: (bounds.width - surfaceSize.width) / 2,
            y: originY,
            width: surfaceSize.width,
            height: surfaceSize.height
        )

        guard silhouette.contains(local) else { return nil }
        return super.hitTest(point)
    }
}
