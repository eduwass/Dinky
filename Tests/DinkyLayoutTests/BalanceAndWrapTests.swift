import CoreGraphics
import XCTest
@testable import DinkyLayout

final class BalanceSizesTests: XCTestCase {
    func testEveryContainerGetsEqualRatios() {
        var ws = workspace(3)  // h[1 v[2 3]]
        ws.focus(3)
        ws.resize(by: 100)
        ws.focus(1)
        ws.resize(by: 200)
        ws.balanceSizes()
        assertRatios(ws.root.ratios, [0.5, 0.5])
        guard case .container(let inner) = ws.root.children[1] else { return XCTFail("expected a container") }
        assertRatios(inner.ratios, [0.5, 0.5])
    }

    func testKeepsShapeAndFocus() {
        var ws = workspace(4)
        ws.focus(2)
        ws.resize(by: 150)
        let before = shape(ws.root)
        ws.balanceSizes()
        XCTAssertEqual(shape(ws.root), before)
        XCTAssertEqual(ws.focused, 2)
    }

    func testThreeSiblingsGetAThirdEach() {
        var ws = workspace(0)
        for id: WindowID in 1...3 { ws.root.insert(.window(id), at: Int(id) - 1) }
        ws.focus(2)
        ws.resize(by: 300)
        ws.balanceSizes()
        assertRatios(ws.root.ratios, [1.0 / 3, 1.0 / 3, 1.0 / 3])
    }
}

final class InnerGapAxesTests: XCTestCase {
    func testHorizontalAndVerticalInnerGapsApplyToTheirAxis() {
        let gaps = Gaps(horizontal: 20, vertical: 10, top: 0, bottom: 0, left: 0, right: 0)
        let frames = workspace(3, bounds: rect(0, 0, 1020, 610), gaps: gaps).layout().frames  // h[1 v[2 3]]
        XCTAssertEqual(frames[1], rect(0, 0, 500, 610))
        XCTAssertEqual(frames[2], rect(520, 0, 500, 300))
        XCTAssertEqual(frames[3], rect(520, 310, 500, 300))
    }
}

final class WrapAroundTests: XCTestCase {
    func testEdgeWindowFollowsTheTree() {
        var ws = workspace(3)  // h[1 v[2 3]]
        XCTAssertEqual(ws.edgeWindow(.left), 1)
        ws.focus(2)
        XCTAssertEqual(ws.edgeWindow(.right), 2, "most recent child across the axis")
        XCTAssertEqual(ws.edgeWindow(.down), 3, "root runs across: its most recent child, then the bottom")
        ws.focus(1)
        XCTAssertEqual(ws.edgeWindow(.down), 1)
        XCTAssertNil(workspace(0).edgeWindow(.left))
    }

    func testFocusWrapsWithinTheWorkspace() {
        var ws = workspace(3)
        ws.focus(3)
        XCTAssertFalse(ws.focus(.right))
        XCTAssertTrue(ws.focus(.right, wrapping: true))
        XCTAssertEqual(ws.focused, 1)
        ws.focus(3)
        XCTAssertTrue(ws.focus(.down, wrapping: true))
        XCTAssertEqual(ws.focused, 2)
    }

    func testWrappingWithOneWindowDoesNothing() {
        var ws = workspace(1)
        XCTAssertFalse(ws.focus(.left, wrapping: true))
        XCTAssertEqual(ws.focused, 1)
    }
}

final class SwapByIDTests: XCTestCase {
    func testSwapTwoWindowsKeepsTilesAndFocus() {
        var ws = Workspace(bounds: CGRect(x: 0, y: 0, width: 1000, height: 600))
        ws.insert(1); ws.insert(2); ws.insert(3)
        ws.focus(2)
        let before = ws.layout().frames
        XCTAssertTrue(ws.swap(1, 3))
        let after = ws.layout().frames
        XCTAssertEqual(after[1], before[3])
        XCTAssertEqual(after[3], before[1])
        XCTAssertEqual(after[2], before[2])
        XCTAssertEqual(ws.focused, 2)
        XCTAssertFalse(ws.swap(1, 1))
        XCTAssertFalse(ws.swap(1, 99))
    }
}
