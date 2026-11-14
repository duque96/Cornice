import XCTest
@testable import CorniceCore

final class WheelPagingTests: XCTestCase {
    func testNotchInLinesPagesOnceAfterAccumulating() {
        var state = WheelPagingState()

        XCTAssertNil(state.step(delta: -1, precise: false, at: 0))
        XCTAssertEqual(state.step(delta: -1, precise: false, at: 0.02), 1)
    }

    func testBurstFromOneNotchPagesOnce() {
        var state = WheelPagingState()
        var steps: [Int] = []

        // Logitech-style mice emit several line events per physical notch.
        for index in 0..<5 {
            if let step = state.step(delta: -1, precise: false, at: Double(index) * 0.01) {
                steps.append(step)
            }
        }

        XCTAssertEqual(steps, [1])
        // The tail of the same burst is swallowed by the cooldown.
        XCTAssertNil(state.step(delta: -1, precise: false, at: 0.1))
    }

    func testScrollingUpPagesBack() {
        var state = WheelPagingState()

        XCTAssertNil(state.step(delta: 1, precise: false, at: 0))
        XCTAssertEqual(state.step(delta: 1, precise: false, at: 0.01), -1)
    }

    func testCooldownExpires() {
        var state = WheelPagingState()

        _ = state.step(delta: -1, precise: false, at: 0)
        _ = state.step(delta: -1, precise: false, at: 0.01)
        XCTAssertNil(state.step(delta: -1, precise: false, at: 0.30))
        // After the cooldown a new notch starts from zero and needs its full delta.
        XCTAssertNil(state.step(delta: -1, precise: false, at: 0.32))
        XCTAssertEqual(state.step(delta: -1, precise: false, at: 0.33), 1)
    }

    func testPreciseDeltasAreAlreadyPoints() {
        var state = WheelPagingState()

        XCTAssertNil(state.step(delta: -12, precise: true, at: 0))
        XCTAssertEqual(state.step(delta: -9, precise: true, at: 0.01), 1)
    }

    func testIdleClearsPartialAccumulation() {
        var state = WheelPagingState()

        XCTAssertNil(state.step(delta: -1, precise: false, at: 0))
        XCTAssertNil(state.step(delta: -1, precise: false, at: 1.0))
        XCTAssertEqual(state.step(delta: -1, precise: false, at: 1.01), 1)
    }
}
