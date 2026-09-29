import CoreGraphics
import XCTest
@testable import DinkyLayout

/// Four windows in 1000x600 as a 2x2 grid: h[v[1 3] v[2 4]].
private func grid() -> Workspace {
    var ws = workspace(2)
    ws.focus(1)
    ws.insert(3)
    ws.focus(2)
    ws.insert(4)
    return ws
}

final class ResizeToTests: XCTestCase {
    func testRightEdgeDragTakesFromTheRightNeighbourOnly() {
        var ws = workspace(3, bounds: rect(0, 0, 900, 300)) // h[1 2 3], 300 each
        XCTAssertTrue(ws.resize(1, to: CGSize(width: 450, height: 300), moving: [.right]))
        XCTAssertEqual(ws.layout().frames[1], rect(0, 0, 450, 300))
        XCTAssertEqual(ws.layout().frames[2], rect(450, 0, 150, 300))
        XCTAssertEqual(ws.layout().frames[3], rect(600, 0, 300, 300))
    }

    func testLeftEdgeDragTakesFromTheLeftNeighbour() {
        var ws = workspace(3, bounds: rect(0, 0, 900, 300))
        ws.resize(2, to: CGSize(width: 400, height: 300), moving: [.left])
        XCTAssertEqual(ws.layout().frames[1], rect(0, 0, 200, 300))
        XCTAssertEqual(ws.layout().frames[2], rect(200, 0, 400, 300))
        XCTAssertEqual(ws.layout().frames[3], rect(600, 0, 300, 300))
    }

    func testUnknownEdgeSplitsBetweenBothNeighbours() {
        var ws = workspace(3, bounds: rect(0, 0, 900, 300))
        ws.resize(2, to: CGSize(width: 400, height: 300))
        XCTAssertEqual(ws.layout().frames[1], rect(0, 0, 250, 300))
        XCTAssertEqual(ws.layout().frames[2], rect(250, 0, 400, 300))
    }

    func testCornerDragChangesBothAxes() {
        var ws = grid()
        ws.resize(1, to: CGSize(width: 600, height: 400), moving: [.right, .down])
        XCTAssertEqual(shape(ws.root), "h[v[1 3] v[2 4]]")
        XCTAssertEqual(ws.layout().frames[1], rect(0, 0, 600, 400))
        XCTAssertEqual(ws.layout().frames[3], rect(0, 400, 600, 200))
        XCTAssertEqual(ws.layout().frames[2], rect(600, 0, 400, 300))
    }

    func testDragBeyondTheMinimumRatioClamps() {
        var ws = workspace(2)
        ws.resize(1, to: CGSize(width: 990, height: 600), moving: [.right])
        assertRatios(ws.root.ratios, [0.9, 0.1])
        XCTAssertFalse(ws.resize(1, to: CGSize(width: 995, height: 600), moving: [.right]))
    }

    func testDragStopsAtTheNeighboursMinimumSize() {
        var ws = workspace(2)
        ws.minimumSizes[2] = CGSize(width: 300, height: 0)
        ws.resize(1, to: CGSize(width: 900, height: 600), moving: [.right])
        XCTAssertEqual(ws.layout().frames[1], rect(0, 0, 700, 600))
    }

    func testNestedColumnResizesThroughItsParent() {
        var ws = workspace(3) // h[1 v[2 3]]
        ws.resize(3, to: CGSize(width: 600, height: 300), moving: [.left])
        XCTAssertEqual(shape(ws.root), "h[1 v[2 3]]")
        assertRatios(ws.root.ratios, [0.4, 0.6])
        assertRatios(ws.root.container(at: [1]).ratios, [0.5, 0.5])
        XCTAssertEqual(ws.layout().frames[2], rect(400, 0, 600, 300))
    }

    func testEdgeWithoutANeighbourLooksFurtherUp() {
        var ws = grid()
        // 3 is the last of its column; its bottom edge has no neighbour, and nothing above runs vertically.
        XCTAssertFalse(ws.resize(3, to: CGSize(width: 500, height: 400), moving: [.down]))
        XCTAssertTrue(ws.resize(3, to: CGSize(width: 500, height: 400), moving: [.up]))
        XCTAssertEqual(ws.layout().frames[1], rect(0, 0, 500, 200))
    }

    func testWindowAloneAlongTheAxisDoesNothing() {
        var ws = workspace(2)
        let before = ws
        XCTAssertFalse(ws.resize(1, to: CGSize(width: 500, height: 400), moving: [.down]))
        XCTAssertFalse(ws.resize(1, to: CGSize(width: 500, height: 400), moving: [.up]))
        XCTAssertEqual(ws, before)
        var one = workspace(1)
        XCTAssertFalse(one.resize(1, to: CGSize(width: 700, height: 400)))
    }

    func testFixedLayoutDragIncludesEmptyCellsInItsExtent() {
        var horizontal = Workspace(bounds: rect(0, 0, 1000, 900), algorithm: .fixed(rows: 1, columns: 2, expand: .columns))
        horizontal.insert(1)
        XCTAssertTrue(horizontal.resize(1, to: CGSize(width: 600, height: 900), moving: [.right]))
        XCTAssertEqual(horizontal.layout().frames[1]?.width, 600)

        var vertical = Workspace(bounds: rect(0, 0, 1000, 900), algorithm: .fixed(rows: 3, columns: 1, expand: .rows))
        vertical.insert(1)
        XCTAssertTrue(vertical.resize(1, to: CGSize(width: 1000, height: 400), moving: [.down]))
        XCTAssertEqual(vertical.layout().frames[1]?.height, 400)
    }

    func testLayoutReproducesTheRequestedSizeWithGaps() {
        var ws = grid()
        ws.gaps = Gaps(all: 10)
        ws.resize(4, to: CGSize(width: 537, height: 213), moving: [.left, .up])
        let frame = ws.layout().frames[4]!
        XCTAssertEqual(frame.width, 537, accuracy: 1)
        XCTAssertEqual(frame.height, 213, accuracy: 1)
        XCTAssertEqual(frame.maxX, 990, accuracy: 1)
        XCTAssertEqual(frame.maxY, 590, accuracy: 1)
    }

    func testAccordionChildResizesItsAccordion() {
        var ws = workspace(3) // h[1 v[2 3]]
        ws.focus(2)
        ws.setMode(.accordion)
        XCTAssertEqual(shape(ws.root), "h[1 av[2 3]]")
        XCTAssertTrue(ws.resize(2, to: CGSize(width: 600, height: 570), moving: [.left]))
        assertRatios(ws.root.ratios, [0.4, 0.6])
        XCTAssertEqual(ws.layout().frames[3]?.width, 600)
        XCTAssertFalse(ws.resize(2, to: CGSize(width: 600, height: 300), moving: [.down]))
    }

    func testFullscreenDoesNothing() {
        var ws = workspace(2)
        ws.toggleFullscreen()
        XCTAssertFalse(ws.resize(2, to: CGSize(width: 300, height: 600), moving: [.left]))
        assertRatios(ws.root.ratios, [0.5, 0.5])
    }
}
