import XCTest
import SwiftUI
@testable import CorniceCore

@MainActor
final class SettingsTests: XCTestCase {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cornice-settings-\(UUID().uuidString).json")
    }

    func testTranslatorFollowsTheLanguage() {
        XCTAssertEqual(Translator(.en)("Motion", "Movimiento"), "Motion")
        XCTAssertEqual(Translator(.es)("Motion", "Movimiento"), "Movimiento")
        XCTAssertEqual(
            Translator(.system)("Motion", "Movimiento"),
            AppLanguage.systemDefault == .es ? "Movimiento" : "Motion"
        )
    }

    func testLanguageIsPersisted() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = SettingsStore(url: url)
        store.set(\.language, .es)
        store.saveNow()

        XCTAssertEqual(SettingsStore(url: url).settings.language, .es)
    }

    func testFitToContentIsOnByDefault() {
        XCTAssertTrue(CorniceSettings.standard.fitToContent)
    }

    func testDefaultsAreWithinClampRanges() {
        let defaults = CorniceSettings.standard
        XCTAssertEqual(defaults, defaults.clamped())
    }

    func testClampingRejectsUnusableValues() {
        var settings = CorniceSettings()
        settings.motion.openResponse = 12
        settings.motion.openDamping = 0.1
        settings.motion.contentDuration = 0
        settings.hoverOpenDelay = -3
        settings.expandedWidth = 5000
        settings.expandedHeight = 10

        let clamped = settings.clamped()

        XCTAssertEqual(clamped.motion.openResponse, 1.20)
        XCTAssertEqual(clamped.motion.openDamping, 0.50)
        XCTAssertEqual(clamped.motion.contentDuration, 0.05)
        XCTAssertEqual(clamped.hoverOpenDelay, 0)
        XCTAssertEqual(clamped.expandedWidth, 900)
        XCTAssertEqual(clamped.expandedHeight, 120)
    }

    func testSettingsRoundTrip() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = SettingsStore(url: url)
        store.set(\.motion.openResponse, 0.44)
        store.set(\.expandedWidth, 520)
        store.set(\.hoverCloseDelay, 0.25)
        store.set(\.showMenuBarIcon, false)
        store.saveNow()

        let reloaded = SettingsStore(url: url)

        XCTAssertEqual(reloaded.settings.motion.openResponse, 0.44)
        XCTAssertEqual(reloaded.settings.expandedWidth, 520)
        XCTAssertEqual(reloaded.settings.hoverCloseDelay, 0.25)
        XCTAssertFalse(reloaded.settings.showMenuBarIcon)
    }

    func testCorruptedFileFallsBackToDefaults() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json".utf8).write(to: url)

        let store = SettingsStore(url: url)

        XCTAssertEqual(store.settings, .standard)
    }

    func testResetRestoresDefaults() {
        let store = SettingsStore(url: temporaryURL())
        store.set(\.motion.openResponse, 0.7)
        store.reset()

        XCTAssertEqual(store.settings, .standard)
    }

    func testRenderSettingsWindow() throws {
        let store = SettingsStore(url: temporaryURL())
        let view = MotionSettingsView(store: store)
            .padding(20)
            .frame(width: 520)
            .fixedSize(horizontal: false, vertical: true)
            .background(Color(nsColor: .windowBackgroundColor))

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            XCTFail("Could not render settings")
            return
        }

        let directory = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["CORNICE_SNAPSHOT_DIR"] ?? NSTemporaryDirectory(),
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appendingPathComponent("cornice-settings.png"))
    }
}
