import AppKit
import SwiftUI

/// Hosts the options window. One instance, reused.
@MainActor
public final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let store: SettingsStore
    private let onPreview: (Bool) -> Void
    private var window: NSWindow?

    public init(store: SettingsStore, onPreview: @escaping (Bool) -> Void) {
        self.store = store
        self.onPreview = onPreview
        super.init()
    }

    public func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 540, height: 660),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Cornice Settings"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(
                rootView: SettingsView(store: store, onPreview: onPreview)
            )
            window.center()
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    public func windowWillClose(_ notification: Notification) {
        // Never leave the surface pinned open with no window to unpin it.
        onPreview(false)
    }
}
