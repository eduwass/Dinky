import CoreGraphics
import XCTest
@testable import DinkyLayout

final class TilesTests: XCTestCase {
    func testTilesWithoutGaps() {
        let expected: [[WindowID: CGRect]] = [
            [1: rect(0, 0, 1000, 600)],
            [1: rect(0, 0, 500, 600), 2: rect(500, 0, 500, 600)],
            [1: rect(0, 0, 500, 600), 2: rect(500, 0, 500, 300), 3: rect(500, 300, 500, 300)],
            [1: rect(0, 0, 500, 600), 2: rect(500, 0, 500, 300), 3: rect(500, 300, 250, 300), 4: rect(750, 300, 250, 300)],
            [1: rect(0, 0, 500, 600), 2: rect(500, 0, 500, 300), 3: rect(500, 300, 250, 300),
             4: rect(750, 300, 250, 150), 5: rect(750, 450, 250, 150)],
        ]
        for (i, frames) in expected.enumerated() {
            XCTAssertEqual(workspace(i + 1).layout().frames, frames, "\(i + 1) windows")
        }
    }

    func testTilesWithGaps() {
        // Outer gaps of 10 leave (10, 10, 990, 590); inner gaps of 10 sit between siblings.
        let bounds = rect(0, 0, 1010, 610), gaps = Gaps(all: 10)
        let expected: [[WindowID: CGRect]] = [
            [1: rect(10, 10, 990, 590)],
            [1: rect(10, 10, 490, 590), 2: rect(510, 10, 490, 590)],
            [1: rect(10, 10, 490, 590), 2: rect(510, 10, 490, 290), 3: rect(510, 310, 490, 290)],
            [1: rect(10, 10, 490, 590), 2: rect(510, 10, 490, 290), 3: rect(510, 310, 240, 290), 4: rect(760, 310, 240, 290)],
            [1: rect(10, 10, 490, 590), 2: rect(510, 10, 490, 290), 3: rect(510, 310, 240, 290),
             4: rect(760, 310, 240, 140), 5: rect(760, 460, 240, 140)],
        ]
        for (i, frames) in expected.enumerated() {
            XCTAssertEqual(workspace(i + 1, bounds: bounds, gaps: gaps).layout().frames, frames, "\(i + 1) windows")
        }
    }

    func testUnevenOuterGaps() {
        let gaps = Gaps(horizontal: 0, vertical: 0, top: 30, bottom: 10, left: 5, right: 15)
        XCTAssertEqual(workspace(1, gaps: gaps).layout().frames[1], rect(5, 30, 980, 560))
    }

    func testEdgesAreRoundedWithoutHoles() {
        var ws = workspace(3, bounds: rect(0, 0, 3000, 500))
        ws.bounds = rect(0, 0, 1000, 500)
        let f = ws.layout().frames
        XCTAssertEqual([f[1]!.width, f[2]!.width, f[3]!.width], [333, 334, 333])
        XCTAssertEqual(f[1]!.maxX, f[2]!.minX)
        XCTAssertEqual(f[2]!.maxX, f[3]!.minX)
    }

    func testChangingBoundsKeepsTopology() {
        var ws = workspace(5)
        let before = ws.root
        ws.bounds = rect(0, 0, 600, 1000)
        _ = ws.layout()
        XCTAssertEqual(ws.root, before)
        XCTAssertEqual(ws.layout().frames[1], rect(0, 0, 300, 1000))
    }

    func testLayoutIsDeterministic() {
        let a = workspace(5, gaps: Gaps(all: 8)), b = workspace(5, gaps: Gaps(all: 8))
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.layout(), b.layout())
        XCTAssertEqual(a.layout(), a.layout())
    }

    func testFocusedWindowIsFrontmost() {
        var ws = workspace(5)
        ws.focus(2)
        XCTAssertEqual(ws.layout().order.first, 2)
        XCTAssertEqual(Set(ws.layout().order), [1, 2, 3, 4, 5])
    }
}

final class AccordionTests: XCTestCase {
    func testSingleChildFillsRect() {
        XCTAssertEqual(workspace(1, mode: .accordion).layout().frames[1], rect(0, 0, 1000, 600))
    }

