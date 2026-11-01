import AppKit
import Observation
import SwiftUI
import CorniceKit

public struct MountedWidget: Identifiable {
    public let id: WidgetID
    public let name: String
    public let size: GridSize
    public let view: AnyView
    let widget: any CorniceWidget
}

/// One row in the widget gallery: what the host found, and whether it is mounted.
public struct WidgetCatalogEntry: Identifiable, Sendable {
    public enum Source: String, Sendable {
        case builtIn
        case disk
    }

    public let id: WidgetID
    public let name: String
    public let version: SemanticVersion
    public let capabilities: Set<Capability>
    public let source: Source
    public let defaultEnabled: Bool
    public let settings: [WidgetSetting]
    public var enabled: Bool
}

@MainActor
private struct DiskWidgetFactory: WidgetFactory {
    let bundle: DiskWidget

    var manifest: WidgetManifest { bundle.manifest }

    func make(context: WidgetContext) -> any CorniceWidget {
        WebWidget(bundle: bundle, context: context)
    }
}

/// Owns the widget lifecycle: mounting, activation and the single shared clock.
///
/// Widgets come from two places: factories compiled into the app, and
/// `*.cornicewidget` bundles discovered on disk. Disk widgets start disabled.
@Observable
@MainActor
public final class WidgetHost {
    public private(set) var widgets: [MountedWidget] = []
    public private(set) var catalog: [WidgetCatalogEntry] = []
    public private(set) var discoveryErrors: [String] = []

    private let builtInFactories: [any WidgetFactory]
    private let secretStore: any SecretAccessing
    private let stageWidth: CGFloat
    private let widgetsDirectory: URL
    private let preferences: WidgetPreferencesStore
    public let settingsStore: WidgetSettingsStore
    private let log = WidgetLog(subsystem: "host")

    private var factories: [WidgetID: any WidgetFactory] = [:]
    private var manifests: [WidgetID: WidgetManifest] = [:]
    private var isActive = false
    private var ticker: Task<Void, Never>?

    public init(
        factories: [any WidgetFactory],
        secretStore: any SecretAccessing = FileSecretStore(),
        stageWidth: CGFloat = 380,
        widgetsDirectory: URL = WidgetPaths.widgetsDirectory,
        preferences: WidgetPreferencesStore? = nil,
        settingsStore: WidgetSettingsStore? = nil
    ) {
        self.builtInFactories = factories
        self.secretStore = secretStore
        self.stageWidth = stageWidth
        self.widgetsDirectory = widgetsDirectory
        self.preferences = preferences ?? WidgetPreferencesStore()
        self.settingsStore = settingsStore ?? WidgetSettingsStore()
    }

    // MARK: - Discovery

    public func start() {
        WidgetBundleStore.ensureDirectoryExists(widgetsDirectory)
        reload()
    }

    public func reload() {
        unmountAll()

        let discovery = WidgetBundleStore.discover(in: widgetsDirectory)
        discoveryErrors = discovery.errors

        var factories: [WidgetID: any WidgetFactory] = [:]
        var entries: [WidgetCatalogEntry] = []

        for factory in builtInFactories {
            let manifest = factory.manifest
            guard manifest.problems.isEmpty else {
                log.warn("skipping \(manifest.id): \(manifest.problems.joined(separator: ", "))")
                continue
            }
            factories[manifest.id] = factory
            entries.append(
                WidgetCatalogEntry(
                    id: manifest.id,
                    name: manifest.name,
                    version: manifest.version,
                    capabilities: manifest.capabilities,
                    source: .builtIn,
                    defaultEnabled: true,
                    settings: manifest.settings,
                    enabled: preferences.isEnabled(manifest.id, builtIn: true)
                )
            )
        }

        for bundle in discovery.widgets {
            let manifest = bundle.manifest
            guard factories[manifest.id] == nil else {
                discoveryErrors.append("\(manifest.id): duplicated id, ignoring the disk copy")
                continue
            }
            factories[manifest.id] = DiskWidgetFactory(bundle: bundle)
            entries.append(
                WidgetCatalogEntry(
                    id: manifest.id,
                    name: manifest.name,
                    version: manifest.version,
                    capabilities: manifest.capabilities,
                    source: .disk,
                    defaultEnabled: bundle.defaultEnabled,
                    settings: manifest.settings,
                    enabled: preferences.isEnabled(
                        manifest.id,
                        builtIn: false,
                        defaultEnabled: bundle.defaultEnabled
                    )
                )
            )
        }

        self.factories = factories
        self.manifests = factories.compactMapValues { $0.manifest }

        for entry in entries {
            if let manifest = self.manifests[entry.id] {
                settingsStore.prepare(manifest)
            }
        }

        catalog = entries

        for entry in entries where entry.enabled {
            mount(entry.id)
        }

        if isActive {
            startTicker()
        }
    }

