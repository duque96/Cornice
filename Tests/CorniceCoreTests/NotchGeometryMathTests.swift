import XCTest
@testable import CorniceCore

final class NotchGeometryMathTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    func testHardwareNotchUsesTheGapBetweenAuxiliaryAreas() {
        let rect = NotchGeometryMath.hardwareNotchRect(
            screenFrame: screen,
            safeAreaTop: 38,
            leftArea: CGRect(x: 0, y: 944, width: 656, height: 38),
            rightArea: CGRect(x: 856, y: 944, width: 656, height: 38)
        )

        XCTAssertEqual(rect, CGRect(x: 656, y: 944, width: 200, height: 38))
    }

    func testHardwareNotchRequiresASafeArea() {
        let rect = NotchGeometryMath.hardwareNotchRect(
            screenFrame: screen,
            safeAreaTop: 0,
            leftArea: CGRect(x: 0, y: 982, width: 656, height: 0),
            rightArea: CGRect(x: 856, y: 982, width: 656, height: 0)
        )

        XCTAssertNil(rect)
    }

    func testHardwareNotchRejectsGapsTooNarrowToBeARealNotch() {
        let rect = NotchGeometryMath.hardwareNotchRect(
            screenFrame: screen,
            safeAreaTop: 38,
            leftArea: CGRect(x: 0, y: 944, width: 740, height: 38),
            rightArea: CGRect(x: 760, y: 944, width: 752, height: 38)
        )

        XCTAssertNil(rect)
    }

    func testSimulatedNotchIsTopCentered() {
        let rect = NotchGeometryMath.simulatedNotchRect(screenFrame: screen)

        XCTAssertEqual(rect.midX, screen.midX)
        XCTAssertEqual(rect.maxY, screen.maxY)
        XCTAssertEqual(rect.size, NotchGeometryMath.defaultNotchSize)
    }

    func testExpandedRectHangsFromTopCenteredOnNotch() {
        let notch = CGRect(x: 656, y: 944, width: 200, height: 38)
        let rect = NotchGeometryMath.expandedRect(
            screenFrame: screen,
            notchRect: notch,
            size: CGSize(width: 420, height: 190)
        )

        XCTAssertEqual(rect.maxY, screen.maxY)
        XCTAssertEqual(rect.midX, notch.midX)
        XCTAssertEqual(rect.size, CGSize(width: 420, height: 190))
    }

    func testHotZoneIsForgiving() {
        let notch = CGRect(x: 656, y: 944, width: 200, height: 38)
        let zone = NotchGeometryMath.hotZone(notchRect: notch, tolerance: 14)

        XCTAssertEqual(zone.minX, notch.minX - 14)
        XCTAssertEqual(zone.maxY, notch.maxY + 14)
        XCTAssertTrue(zone.contains(CGPoint(x: notch.minX - 10, y: notch.midY)))
        XCTAssertFalse(zone.contains(CGPoint(x: notch.minX - 20, y: notch.midY)))
    }

    func testOpenZoneAddsToleranceAroundThePanel() {
        let panel = CGRect(x: 546, y: 792, width: 420, height: 190)
        let zone = NotchGeometryMath.openZone(expandedRect: panel, tolerance: 4)

        XCTAssertEqual(zone.width, panel.width + 8)
        XCTAssertEqual(zone.height, panel.height + 8)
    }
}
