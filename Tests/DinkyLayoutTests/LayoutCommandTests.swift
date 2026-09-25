import CoreGraphics
import XCTest
@testable import DinkyLayout

/// i3's answer for `move` from every window of h[1 v[2 3]] in every direction.
final class MoveEveryDirectionTests: XCTestCase {
    func testEveryDirectionFromEveryWindow() {
        let expected: [WindowID: [Direction: String]] = [
            1: [.left: "h[1 v[2 3]]", .right: "v[2 3 1]", .up: "v[1 2 3]", .down: "v[2 3 1]"],
            2: [.left: "h[1 2 3]", .right: "h[1 3 2]", .up: "v[2 h[1 3]]", .down: "h[1 v[3 2]]"],
            3: [.left: "h[1 3 2]", .right: "h[1 2 3]", .up: "h[1 v[3 2]]", .down: "v[h[1 2] 3]"],
        ]
        for (id, moves) in expected {
            for (direction, shapeAfter) in moves {
                var ws = workspace(3)
                ws.focus(id)
                ws.move(direction)
                XCTAssertEqual(shape(ws.root), shapeAfter, "move \(direction) from \(id)")
                XCTAssertEqual(ws.focused, id, "move \(direction) from \(id) keeps focus")
            }
        }
    }

    func testMovingOutAtTheEdgeKeepsTheOtherWindowsShares() {
        var ws = workspace(3)
        ws.focus(1)
        ws.move(.up)
        assertRatios(ws.root.ratios, [0.5, 0.25, 0.25])
    }
}

final class FullscreenExitTests: XCTestCase {
    func testFocusingAnotherWindowEndsFullscreen() {
        var ws = workspace(3)
        ws.toggleFullscreen()
        ws.focus(3)
        XCTAssertEqual(ws.fullscreen, 3)
        ws.focus(1)
        XCTAssertNil(ws.fullscreen)
    }

    func testLayoutCommandsEndFullscreenAndKeepTheTree() {
        let commands: [(String, (inout Workspace) -> Void)] = [
            ("setMode", { $0.setMode(.tiles) }), ("move", { $0.move(.right) }),
            ("join", { $0.join(.down) }), ("resize", { $0.resize(by: 0) }), ("flatten", { $0.flatten() }),
        ]
        for (name, command) in commands {
            var ws = workspace(3, bounds: rect(0, 0, 3000, 500))
            ws.toggleFullscreen()
            command(&ws)
            XCTAssertNil(ws.fullscreen, name)
        }
    }
}

final class AccordionCommandTests: XCTestCase {
    func testFocusCyclesThroughAccordionOrderAndBringsItToFront() {
        var ws = workspace(3, mode: .accordion)
        XCTAssertTrue(ws.focus(.left))
        XCTAssertEqual(ws.focused, 2)
        XCTAssertEqual(ws.layout().order.first, 2)
        XCTAssertTrue(ws.focus(.left))
        XCTAssertEqual(ws.layout().order.first, 1)
        XCTAssertFalse(ws.focus(.left))
        XCTAssertTrue(ws.focus(.right))
        XCTAssertEqual(ws.layout().order.first, 2)
    }

    func testTogglingBackToTilesRestoresRatios() {
        var ws = workspace(3, bounds: rect(0, 0, 3000, 500))
        ws.resize(by: 300)
        let tiles = ws.layout()
        ws.setMode(.accordion)
        XCTAssertEqual(ws.container(of: 3)?.mode, .accordion)
        XCTAssertNotEqual(ws.layout(), tiles)
        ws.setMode(.tiles)
        XCTAssertEqual(ws.container(of: 3)?.mode, .tiles)
        XCTAssertEqual(ws.layout(), tiles)
    }

    func testContainerOfUnknownWindowIsNil() {
        XCTAssertNil(workspace(1).container(of: 9))
    }

