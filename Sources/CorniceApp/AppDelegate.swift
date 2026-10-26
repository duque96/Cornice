import AppKit
import CorniceCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchSurfaceController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let forceSimulation = ProcessInfo.processInfo.environment["CORNICE_SIMULATE"] == "1"
        let provider: NotchGeometryProviding = forceSimulation
            ? SimulatedNotchGeometry()
            : AutomaticNotchGeometry()

        let controller = NotchSurfaceController(geometryProvider: provider)
        controller.start()
        self.controller = controller

        if ProcessInfo.processInfo.environment["CORNICE_START_OPEN"] == "1" {
            controller.openImmediately()
        }

        installStatusItem()
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

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Cornice", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    @objc private func toggleSurface() {
        controller?.toggle()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
