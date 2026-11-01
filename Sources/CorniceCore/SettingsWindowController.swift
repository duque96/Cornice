import AppKit
import SwiftUI

/// Hosts the options window. Sections are rebuilt on every open so newly enabled
/// widgets get their page without restarting the app.
@MainActor
public final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let store: SettingsStore
    private let makeSections: () -> [SettingsSection]
    private let onPreview: (Bool) -> Void
    private var window: NSWindow?

    public init(
        store: SettingsStore,
        sections: @escaping () -> [SettingsSection],
        onPreview: @escaping (Bool) -> Void
    ) {
        self.store = store
        self.makeSections = sections
        self.onPreview = onPreview
        super.init()
    }

    private var title: String {
        Translator(store.settings.language)("Cornice Settings", "Ajustes de Cornice")
    }

    private func content() -> NSView {
        NSHostingView(
            rootView: SettingsShellView(
                sections: makeSections(),
                store: store,
                onPreview: onPreview
            )
        )
    }

    /// Rebuilds an open window (used when the language changes).
    public func refresh() {
        guard let window, window.isVisible else { return }
        window.title = title
        window.contentView = content()
    }

    public func show() {
        let content = content()

        if let window {
            window.contentView = content
        } else {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = title
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = content
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
