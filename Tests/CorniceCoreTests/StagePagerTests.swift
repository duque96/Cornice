import XCTest
@testable import CorniceCore

final class StagePagerTests: XCTestCase {
    @MainActor
    func testAdvanceClampsToTheAvailablePages() {
        let pager = StagePager()
        pager.setPageCount(3)

        pager.advance(1)
        XCTAssertEqual(pager.index, 1)
        pager.advance(5)
        XCTAssertEqual(pager.index, 2)
        pager.advance(-9)
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

    func testGestureNeedsEnoughTravel() {
        var gesture = PagerGestureAccumulator(threshold: 30, cooldown: 0.25)
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertNil(gesture.feed(deltaX: 10, now: now))
        XCTAssertNil(gesture.feed(deltaX: 10, now: now))
        XCTAssertEqual(gesture.feed(deltaX: 15, now: now), 1)
    }

    func testGestureIsDirectional() {
        var gesture = PagerGestureAccumulator(threshold: 30, cooldown: 0)
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(gesture.feed(deltaX: -40, now: now), -1)
    }

    func testGestureRespectsTheCooldown() {
        var gesture = PagerGestureAccumulator(threshold: 30, cooldown: 0.5)
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(gesture.feed(deltaX: 40, now: now), 1)
        XCTAssertNil(gesture.feed(deltaX: 40, now: now.addingTimeInterval(0.2)))
        XCTAssertEqual(gesture.feed(deltaX: 40, now: now.addingTimeInterval(0.6)), 1)
    }

    func testResetDropsPartialTravel() {
        var gesture = PagerGestureAccumulator(threshold: 30, cooldown: 0)
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertNil(gesture.feed(deltaX: 20, now: now))
        gesture.reset()
        XCTAssertNil(gesture.feed(deltaX: 20, now: now))
    }
}
