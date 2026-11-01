import AppKit
import SwiftUI
import CorniceCore
import CorniceHost

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchSurfaceController?
    private var settingsWindow: SettingsWindowController?
    private var widgetHost: WidgetHost?
    private var settingsStore: SettingsStore?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let forceSimulation = ProcessInfo.processInfo.environment["CORNICE_SIMULATE"] == "1"
        let provider: NotchGeometryProviding = forceSimulation
            ? SimulatedNotchGeometry()
            : AutomaticNotchGeometry()

        let settings = SettingsStore()
        settingsStore = settings
        let pager = StagePager()
        let controller = NotchSurfaceController(
            settings: settings,
            geometryProvider: provider,
            pager: pager
        )
        controller.start()
        self.controller = controller

        // Import the legacy plain-text key once, so widgets only need the Keychain.
        LegacyCredentials.migrateLegacyKeyIfNeeded()

        // Widgets shipped inside the app land in Application Support on first run.
        if let bundled = WidgetInstaller.bundledWidgetsURL {
            WidgetInstaller.installBundledWidgets(from: bundled, into: WidgetPaths.widgetsDirectory)
        }

        let host = WidgetHost(factories: [])
        widgetHost = host

        controller.widgetContent = AnyView(WidgetAreaView(host: host, pager: pager))
        controller.stageHeightProvider = { [weak host] width in
            host?.preferredStageHeight(forWidth: width) ?? 0
        }
        controller.onStateChanged = { [weak host] state in
            host?.setActive(state == .open)
        }
        host.onLayoutChange = { [weak controller] in
            controller?.refreshStage()
        }

        // Start after wiring: mounting triggers the first fit-to-content pass.
        host.start()

        settings.onChange = { [weak self, weak controller] in
            controller?.applySettings()
            self?.syncStatusItem()
        }

        controller.onOpenSettings = { [weak self] in
            self?.openSettings()
        }

        settingsWindow = SettingsWindowController(
            sections: { [weak self, weak host] in
                guard let self else { return [] }
                return self.makeSections(settings: settings, host: host)
            },
            onPreview: { [weak controller] pinned in
                controller?.setPinned(pinned)
            }
        )

        if ProcessInfo.processInfo.environment["CORNICE_START_OPEN"] == "1" {
            // Pin it: design review should not depend on where the pointer is.
            controller.setPinned(true)
        }

        syncStatusItem()

        if ProcessInfo.processInfo.environment["CORNICE_START_SETTINGS"] == "1" {
            openSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }

    private func syncStatusItem() {
        let shouldShow = settingsStore?.settings.showMenuBarIcon ?? true
        debugLog("menu bar icon: \(shouldShow ? "shown" : "hidden")")

        if shouldShow, statusItem == nil {
            installStatusItem()
        } else if !shouldShow, let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func debugLog(_ message: String) {
        guard ProcessInfo.processInfo.environment["CORNICE_DEBUG"] == "1" else { return }
        FileHandle.standardError.write(Data("[cornice] \(message)\n".utf8))
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

    private func makeSections(settings: SettingsStore, host: WidgetHost?) -> [SettingsSection] {
        var sections: [SettingsSection] = [
            SettingsSection(
                id: "general",
                title: "General",
                systemImage: "gearshape",
                content: AnyView(
                    GeneralSettingsView(store: settings) {
                        NSApp.terminate(nil)
                    }
                )
            ),
            SettingsSection(
                id: "motion",
                title: "Motion",
                systemImage: "sparkles",
                content: AnyView(MotionSettingsView(store: settings))
            ),
            SettingsSection(
                id: "interaction",
                title: "Interaction",
                systemImage: "cursorarrow.rays",
                content: AnyView(InteractionSettingsView(store: settings))
            ),
            SettingsSection(
                id: "panel",
                title: "Panel",
                systemImage: "rectangle.topthird.inset.filled",
                content: AnyView(PanelSettingsView(store: settings))
            ),
        ]

        guard let host else { return sections }

        sections.append(
            SettingsSection(
                id: "layout",
                title: "Layout",
                systemImage: "rectangle.3.group",
                content: AnyView(LayoutEditorView(host: host))
            )
        )

        sections.append(
            SettingsSection(
                id: "widgets",
                title: "Widgets",
                systemImage: "square.grid.2x2",
                content: AnyView(
                    WidgetGalleryView(host: host) {
                        WidgetBundleStore.ensureDirectoryExists()
                        NSWorkspace.shared.activateFileViewerSelecting([WidgetPaths.widgetsDirectory])
                    }
                )
            )
        )

        for entry in host.catalog where !entry.settings.isEmpty {
            sections.append(
                SettingsSection(
                    id: "widget.\(entry.id)",
                    title: entry.name,
                    systemImage: entry.source == .disk ? "shippingbox" : "hammer",
                    content: AnyView(WidgetSettingsView(host: host, widgetID: entry.id))
                )
            )
        }

        return sections
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
