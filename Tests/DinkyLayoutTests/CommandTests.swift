import CoreGraphics
import XCTest
@testable import DinkyLayout

/// Three windows in 1000x600: 1 on the left, 2 above 3 on the right.
private func three() -> Workspace { workspace(3) }

final class NeighborTests: XCTestCase {
    func testLeftFromEitherRightWindowIsOne() {
        XCTAssertEqual(three().neighbor(of: 2, .left), 1)
        XCTAssertEqual(three().neighbor(of: 3, .left), 1)
    }

    func testUpAndDownWithinRightColumn() {
        XCTAssertEqual(three().neighbor(of: 3, .up), 2)
        XCTAssertEqual(three().neighbor(of: 2, .down), 3)
    }

    func testRightFromOnePrefersMostRecent() {
        var ws = three()
        ws.focus(2)
        ws.focus(1)
        XCTAssertEqual(ws.neighbor(of: 1, .right), 2)
        ws.focus(3)
        ws.focus(1)
        XCTAssertEqual(ws.neighbor(of: 1, .right), 3)
    }

    func testNoNeighbourAtEdges() {
        XCTAssertNil(three().neighbor(of: 1, .left))
        XCTAssertNil(three().neighbor(of: 1, .up))
        XCTAssertNil(three().neighbor(of: 2, .right))
        XCTAssertNil(three().neighbor(of: 3, .down))
    }

    func testFocusDirectionMovesFocus() {
        var ws = three()
        XCTAssertTrue(ws.focus(.left))
        XCTAssertEqual(ws.focused, 1)
        XCTAssertFalse(ws.focus(.left))
    }

    func testAccordionNeighboursFollowChildOrder() {
        var ws = workspace(3, mode: .accordion)
        XCTAssertEqual(ws.neighbor(of: 3, .left), 2)
        ws.focus(1)
        XCTAssertEqual(ws.neighbor(of: 1, .right), 2)
    }
}

final class SwapAndMoveTests: XCTestCase {
    func testMoveSwapsWithSiblingWindow() {
        var ws = workspace(3, bounds: rect(0, 0, 3000, 500))
        ws.focus(1)
        ws.move(.right)
        XCTAssertEqual(shape(ws.root), "h[2 1 3]")
    }

    func testMoveOutOfContainerAtEdge() {
        var ws = three()
        XCTAssertTrue(ws.move(.right))
        XCTAssertEqual(shape(ws.root), "h[1 2 3]")
    }

    func testMoveAcrossAxisLeavesContainer() {
        var ws = three()
        ws.move(.left)
        XCTAssertEqual(shape(ws.root), "h[1 3 2]")
    }

    func testMoveIntoSiblingContainer() {
        var ws = three()
        ws.focus(1)
        ws.move(.right)
        XCTAssertEqual(shape(ws.root), "v[2 3 1]")
    }

    func testMoveAtWorkspaceEdgeDoesNothing() {
        var ws = three()
        ws.focus(1)
        XCTAssertFalse(ws.move(.left))
        XCTAssertEqual(shape(ws.root), "h[1 v[2 3]]")
    }

    func testMoveAcrossRootWrapsIt() {
        var ws = workspace(2)
        ws.focus(1)
        ws.move(.down)
        XCTAssertEqual(shape(ws.root), "v[2 1]")
    }
}

final class JoinTests: XCTestCase {
    func testJoinWrapsNeighbourWindow() {
        var ws = workspace(3, bounds: rect(0, 0, 3000, 500))
        ws.focus(2)
        XCTAssertTrue(ws.join(.right))
        XCTAssertEqual(shape(ws.root), "h[1 v[2 3]]")
        XCTAssertEqual(ws.focused, 2)
    }

    func testJoinIntoNeighbourContainer() {
        var ws = three()
        ws.focus(1)
        ws.join(.right)
        XCTAssertEqual(shape(ws.root), "v[1 2 3]")
    }

    func testJoinFromInsideContainer() {
        var ws = three()
        ws.join(.left)
        XCTAssertEqual(shape(ws.root), "h[v[1 3] 2]")
    }

    func testJoinWithoutNeighbourFails() {
        var ws = three()
        ws.focus(1)
        XCTAssertFalse(ws.join(.left))
    }
}

final class ResizeTests: XCTestCase {
    func testResizeGrowsAlongParentAxis() {
        var ws = workspace(2)
        ws.focus(1)
        XCTAssertTrue(ws.resize(by: 100))
        assertRatios(ws.root.ratios, [0.6, 0.4])
        XCTAssertEqual(ws.layout().frames[1], rect(0, 0, 600, 600))
    }

    func testResizeUsesNearestParent() {
        var ws = three() // 3 sits in the right column, 600 tall
        ws.resize(by: 60)
        XCTAssertEqual(shape(ws.root), "h[1 v[2 3]]")
        assertRatios(ws.root.ratios, [0.5, 0.5])
        XCTAssertEqual(ws.layout().frames[3], rect(500, 240, 500, 360))
    }

    func testResizeClampsAtMinimum() {
        var ws = workspace(2)
        ws.resize(by: 5000)
        assertRatios(ws.root.ratios, [0.1, 0.9])
        XCTAssertFalse(ws.resize(by: 50))
        ws.resize(by: -5000)
        assertRatios(ws.root.ratios, [0.9, 0.1])
    }

    func testResizeKeepsEverySiblingAboveMinimum() {
        var ws = workspace(3, bounds: rect(0, 0, 3000, 500))
        ws.resize(by: 5000)
        assertRatios(ws.root.ratios, [0.1, 0.1, 0.8])
    }

    func testSingleWindowCannotResize() {
        var ws = workspace(1)
        XCTAssertFalse(ws.resize(by: 50))
    }
}
