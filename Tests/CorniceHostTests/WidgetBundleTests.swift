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
        entry: String? = "<html></html>"
    ) throws -> URL {
        let directory = root.appendingPathComponent("\(name).cornicewidget", isDirectory: true)
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
}
