import AppKit
import SwiftUI
import CorniceCore
import CorniceHost
import ExampleWidgetWidget

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchSurfaceController?
    private var settingsWindow: SettingsWindowController?
    private var widgetHost: WidgetHost?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let forceSimulation = ProcessInfo.processInfo.environment["CORNICE_SIMULATE"] == "1"
        let provider: NotchGeometryProviding = forceSimulation
            ? SimulatedNotchGeometry()
            : AutomaticNotchGeometry()

        let settings = SettingsStore()
        let controller = NotchSurfaceController(settings: settings, geometryProvider: provider)
        controller.start()
        self.controller = controller

        let host = WidgetHost(factories: [ExampleWidgetWidgetFactory.self])
        host.start()
        widgetHost = host

        controller.widgetContent = AnyView(WidgetAreaView(host: host))
        controller.onStateChanged = { [weak host] state in
            host?.setActive(state == .open)
        }

        settings.onChange = { [weak controller] in
            controller?.applySettings()
        }

        controller.onOpenSettings = { [weak self] in
            self?.openSettings()
        }

        settingsWindow = SettingsWindowController(store: settings) { [weak controller] pinned in
            controller?.setPinned(pinned)
        }

        if ProcessInfo.processInfo.environment["CORNICE_START_OPEN"] == "1" {
            controller.openImmediately()
        }

        installStatusItem()

        if ProcessInfo.processInfo.environment["CORNICE_START_SETTINGS"] == "1" {
            openSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = item.button {
            if let image = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: "Cornice") {
                button.image = image
            } else {
                button.title = "C"
            }
        }

        let menu = NSMenu()

        let toggle = NSMenuItem(title: "Toggle notch", action: #selector(toggleSurface), keyEquivalent: "t")
        toggle.target = self
        menu.addItem(toggle)

        let options = NSMenuItem(title: "Options…", action: #selector(openSettings), keyEquivalent: ",")
        options.target = self
        menu.addItem(options)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Cornice", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    @objc private func openSettings() {
        settingsWindow?.show()
    }

    @objc private func toggleSurface() {
        controller?.toggle()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
