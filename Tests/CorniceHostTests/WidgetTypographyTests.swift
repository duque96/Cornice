import XCTest
@testable import CorniceHost

final class WidgetTypographyTests: XCTestCase {
    func testTokensDefineOneSizePerRole() {
        let css = WidgetTypography.css

        XCTAssertTrue(css.contains("--cornice-title-size: 12px;"))
        XCTAssertTrue(css.contains("--cornice-label-size: 10px;"))
        XCTAssertTrue(css.contains("--cornice-value-size: 16px;"))
        XCTAssertTrue(css.contains("--cornice-meta-size: 9.5px;"))
        XCTAssertTrue(css.contains("--cornice-mono-size: 9.5px;"))
        XCTAssertTrue(css.contains(":root"))
    }

    func testBundledWidgetsReadTokensInsteadOfHardcodingSizes() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let directory = packageRoot.appendingPathComponent("BundledWidgets")

        let bundles = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == WidgetBundleStore.bundleExtension }

        XCTAssertFalse(bundles.isEmpty)

        for bundle in bundles {
            let page = bundle.appendingPathComponent("index.html")
            let html = try String(contentsOf: page, encoding: .utf8)

            XCTAssertTrue(
                html.contains("var(--cornice-"),
                "\(bundle.lastPathComponent) should read the type tokens"
            )
            XCTAssertFalse(
                html.contains("cornice-low-dpi"),
                "\(bundle.lastPathComponent) should not scale type per display; uiScale is the only factor"
            )
            XCTAssertFalse(
                html.contains("-webkit-font-smoothing"),
                "\(bundle.lastPathComponent) should let the host decide antialiasing"
            )
        }
    }
}
