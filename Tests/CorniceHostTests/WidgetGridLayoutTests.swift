import XCTest
@testable import CorniceHost
@testable import CorniceKit

final class WidgetGridLayoutTests: XCTestCase {
    private let available = CGSize(width: 380, height: 114)

    func testTwoHalfWidthWidgetsShareARow() {
        let pages = WidgetGridLayout.layout(
            widgets: [
                WidgetGridLayout.Widget(id: "a", size: GridSize(columns: 3, rows: 3)),
                WidgetGridLayout.Widget(id: "b", size: GridSize(columns: 3, rows: 2)),
            ],
            available: available
        )

        XCTAssertEqual(pages.count, 1)
        XCTAssertEqual(pages[0].items.count, 2)

        let first = pages[0].items[0].frame
        let second = pages[0].items[1].frame

        XCTAssertEqual(first.minX, 0)
        XCTAssertEqual(first.width, 186, accuracy: 0.5)
        XCTAssertEqual(first.height, 30 * 3 + 8 * 2, accuracy: 0.5)
        XCTAssertEqual(second.minX, first.maxX + WidgetGridLayout.gap, accuracy: 0.5)
        XCTAssertEqual(second.width, 186, accuracy: 0.5)
        XCTAssertEqual(second.minY, 0)
    }

    func testAFullWidthWidgetTakesItsOwnRow() {
        let pages = WidgetGridLayout.layout(
            widgets: [
                WidgetGridLayout.Widget(id: "a", size: GridSize(columns: 3, rows: 1)),
                WidgetGridLayout.Widget(id: "b", size: GridSize(columns: 6, rows: 1)),
                WidgetGridLayout.Widget(id: "c", size: GridSize(columns: 3, rows: 1)),
            ],
            available: CGSize(width: 380, height: 400)
        )

        XCTAssertEqual(pages.count, 1)
        let items = pages[0].items

        XCTAssertEqual(items[0].frame.minX, 0, accuracy: 0.5)
        XCTAssertEqual(items[1].frame.minX, 0, accuracy: 0.5)
        XCTAssertGreaterThan(items[1].frame.minY, items[0].frame.minY)
        XCTAssertEqual(items[2].frame.minX, 0, accuracy: 0.5)
        XCTAssertGreaterThan(items[2].frame.minY, items[1].frame.minY)
    }

    func testOverflowStartsANewPage() {
        let pages = WidgetGridLayout.layout(
            widgets: [
                WidgetGridLayout.Widget(id: "a", size: GridSize(columns: 6, rows: 3)),
                WidgetGridLayout.Widget(id: "b", size: GridSize(columns: 6, rows: 3)),
            ],
            available: available
        )

        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[0].items.map(\.id), ["a"])
        XCTAssertEqual(pages[1].items.map(\.id), ["b"])
    }

    func testPriorityMovesAWidgetFirst() {
        let pages = WidgetGridLayout.layout(
            widgets: [
                WidgetGridLayout.Widget(id: "low", size: GridSize(columns: 3, rows: 1), priority: 0),
                WidgetGridLayout.Widget(id: "high", size: GridSize(columns: 3, rows: 1), priority: 10),
            ],
            available: available
        )

        XCTAssertEqual(pages[0].items.map(\.id), ["high", "low"])
        XCTAssertEqual(pages[0].items[0].frame.minX, 0, accuracy: 0.5)
    }

    func testFramesNeverExceedTheAvailableArea() {
        let pages = WidgetGridLayout.layout(
            widgets: [
                WidgetGridLayout.Widget(id: "wide", size: GridSize(columns: 9, rows: 9)),
            ],
            available: available
        )

        let frame = pages[0].items[0].frame
        XCTAssertLessThanOrEqual(frame.maxX, available.width + 0.5)
        XCTAssertLessThanOrEqual(frame.maxY, available.height + 0.5)
    }

    func testEmptyInputHasNoPages() {
        XCTAssertTrue(
            WidgetGridLayout.layout(widgets: [], available: available).isEmpty
        )
        XCTAssertTrue(
            WidgetGridLayout.layout(
                widgets: [WidgetGridLayout.Widget(id: "a", size: GridSize(columns: 3, rows: 1))],
                available: .zero
            ).isEmpty
        )
    }
}
