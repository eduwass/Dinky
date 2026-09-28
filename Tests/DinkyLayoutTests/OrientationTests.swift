import CoreGraphics
import XCTest
@testable import DinkyLayout

/// `auto` orientation, `setOrientation` and accordions turning `auto`.
final class OrientationTests: XCTestCase {
    /// h[1 v[2 3]] in 1000x600: the column on the right is 500x600, taller than wide. 3 is focused.
    func column(autoOrientAccordions: Bool = true) -> Workspace {
        var ws = workspace(3)
        ws.autoOrientAccordions = autoOrientAccordions
        return ws
    }

    func testAutoResolvesAlongTheLongerSide() {
        let c = Container(.auto)
        XCTAssertEqual(c.axis(in: rect(0, 0, 800, 600)), .horizontal)
        XCTAssertEqual(c.axis(in: rect(0, 0, 600, 800)), .vertical)
        XCTAssertEqual(c.axis(in: rect(0, 0, 600, 600)), .horizontal)
    }

    func testAutoTilesFollowTheWorkspaceShape() {
        var ws = workspace(2)
        ws.setOrientation(.auto)
        XCTAssertEqual(shape(ws.root), "*[1 2]")
        XCTAssertEqual(ws.layout().frames[2], rect(500, 0, 500, 600))
        ws.bounds = rect(0, 0, 600, 1000)
        XCTAssertEqual(ws.layout().frames[2], rect(0, 500, 600, 500))
        XCTAssertEqual(ws.containerAxis(of: 2), .vertical)
    }

    func testANewAccordionWorkspaceOnATallDisplayRunsTopToBottom() {
        let tall = rect(0, 0, 600, 1000)
        var ws = Workspace(bounds: tall, autoOrientAccordions: true, mode: .accordion)
        ws.insert(1)
        ws.insert(2)
        XCTAssertEqual(shape(ws.root), "a*[1 2]")
        XCTAssertEqual(ws.containerAxis(of: 2), .vertical)
        XCTAssertEqual(ws.layout().frames[2], rect(0, 30, 600, 970))
        var kept = Workspace(bounds: tall, autoOrientAccordions: false, mode: .accordion)
        kept.insert(1)
        XCTAssertEqual(shape(kept.root), "ah[1]", "without auto orientation the root stays horizontal")
        XCTAssertEqual(shape(Workspace(bounds: tall, autoOrientAccordions: true).root), "h[]", "tiles are unchanged")
    }

    func testAccordionInATallColumnPeeksTopAndBottom() {
        var ws = column()
        ws.setMode(.accordion)
        XCTAssertEqual(shape(ws.root), "h[1 a*[2 3]]")
        XCTAssertEqual(ws.layout().frames[2], rect(500, 0, 500, 570))
        XCTAssertEqual(ws.layout().frames[3], rect(500, 30, 500, 570))
    }

    func testResizingPastSquareFlipsAnAutoAccordion() {
        var ws = column()
        ws.setMode(.accordion)
        XCTAssertTrue(ws.resize(by: 200))
        XCTAssertEqual(ws.containerAxis(of: 3), .horizontal)
        XCTAssertEqual(ws.layout().frames[3], rect(330, 0, 670, 600))
    }

    func testAutoFollowsTheLaidOutRectWhenAMinimumHoldsTheColumnBack() {
        var ws = column()
        ws.setMode(.accordion)
        ws.minimumSizes = [1: CGSize(width: 450, height: 0)]
        XCTAssertTrue(ws.resize(by: 200))
        XCTAssertEqual(ws.containerAxis(of: 3), .vertical)
        XCTAssertEqual(ws.layout().frames[3], rect(450, 30, 550, 570))
    }

    func testExplicitOrientationIsNotChangedByLayout() {
        var ws = column(autoOrientAccordions: false)
        ws.setMode(.accordion)
        XCTAssertEqual(shape(ws.root), "h[1 av[2 3]]")
        ws.resize(by: 200)
        XCTAssertEqual(ws.containerAxis(of: 3), .vertical)
        XCTAssertEqual(ws.layout().frames[3], rect(300, 30, 700, 570))
    }

    func testAnOrientationChosenByCommandSurvivesTheSwitchToAccordion() {
        var ws = column()
        ws.setOrientation(.vertical)
        ws.setMode(.accordion)
        XCTAssertEqual(shape(ws.root), "h[1 av[2 3]]")
    }

    func testModeAndOrientationTogetherDoNotMergeHalfway() {
        var ws = column()
        ws.setLayout(.accordion, .horizontal)
        XCTAssertEqual(shape(ws.root), "h[1 ah[2 3]]")
    }

    func testSettingTheParentsOrientationMergesIntoIt() {
        var ws = column()
        ws.setOrientation(.horizontal)
        XCTAssertEqual(shape(ws.root), "h[1 2 3]")
    }

    func testNeighboursFollowTheResolvedAxis() {
        var ws = column()
        ws.setOrientation(.auto)
        ws.focus(2)
        XCTAssertEqual(ws.neighbor(of: 2, .down), 3)
        XCTAssertTrue(ws.resize(by: 200, along: .horizontal))
        XCTAssertEqual(ws.neighbor(of: 2, .right), 3)
        XCTAssertNil(ws.neighbor(of: 2, .down))
    }
}
