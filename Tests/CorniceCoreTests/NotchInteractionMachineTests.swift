import XCTest
@testable import CorniceCore

final class NotchInteractionMachineTests: XCTestCase {
    private let notch = CGRect(x: 763, y: 1074, width: 185, height: 33)
    private let panel = CGRect(x: 645, y: 917, width: 420, height: 190)

    private func machine() -> NotchInteractionMachine { NotchInteractionMachine() }

    private func insidePoint() -> CGPoint { CGPoint(x: notch.midX, y: notch.midY) }
    private func farPoint() -> CGPoint { CGPoint(x: 200, y: 300) }

    func testHoverArmsAndSchedulesOpening() {
        var m = machine()
        XCTAssertEqual(m.pointerMoved(at: insidePoint(), notch: notch, panel: panel), .scheduleOpen)
        XCTAssertEqual(m.state, .armed)
    }

    func testLeavingBeforeTheDelayCancels() {
        var m = machine()
        _ = m.pointerMoved(at: insidePoint(), notch: notch, panel: panel)
        XCTAssertEqual(m.pointerMoved(at: farPoint(), notch: notch, panel: panel), .cancelScheduled)
        XCTAssertEqual(m.state, .dormant)
    }

    func testOpenDeadlineOnlyOpensWhenArmed() {
        var m = machine()
        XCTAssertEqual(m.openDeadlineReached(), .none)
        XCTAssertEqual(m.state, .dormant)

        _ = m.pointerMoved(at: insidePoint(), notch: notch, panel: panel)
        XCTAssertEqual(m.openDeadlineReached(), .open)
        XCTAssertEqual(m.state, .open)
    }

    func testStayingOpenDoesNotArmAgain() {
        var m = machine()
        _ = m.pointerMoved(at: insidePoint(), notch: notch, panel: panel)
        _ = m.openDeadlineReached()

        XCTAssertEqual(m.pointerMoved(at: insidePoint(), notch: notch, panel: panel), .cancelScheduled)
        XCTAssertEqual(m.state, .open)
    }

    func testLeavingSchedulesCollapseOnlyOnce() {
        var m = machine()
        _ = m.pointerMoved(at: insidePoint(), notch: notch, panel: panel)
        _ = m.openDeadlineReached()

        XCTAssertEqual(m.pointerMoved(at: farPoint(), notch: notch, panel: panel), .scheduleClose)
        XCTAssertEqual(m.pointerMoved(at: farPoint(), notch: notch, panel: panel), .none)
        XCTAssertEqual(m.state, .open)
    }

    func testComingBackCancelsTheCollapse() {
        var m = machine()
        _ = m.pointerMoved(at: insidePoint(), notch: notch, panel: panel)
        _ = m.openDeadlineReached()
        _ = m.pointerMoved(at: farPoint(), notch: notch, panel: panel)

        XCTAssertEqual(m.pointerMoved(at: insidePoint(), notch: notch, panel: panel), .cancelScheduled)

        // A timer that fires after the pointer came back must be ignored.
        XCTAssertEqual(m.closeDeadlineReached(), .none)
        XCTAssertEqual(m.state, .open)
    }

    func testCollapseDeadlineIsIgnoredWhenNotOpen() {
        var m = machine()
        XCTAssertEqual(m.closeDeadlineReached(), .none)
        XCTAssertEqual(m.state, .dormant)
    }

    func testOpenZoneIsMoreForgivingThanTheNotch() {
        var m = machine()
        _ = m.pointerMoved(at: insidePoint(), notch: notch, panel: panel)
        _ = m.openDeadlineReached()

        // Inside the expanded panel but well below the notch.
        let panelPoint = CGPoint(x: panel.midX, y: panel.minY + 20)
        XCTAssertEqual(m.pointerMoved(at: panelPoint, notch: notch, panel: panel), .cancelScheduled)
        XCTAssertEqual(m.state, .open)
    }
}