    // MARK: - Enable / disable

    public func setEnabled(_ id: WidgetID, _ enabled: Bool) {
        guard let index = catalog.firstIndex(where: { $0.id == id }),
              catalog[index].enabled != enabled
        else { return }

        preferences.setEnabled(id, builtIn: catalog[index].source == .builtIn, enabled)
        catalog[index].enabled = enabled

        if enabled {
            mount(id)
        } else {
            unmount(id)
        }
    }

    public func isEnabled(_ id: WidgetID) -> Bool {
        catalog.first { $0.id == id }?.enabled ?? false
    }

    // MARK: - Settings

    public func manifest(for id: WidgetID) -> WidgetManifest? {
        manifests[id]
    }

    public func settingsValues(for id: WidgetID) -> [String: SettingValue] {
        guard let manifest = manifests[id] else { return [:] }
        return settingsStore.values(for: manifest)
    }

    /// Applies a setting and remounts the widget so it reads the new value.
    public func setSetting(_ id: WidgetID, key: String, value: SettingValue) {
        guard let manifest = manifests[id] else { return }

        settingsStore.set(value, for: key, of: manifest)

        guard widgets.contains(where: { $0.id == id }) else { return }
        unmount(id)
        mount(id)
    }

    // MARK: - Lifecycle

    public func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active

        for item in widgets {
            if active {
                item.widget.activate()
            } else {
                item.widget.deactivate()
            }
        }

        if active {
            startTicker()
        } else {
            stopTicker()
        }
    }

    private func mount(_ id: WidgetID) {
        guard !widgets.contains(where: { $0.id == id }), let factory = factories[id] else { return }

        let manifest = factory.manifest
        let widgetLog = WidgetLog(subsystem: manifest.id)

        let scopedSecrets: (any SecretAccessing)? = manifest.capabilities.contains(.keychain)
            ? ScopedSecrets(base: secretStore, allowedServices: Set(manifest.keychainServices))
            : nil

        let credentialSources: [CredentialSource] = scopedSecrets.map { secrets in
            manifest.credentials.map { CredentialSource(rule: $0, secrets: secrets) }
        } ?? []

        let http: (any HTTPClient)? = manifest.capabilities.contains(.network)
            ? WidgetHTTPClient(
                allowedHosts: Set(manifest.networkHosts),
                credentials: credentialSources,
                log: widgetLog
            )
            : nil

        let context = WidgetContext(
            capabilities: manifest.capabilities,
            secrets: scopedSecrets,
            http: http,
            settings: WidgetSettings(values: settingsStore.values(for: manifest)),
            log: widgetLog,
            availableWidth: stageWidth
        )

        let widget = factory.make(context: context)
        widgets.append(
            MountedWidget(
                id: manifest.id,
                name: manifest.name,
                size: manifest.placement.size,
                view: widget.makeView(),
                widget: widget
            )
        )

        if isActive {
            widget.activate()
        }

        log.warn("mounted \(manifest.id) \(manifest.version)")
    }

    private func unmount(_ id: WidgetID) {
        guard let index = widgets.firstIndex(where: { $0.id == id }) else { return }
        widgets[index].widget.deactivate()
        widgets.remove(at: index)
        log.warn("unmounted \(id)")
    }

    private func unmountAll() {
        for item in widgets {
            item.widget.deactivate()
        }
        widgets.removeAll()
        stopTicker()
    }

    // MARK: - Clock

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }

                let now = Date()
                for item in self.widgets {
                    item.widget.tick(now)
                }
            }
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }
}
