import XCTest
@testable import CorniceCore

final class StagePagerTests: XCTestCase {
    @MainActor
    func testSelectClampsToTheAvailablePages() {
        let pager = StagePager()
        pager.setPageCount(3)

        pager.select(1)
        XCTAssertEqual(pager.index, 1)
        pager.select(5)
        XCTAssertEqual(pager.index, 2)
        pager.select(-9)
        XCTAssertEqual(pager.index, 0)
    }

    @MainActor
    func testShrinkingPagesClampsTheIndex() {
        let pager = StagePager()
        pager.setPageCount(4)
        pager.index = 3

        pager.setPageCount(2)
        XCTAssertEqual(pager.pageCount, 2)
        XCTAssertEqual(pager.index, 1)
    }

    @MainActor
    func testDragIsClampedToThePageWidth() {
        let pager = StagePager()
        pager.setPageCount(2)
        pager.beginDrag()

        pager.drag(by: -5_000, limit: 380)
        XCTAssertEqual(pager.offset, -380)
    }

    @MainActor
    func testDragRubberBandsAtTheEnds() {
        let pager = StagePager()
        pager.setPageCount(2)
        pager.beginDrag()

        // Already on the first page: dragging forwards (positive) is damped.
        pager.drag(by: 200, limit: 380)
        XCTAssertEqual(pager.offset, 70, accuracy: 0.5)
    }

    @MainActor
    func testPendingStepUsesAThreshold() {
        let pager = StagePager()
        pager.setPageCount(2)
        pager.beginDrag()

        pager.drag(by: -20, limit: 380)
        XCTAssertNil(pager.pendingStep(limit: 380))

        pager.drag(by: -120, limit: 380)
        XCTAssertEqual(pager.pendingStep(limit: 380), 1)
    }

    @MainActor
    func testCommitMovesThePageAndResetsTheOffset() {
        let pager = StagePager()
        pager.setPageCount(3)
        pager.beginDrag()
        pager.drag(by: -200, limit: 380)

        pager.commit(step: 1)

        XCTAssertEqual(pager.index, 1)
        XCTAssertEqual(pager.offset, 0)
    }

    @MainActor
    func testCancelAndEndResetTheDragState() {
        let pager = StagePager()
        pager.setPageCount(2)
        pager.beginDrag()
        pager.drag(by: -200, limit: 380)

        pager.cancelDrag()
        XCTAssertEqual(pager.offset, 0)
        XCTAssertTrue(pager.isDragging)

        pager.endInteraction()
        XCTAssertFalse(pager.isDragging)
        XCTAssertEqual(pager.offset, 0)
    }
}
