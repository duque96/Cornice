import XCTest
@testable import CorniceHost
@testable import CorniceKit

final class WidgetBundleTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cornice-widgets-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeBundle(
        named name: String,
        manifest: String,
        entry: String? = "<html></html>",
        in base: URL? = nil
    ) throws -> URL {
        let directory = (base ?? root).appendingPathComponent("\(name).cornicewidget", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try manifest.write(
            to: directory.appendingPathComponent("manifest.json"),
            atomically: true,
            encoding: .utf8
        )
        if let entry {
            try entry.write(
                to: directory.appendingPathComponent("index.html"),
                atomically: true,
                encoding: .utf8
            )
        }
        return directory
    }

    private func manifest(
        id: String = "com.example.hello",
        version: String = "1.0.0",
        apiVersion: Int = 1,
        capabilities: String = "[]",
        entry: String = "index.html"
    ) -> String {
        """
        {
          "id": "\(id)",
          "name": "Hello",
          "version": "\(version)",
          "apiVersion": \(apiVersion),
          "capabilities": \(capabilities),
          "networkHosts": ["example.com"],
          "placement": { "columns": 6, "rows": 2 },
          "refresh": { "interval": 30 },
          "entry": "\(entry)"
        }
        """
    }

    func testDiscoversAValidBundle() throws {
        _ = try makeBundle(named: "Hello", manifest: manifest())

        let discovery = WidgetBundleStore.discover(in: root)

        XCTAssertEqual(discovery.widgets.count, 1)
        XCTAssertTrue(discovery.errors.isEmpty, "\(discovery.errors)")

        let widget = try XCTUnwrap(discovery.widgets.first)
        XCTAssertEqual(widget.manifest.id, "com.example.hello")
        XCTAssertEqual(widget.manifest.version, SemanticVersion(1, 0, 0))
        XCTAssertEqual(widget.manifest.placement.size, GridSize(columns: 6, rows: 2))
        XCTAssertEqual(widget.manifest.refresh, .interval(30))
    }

    func testIgnoresOtherExtensions() throws {
        let other = root.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)

        XCTAssertTrue(WidgetBundleStore.discover(in: root).widgets.isEmpty)
    }

    func testRejectsUnsupportedAPIVersion() throws {
        _ = try makeBundle(named: "Old", manifest: manifest(apiVersion: 2))

        let discovery = WidgetBundleStore.discover(in: root)

        XCTAssertTrue(discovery.widgets.isEmpty)
        XCTAssertEqual(discovery.errors.count, 1)
        XCTAssertTrue(discovery.errors[0].contains("apiVersion"))
    }

    func testRejectsUnknownCapability() throws {
        _ = try makeBundle(named: "Odd", manifest: manifest(capabilities: #"["telepathy"]"#))

        let discovery = WidgetBundleStore.discover(in: root)

        XCTAssertTrue(discovery.widgets.isEmpty)
        XCTAssertTrue(discovery.errors[0].contains("telepathy"))
    }

    func testRejectsAnEntryOutsideTheBundle() throws {
        _ = try makeBundle(named: "Escape", manifest: manifest(entry: "../outside.html"))

        let discovery = WidgetBundleStore.discover(in: root)

        XCTAssertTrue(discovery.widgets.isEmpty)
        XCTAssertTrue(discovery.errors[0].contains("inside the bundle"))
    }

    func testRejectsAMissingEntryFile() throws {
        _ = try makeBundle(named: "Empty", manifest: manifest(entry: "missing.html"))

        let discovery = WidgetBundleStore.discover(in: root)

        XCTAssertTrue(discovery.widgets.isEmpty)
        XCTAssertTrue(discovery.errors[0].contains("missing.html"), "\(discovery.errors)")
    }

    @MainActor
    func testDiskWidgetsAreDisabledByDefault() {
        let preferences = WidgetPreferencesStore(url: root.appendingPathComponent("widgets.json"))

        XCTAssertFalse(preferences.isEnabled("com.example.hello", builtIn: false))
        XCTAssertTrue(preferences.isEnabled("com.example.status", builtIn: true))
    }

    @MainActor
    func testPreferencesPersist() {
        let url = root.appendingPathComponent("widgets.json")

        let first = WidgetPreferencesStore(url: url)
        first.setEnabled("com.example.hello", builtIn: false, true)
        first.setEnabled("com.example.status", builtIn: true, false)

        let second = WidgetPreferencesStore(url: url)
        XCTAssertTrue(second.isEnabled("com.example.hello", builtIn: false))
        XCTAssertFalse(second.isEnabled("com.example.status", builtIn: true))
    }

    @MainActor
    func testDefaultEnabledWidgetsStayOnUntilDisabled() {
        let url = root.appendingPathComponent("widgets.json")
        let preferences = WidgetPreferencesStore(url: url)

        XCTAssertTrue(preferences.isEnabled("com.example.status", builtIn: false, defaultEnabled: true))

        preferences.setEnabled("com.example.status", builtIn: false, false)
        XCTAssertFalse(preferences.isEnabled("com.example.status", builtIn: false, defaultEnabled: true))

        let reloaded = WidgetPreferencesStore(url: url)
        XCTAssertFalse(reloaded.isEnabled("com.example.status", builtIn: false, defaultEnabled: true))
    }

    func testBundledExampleWidgetIsValid() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let bundle = root.appendingPathComponent("BundledWidgets/ExampleWidget.cornicewidget")

        let widget = try WidgetBundleStore.load(bundleAt: bundle)

        XCTAssertEqual(widget.manifest.id, "com.example.status")
        XCTAssertTrue(widget.defaultEnabled)
        XCTAssertEqual(widget.manifest.capabilities, [.network, .keychain])
        XCTAssertEqual(widget.manifest.networkHosts, ["example.com"])
        XCTAssertEqual(widget.manifest.credentials.count, 1)

        let credential = try XCTUnwrap(widget.manifest.credentials.first)
        XCTAssertEqual(credential.host, "example.com")
        XCTAssertEqual(credential.header, "Authorization")
        XCTAssertEqual(credential.prefix, "Bearer ")
        XCTAssertEqual(credential.service, "com.duque.cornice")
    }

    // MARK: - Bundled installation

    func testInstallerCopiesBundlesOnFirstRun() throws {
        let source = root.appendingPathComponent("source", isDirectory: true)
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        _ = try makeBundle(named: "Hello", manifest: manifest(), in: source)

        let installed = WidgetInstaller.installBundledWidgets(from: source, into: destination)

        XCTAssertEqual(installed, ["com.example.hello"])
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: destination.appendingPathComponent("Hello.cornicewidget/manifest.json").path
            )
        )
    }

    func testInstallerUpgradesANewerBundledVersion() throws {
        let source = root.appendingPathComponent("source", isDirectory: true)
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)

        _ = try makeBundle(named: "Hello", manifest: manifest(version: "1.0.0"), in: source)
        WidgetInstaller.installBundledWidgets(from: source, into: destination)

        _ = try makeBundle(named: "Hello", manifest: manifest(version: "1.1.0"), in: source)
        let installed = WidgetInstaller.installBundledWidgets(from: source, into: destination)

        XCTAssertEqual(installed, ["com.example.hello"])

        let updated = try WidgetBundleStore.load(
            bundleAt: destination.appendingPathComponent("Hello.cornicewidget")
        )
        XCTAssertEqual(updated.manifest.version, SemanticVersion(1, 1, 0))
    }

    func testInstallerLeavesAnOlderOrEqualBundleAlone() throws {
        let source = root.appendingPathComponent("source", isDirectory: true)
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)

        _ = try makeBundle(named: "Hello", manifest: manifest(version: "2.0.0"), in: source)
        WidgetInstaller.installBundledWidgets(from: source, into: destination)

        let marker = destination.appendingPathComponent("Hello.cornicewidget/user-edit.txt")
        try "keep me".write(to: marker, atomically: true, encoding: .utf8)

        _ = try makeBundle(named: "Hello", manifest: manifest(version: "2.0.0"), in: source)
        let installed = WidgetInstaller.installBundledWidgets(from: source, into: destination)

        XCTAssertTrue(installed.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
    }

    // MARK: - Widget settings

    private func settingsManifest() -> WidgetManifest {
        WidgetManifest(
            id: "com.example.settings",
            name: "Settings",
            version: SemanticVersion(1, 0, 0),
            settings: [
                WidgetSetting(
                    id: "refresh",
                    title: "Refresh",
                    kind: .number(min: 30, max: 600, step: 10),
                    defaultValue: .number(60)
                ),
                WidgetSetting(
                    id: "flag",
                    title: "Flag",
                    kind: .toggle,
                    defaultValue: .bool(true)
                ),
            ],
            placement: Placement(size: GridSize(columns: 2, rows: 1))
        )
    }

    @MainActor
    func testWidgetSettingsStartFromDefaults() {
        let store = WidgetSettingsStore(root: root.appendingPathComponent("settings"))
        let manifest = settingsManifest()

        store.prepare(manifest)
        let values = store.values(for: manifest)

        XCTAssertEqual(values["refresh"], .number(60))
        XCTAssertEqual(values["flag"], .bool(true))
    }

    @MainActor
    func testWidgetSettingsClampAndPersist() {
        let settingsRoot = root.appendingPathComponent("settings")
        let manifest = settingsManifest()

        let store = WidgetSettingsStore(root: settingsRoot)
        store.prepare(manifest)
        store.set(.number(9_000), for: "refresh", of: manifest)
        store.set(.bool(false), for: "flag", of: manifest)

        XCTAssertEqual(store.values(for: manifest)["refresh"], .number(600))

        let reloaded = WidgetSettingsStore(root: settingsRoot)
        reloaded.prepare(manifest)

        XCTAssertEqual(reloaded.values(for: manifest)["refresh"], .number(600))
        XCTAssertEqual(reloaded.values(for: manifest)["flag"], .bool(false))
    }

    func testParsesSettingsFromDisk() throws {
        let manifestJSON = """
        {
          "id": "com.example.tuned",
          "name": "Tuned",
          "version": "1.0.0",
          "apiVersion": 1,
          "capabilities": [],
          "placement": { "columns": 6, "rows": 3 },
          "settings": [
            { "id": "refreshSeconds", "title": "Refresh", "type": "number",
              "min": 30, "max": 600, "step": 10, "default": 60 },
            { "id": "showMonthly", "title": "Monthly", "type": "toggle", "default": true }
          ],
          "entry": "index.html"
        }
        """
        let bundle = try makeBundle(named: "Tuned", manifest: manifestJSON)

        let widget = try WidgetBundleStore.load(bundleAt: bundle)
        let settings = widget.manifest.settings

        XCTAssertEqual(settings.count, 2)
        XCTAssertEqual(settings[0].kind, .number(min: 30, max: 600, step: 10))
        XCTAssertEqual(settings[0].defaultValue, .number(60))
        XCTAssertEqual(settings[1].kind, .toggle)
        XCTAssertEqual(settings[1].defaultValue, .bool(true))
    }

    func testRejectsANumericSettingWithoutRange() throws {
        let manifestJSON = """
        {
          "id": "com.example.broken",
          "name": "Broken",
          "version": "1.0.0",
          "apiVersion": 1,
          "placement": { "columns": 6, "rows": 3 },
          "settings": [
            { "id": "count", "title": "Count", "type": "number", "default": 3 }
          ],
          "entry": "index.html"
        }
        """
        let bundle = try makeBundle(named: "Broken", manifest: manifestJSON)

        XCTAssertThrowsError(try WidgetBundleStore.load(bundleAt: bundle))
    }

    func testEveryBundledWidgetLoads() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let directory = packageRoot.appendingPathComponent("BundledWidgets")

        let bundles = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == WidgetBundleStore.bundleExtension }

        XCTAssertGreaterThanOrEqual(bundles.count, 3)

        for bundle in bundles {
            _ = try WidgetBundleStore.load(bundleAt: bundle)
        }
    }
}