    func testMiddleFocusedNeighboursPeekOnBothSides() {
        var ws = workspace(3, mode: .accordion)
        ws.focus(2)
        let layout = ws.layout()
        XCTAssertEqual(layout.frames, [1: rect(0, 0, 970, 600), 2: rect(30, 0, 940, 600), 3: rect(30, 0, 970, 600)])
        XCTAssertEqual(layout.order, [2, 1, 3])
    }

    func testLastFocusedPreviousPeeksOnLeft() {
        let layout = workspace(3, mode: .accordion).layout() // 3 is focused
        XCTAssertEqual(layout.frames, [1: rect(0, 0, 970, 600), 2: rect(0, 0, 940, 600), 3: rect(30, 0, 970, 600)])
        XCTAssertEqual(layout.order, [3, 2, 1])
    }

    func testFirstFocusedNextPeeksOnRight() {
        var ws = workspace(3, mode: .accordion)
        ws.focus(1)
        let layout = ws.layout()
        XCTAssertEqual(layout.frames, [1: rect(0, 0, 970, 600), 2: rect(60, 0, 940, 600), 3: rect(30, 0, 970, 600)])
        XCTAssertEqual(layout.order, [1, 2, 3])
    }

    func testVerticalAccordionPeeksAlongHeight() {
        var ws = workspace(2, bounds: rect(0, 0, 600, 1000), mode: .accordion)
        ws.focus(1)
        XCTAssertEqual(ws.layout().frames, [1: rect(0, 0, 600, 970), 2: rect(0, 30, 600, 970)])
    }

    func testAccordionRespectsOuterGaps() {
        let ws = workspace(2, bounds: rect(0, 0, 1020, 620), gaps: Gaps(all: 10), mode: .accordion)
        XCTAssertEqual(ws.layout().frames, [1: rect(10, 10, 970, 600), 2: rect(40, 10, 970, 600)])
    }

    func testStackingOrderIsStableAcrossFocusChanges() {
        var ws = workspace(5, mode: .accordion)
        ws.focus(3)
        XCTAssertEqual(ws.layout().order, [3, 2, 4, 1, 5])
        ws.focus(1)
        ws.focus(3)
        XCTAssertEqual(ws.layout().order, [3, 2, 4, 1, 5])
    }

    func testAccordionRemembersTopChildWhenFocusLeaves() {
        var ws = workspace(3) // h[1 v[2 3]]
        ws.focus(2)
        ws.setMode(.accordion)
        ws.focus(1)
        XCTAssertEqual(ws.layout().order, [1, 2, 3])
    }
}

final class FullscreenTests: XCTestCase {
    func testFullscreenWindowFillsBoundsMinusOuterGaps() {
        var ws = workspace(3, bounds: rect(0, 0, 1010, 610), gaps: Gaps(all: 10))
        ws.focus(2)
        ws.toggleFullscreen()
        let layout = ws.layout()
        XCTAssertEqual(layout.frames[2], rect(10, 10, 990, 590))
        XCTAssertEqual(layout.order.first, 2)
    }

    func testFullscreenLeavesTreeAndOtherFramesAlone() {
        var ws = workspace(3)
        let root = ws.root, frames = ws.layout().frames
        ws.toggleFullscreen()
        XCTAssertEqual(ws.root, root)
        XCTAssertEqual(ws.layout().frames[1], frames[1])
        XCTAssertEqual(ws.layout().frames[2], frames[2])
    }

    func testToggleTwiceRestores() {
        var ws = workspace(3)
        let layout = ws.layout()
        ws.toggleFullscreen()
        XCTAssertEqual(ws.fullscreen, 3)
        ws.toggleFullscreen()
        XCTAssertNil(ws.fullscreen)
        XCTAssertEqual(ws.layout(), layout)
    }

    func testRemovingFullscreenWindowClearsIt() {
        var ws = workspace(3)
        ws.toggleFullscreen()
        ws.remove(3)
        XCTAssertNil(ws.fullscreen)
    }
}
