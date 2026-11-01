import XCTest
import SwiftUI
@testable import CorniceHost
@testable import CorniceKit

final class WidgetResizeTests: XCTestCase {
    private let columnWidth: CGFloat = (380 - 8 * 5) / 6
    private let rowUnit: CGFloat = 30
    private let gap: CGFloat = 8

    private func snap(from size: GridSize, translation: CGSize) -> GridSize {
        WidgetResize.snapped(
            start: size,
            translation: translation,
            columnWidth: columnWidth,
            rowUnit: rowUnit,
            gap: gap
        )
    }

    func testNoTranslationKeepsTheSize() {
        XCTAssertEqual(snap(from: GridSize(columns: 3, rows: 2), translation: .zero), GridSize(columns: 3, rows: 2))
    }

    func testGrowingOneColumnAndOneRow() {
        let translation = CGSize(width: columnWidth + gap, height: rowUnit + gap)
        XCTAssertEqual(
            snap(from: GridSize(columns: 3, rows: 2), translation: translation),
            GridSize(columns: 4, rows: 3)
        )
    }

    func testClampsToTheGrid() {
        XCTAssertEqual(
            snap(from: GridSize(columns: 3, rows: 3), translation: CGSize(width: 5_000, height: 5_000)),
            GridSize(columns: 6, rows: WidgetResize.maxRows)
        )
        XCTAssertEqual(
            snap(from: GridSize(columns: 3, rows: 3), translation: CGSize(width: -5_000, height: -5_000)),
            GridSize(columns: 1, rows: 1)
        )
    }
}

// MARK: - Host integration

@MainActor
private final class StubWidget: CorniceWidget {
    func makeView() -> AnyView { AnyView(EmptyView()) }
    func activate() {}
    func deactivate() {}
    func tick(_ now: Date) {}
}

@MainActor
private struct StubFactory: WidgetFactory {
    let manifest: WidgetManifest

    func make(context: WidgetContext) -> any CorniceWidget { StubWidget() }
}

final class WidgetSizePersistenceTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cornice-size-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @MainActor
    func testResizingUpdatesTheHostAndPersists() {
        let preferencesURL = root.appendingPathComponent("widgets.json")
        let preferences = WidgetPreferencesStore(url: preferencesURL)
        let manifest = WidgetManifest(
            id: "com.example.tile",
            name: "Tile",
            version: SemanticVersion(1, 0, 0),
            placement: Placement(size: GridSize(columns: 3, rows: 3))
        )

        let host = WidgetHost(
            factories: [StubFactory(manifest: manifest)],
            widgetsDirectory: root.appendingPathComponent("Widgets", isDirectory: true),
            preferences: preferences,
            settingsStore: WidgetSettingsStore(root: root.appendingPathComponent("settings"))
        )
        host.start()

        XCTAssertEqual(host.size(for: "com.example.tile"), GridSize(columns: 3, rows: 3))

        host.setSize(GridSize(columns: 4, rows: 2), for: "com.example.tile")
        XCTAssertEqual(host.size(for: "com.example.tile"), GridSize(columns: 4, rows: 2))
        XCTAssertEqual(host.widgets.first?.size, GridSize(columns: 4, rows: 2))

        let reloaded = WidgetPreferencesStore(url: preferencesURL)
        XCTAssertEqual(reloaded.size(for: "com.example.tile"), GridSize(columns: 4, rows: 2))
    }

    @MainActor
    func testSizesAreClamped() {
        let manifest = WidgetManifest(
            id: "com.example.tile",
            name: "Tile",
            version: SemanticVersion(1, 0, 0),
            placement: Placement(size: GridSize(columns: 3, rows: 3))
        )

        let host = WidgetHost(
            factories: [StubFactory(manifest: manifest)],
            widgetsDirectory: root.appendingPathComponent("Widgets", isDirectory: true),
            preferences: WidgetPreferencesStore(url: root.appendingPathComponent("widgets.json")),
            settingsStore: WidgetSettingsStore(root: root.appendingPathComponent("settings"))
        )
        host.start()

        host.setSize(GridSize(columns: 99, rows: 99), for: "com.example.tile")
        XCTAssertEqual(host.size(for: "com.example.tile"), GridSize(columns: 6, rows: WidgetResize.maxRows))
    }

    @MainActor
    func testResetGoesBackToTheManifestSize() {
        let manifest = WidgetManifest(
            id: "com.example.tile",
            name: "Tile",
            version: SemanticVersion(1, 0, 0),
            placement: Placement(size: GridSize(columns: 2, rows: 2))
        )

        let host = WidgetHost(
            factories: [StubFactory(manifest: manifest)],
            widgetsDirectory: root.appendingPathComponent("Widgets", isDirectory: true),
            preferences: WidgetPreferencesStore(url: root.appendingPathComponent("widgets.json")),
            settingsStore: WidgetSettingsStore(root: root.appendingPathComponent("settings"))
        )
        host.start()
        host.setSize(GridSize(columns: 5, rows: 4), for: "com.example.tile")

        host.resetSizes()

        XCTAssertEqual(host.size(for: "com.example.tile"), GridSize(columns: 2, rows: 2))
    }

    @MainActor
    func testPreferredStageHeightUsesTheTallestRow() {
        func manifest(_ id: String, columns: Int, rows: Int) -> WidgetManifest {
            WidgetManifest(
                id: id,
                name: id,
                version: SemanticVersion(1, 0, 0),
                placement: Placement(size: GridSize(columns: columns, rows: rows))
            )
        }

        let host = WidgetHost(
            factories: [
                StubFactory(manifest: manifest("com.example.a", columns: 3, rows: 3)),
                StubFactory(manifest: manifest("com.example.b", columns: 3, rows: 2)),
            ],
            widgetsDirectory: root.appendingPathComponent("Widgets", isDirectory: true),
            preferences: WidgetPreferencesStore(url: root.appendingPathComponent("widgets.json")),
            settingsStore: WidgetSettingsStore(root: root.appendingPathComponent("settings"))
        )
        host.start()

        // Two 3-column widgets share a row whose height is the taller one: 3 rows.
        XCTAssertEqual(host.preferredStageHeight(forWidth: 380), 30 * 3 + 8 * 2, accuracy: 0.5)
    }
}