    func testContainerOfNestedWindow() {
        let ws = workspace(3) // 1 on the left, 2 above 3 on the right
        XCTAssertEqual(ws.container(of: 1)?.orientation, .horizontal)
        XCTAssertEqual(ws.container(of: 3)?.orientation, .vertical)
        XCTAssertEqual(ws.container(of: 3).map { shape($0) }, "v[2 3]")
    }
}

final class ResizeAxisTests: XCTestCase {
    func testWidthResizesTheNearestHorizontalContainer() {
        var ws = workspace(3) // 3 sits in the right column
        XCTAssertTrue(ws.resize(by: 100, along: .horizontal))
        assertRatios(ws.root.ratios, [0.4, 0.6])
        assertRatios(ws.root.container(at: [1]).ratios, [0.5, 0.5])
    }

    func testHeightResizesTheColumn() {
        var ws = workspace(3)
        XCTAssertTrue(ws.resize(by: 60, along: .vertical))
        assertRatios(ws.root.ratios, [0.5, 0.5])
        assertRatios(ws.root.container(at: [1]).ratios, [0.4, 0.6])
    }

    func testNoContainerAlongTheAxis() {
        var ws = workspace(2)
        XCTAssertFalse(ws.resize(by: 50, along: .vertical))
    }
}

final class MinimumSizeTests: XCTestCase {
    func testTileGrowsToItsMinimumAtItsSiblingsExpense() {
        var ws = workspace(2)
        ws.minimumSizes = [1: CGSize(width: 700, height: 0)]
        XCTAssertEqual(ws.layout().frames[1], rect(0, 0, 700, 600))
        XCTAssertEqual(ws.layout().frames[2], rect(700, 0, 300, 600))
        assertRatios(ws.root.ratios, [0.5, 0.5])
    }

    func testMinimumsThatDoNotFitAreIgnored() {
        var ws = workspace(2)
        ws.minimumSizes = [1: CGSize(width: 700, height: 0), 2: CGSize(width: 700, height: 0)]
        XCTAssertEqual(ws.layout().frames[1], rect(0, 0, 500, 600))
    }

    func testNestedMinimumWidensItsColumn() {
        var ws = workspace(3)
        ws.minimumSizes = [3: CGSize(width: 800, height: 0)]
        XCTAssertEqual(ws.layout().frames[1], rect(0, 0, 200, 600))
        XCTAssertEqual(ws.layout().frames[2], rect(200, 0, 800, 300))
    }

    func testSiblingsGiveInProportionAndStopAtTheirOwnMinimum() {
        XCTAssertEqual(fit([1000, 1000, 1000], minimums: [2000, 0, 0], total: 3000), [2000, 500, 500])
        XCTAssertEqual(fit([1000, 1000, 1000], minimums: [2000, 800, 0], total: 3000), [2000, 800, 200])
        XCTAssertEqual(fit([600, 300, 100], minimums: [0, 0, 200], total: 1000), [533.3333333333334, 266.6666666666667, 200])
    }

    func testResizeStopsAtTheMinimum() {
        var ws = workspace(2) // 2 focused
        ws.minimumSizes = [2: CGSize(width: 450, height: 0)]
        XCTAssertTrue(ws.resize(by: -100))
        XCTAssertEqual(ws.layout().frames[2]?.width, 450)
        XCTAssertFalse(ws.resize(by: -100))
    }

    func testResizeTheSiblingsMinimumSwallowsIsUndone() {
        var ws = workspace(2)
        ws.focus(1)
        ws.minimumSizes = [2: CGSize(width: 500, height: 0)]
        XCTAssertFalse(ws.resize(by: 100))
        assertRatios(ws.root.ratios, [0.5, 0.5])
    }

    func testAccordionMinimumIncludesThePeekingNeighbours() {
        let accordion = Node.container(Container(.horizontal, .accordion, [.window(1), .window(2), .window(3)]))
        XCTAssertEqual(accordion.minimumExtent(.horizontal, gap: 8, padding: 30, [2: CGSize(width: 400, height: 0)]), 460)
    }
}
