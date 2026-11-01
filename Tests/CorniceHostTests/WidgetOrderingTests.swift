import XCTest
@testable import CorniceHost
@testable import CorniceKit

final class WidgetOrderingTests: XCTestCase {
    func testExplicitOrderWinsAndTheRestKeepTheirPosition() {
        let ids = ["a", "b", "c", "d"]

        XCTAssertEqual(WidgetOrdering.sorted(ids, by: ["c"]), ["c", "a", "b", "d"])
        XCTAssertEqual(WidgetOrdering.sorted(ids, by: ["d", "b"]), ["d", "b", "a", "c"])
        XCTAssertEqual(WidgetOrdering.sorted(ids, by: []), ids)
    }

    func testUnknownIDsInTheOrderAreIgnored() {
        let ids = ["a", "b"]

        XCTAssertEqual(WidgetOrdering.sorted(ids, by: ["ghost", "b"]), ["b", "a"])
    }

    func testMovingPutsTheItemInTheTargetSlot() {
        let ids = ["a", "b", "c"]

        XCTAssertEqual(WidgetOrdering.moving("c", before: "a", in: ids), ["c", "a", "b"])
        XCTAssertEqual(WidgetOrdering.moving("a", before: "c", in: ids), ["b", "a", "c"])
    }

    func testMovingToItselfChangesNothing() {
        XCTAssertEqual(WidgetOrdering.moving("b", before: "b", in: ["a", "b"]), ["a", "b"])
    }

    @MainActor
    func testOrderPersists() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cornice-order-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let first = WidgetPreferencesStore(url: url)
        first.setOrder(["c", "a", "b"])

        let second = WidgetPreferencesStore(url: url)
        XCTAssertEqual(second.current.order, ["c", "a", "b"])
    }
}
