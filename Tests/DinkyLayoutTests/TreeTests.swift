import CoreGraphics
import XCTest
@testable import DinkyLayout

final class InsertTests: XCTestCase {
    func testFirstWindowFillsRoot() {
        let ws = workspace(1)
        XCTAssertEqual(shape(ws.root), "h[1]")
        XCTAssertEqual(ws.focused, 1)
    }

    func testWideLeafSplitsSideBySide() {
        XCTAssertEqual(shape(workspace(2).root), "h[1 2]")
    }

    func testTallLeafSplitsTopAndBottom() {
        XCTAssertEqual(shape(workspace(2, bounds: rect(0, 0, 600, 1000)).root), "v[1 2]")
    }

    func testSquareLeafSplitsSideBySide() {
        XCTAssertEqual(shape(workspace(2, bounds: rect(0, 0, 800, 800)).root), "h[1 2]")
    }

    func testAlternatingSplitsNest() {
        XCTAssertEqual(shape(workspace(5).root), "h[1 v[2 h[3 v[4 5]]]]")
    }

    func testMatchingOrientationInsertsAsSibling() {
        // 1000x500 halves are square, so the third window splits side by side like its parent.
        XCTAssertEqual(shape(workspace(3, bounds: rect(0, 0, 1000, 500)).root), "h[1 2 3]")
    }

    func testNewWindowGoesAfterFocused() {
        var ws = workspace(3, bounds: rect(0, 0, 3000, 500))
        ws.focus(1)
        ws.insert(4)
        XCTAssertEqual(shape(ws.root), "h[1 4 2 3]")
        XCTAssertEqual(ws.focused, 4)
    }

    func testInsertSplitsFiftyFifty() {
        assertRatios(workspace(2).root.ratios, [0.5, 0.5])
    }

    func testSiblingInsertDividesRatiosProportionally() {
        var ws = workspace(2, bounds: rect(0, 0, 3000, 500))
        ws.focus(1)
        ws.resize(by: 300) // [0.6, 0.4]
        ws.insert(3)
        assertRatios(ws.root.ratios, [0.4, 1.0 / 3, 0.4 * 2 / 3])
    }

    func testInsertIntoAccordionIsAlwaysASibling() {
        var ws = workspace(2, mode: .accordion)
        ws.insert(3)
        XCTAssertEqual(shape(ws.root), "ah[1 2 3]")
    }

    func testInsertingKnownWindowIsIgnored() {
        var ws = workspace(2)
        ws.insert(1)
        XCTAssertEqual(shape(ws.root), "h[1 2]")
    }
}

final class FixedLayoutTests: XCTestCase {
    func testEmptyCellsKeepTheirFrames() {
        var ws = Workspace(bounds: rect(0, 0, 1200, 900), algorithm: .fixed(rows: 3, columns: 2, expand: .columns))
        ws.insert(1)
        XCTAssertEqual(ws.layout().frames[1], rect(0, 0, 600, 300))
        XCTAssertEqual(ws.edgeWindow(.right), 1, "an empty boundary column must not hide occupied cells")
        XCTAssertEqual(ws.edgeWindow(.down), 1)
        for id in 2...5 { ws.insert(WindowID(id)) }
        XCTAssertEqual(ws.windows.count, 5)
        XCTAssertEqual(ws.layout().frames[5], rect(0, 600, 600, 300))
        XCTAssertEqual(ws.layout().frames.count, 5)
        ws.insert(6)
        XCTAssertEqual(ws.layout().frames[6], rect(600, 600, 600, 300))
        ws.remove(2)
        XCTAssertEqual(ws.layout().frames[1], rect(0, 0, 600, 300))
        XCTAssertEqual(ws.layout().frames[6], rect(600, 600, 600, 300))
        ws.insert(7)
        XCTAssertEqual(ws.layout().frames[7], rect(600, 0, 600, 300))
    }

    func testDefaultOneByOneAndColumnExpansion() {
        var ws = Workspace(bounds: rect(0, 0, 1200, 900), algorithm: .fixed(rows: 1, columns: 1, expand: .columns))
        ws.insert(1)
        XCTAssertEqual(ws.layout().frames[1], rect(0, 0, 1200, 900))
        ws.insert(2)
        XCTAssertEqual(ws.layout().frames[1], rect(0, 0, 600, 900))
        XCTAssertEqual(ws.layout().frames[2], rect(600, 0, 600, 900))
        ws.remove(2)
        XCTAssertEqual(ws.layout().frames[1], rect(0, 0, 1200, 900))
        ws.remove(1)
        ws.insert(3)
        XCTAssertEqual(ws.layout().frames[3], rect(0, 0, 1200, 900))
    }

    func testRowExpansionAndAccordionOverflow() {
        var rows = Workspace(bounds: rect(0, 0, 1200, 900), algorithm: .fixed(rows: 1, columns: 2, expand: .rows))
        for id in 1...3 { rows.insert(WindowID(id)) }
        XCTAssertEqual(rows.layout().frames[3], rect(0, 450, 600, 450))
        rows.remove(3)
        XCTAssertEqual(rows.layout().frames[1], rect(0, 0, 600, 900))

        var stacked = Workspace(bounds: rect(0, 0, 1200, 900), algorithm: .fixed(rows: 3, columns: 2, expand: .accordion))
        for id in 1...8 { stacked.insert(WindowID(id)) }
        XCTAssertEqual(stacked.windows.count, 8)
        XCTAssertEqual(stacked.container(of: 7)?.mode, .accordion)
        XCTAssertEqual(stacked.container(of: 8)?.mode, .accordion)
        stacked.remove(7)
        XCTAssertTrue(stacked.contains(8))
        stacked.remove(8)
        stacked.remove(6)
        stacked.insert(9)
        XCTAssertEqual(stacked.layout().frames[9], rect(600, 600, 600, 300))
    }

    func testManualResizeSurvivesFillingAHole() {
        var ws = Workspace(bounds: rect(0, 0, 1200, 900), algorithm: .fixed(rows: 2, columns: 2, expand: .columns))
        ws.insert(1)
        ws.focus(1)
        XCTAssertTrue(ws.resize(by: 120, along: .horizontal))
        let widths = ws.root.ratios
        ws.insert(2)
        assertRatios(ws.root.ratios, widths)
    }

    func testChangingTemplateKeepsFocus() {
        var ws = workspace(4)
        ws.focus(1)
        ws.setAlgorithm(.fixed(rows: 3, columns: 2, expand: .columns))
        XCTAssertEqual(ws.focused, 1)
        XCTAssertEqual(ws.layout().frames[4], rect(500, 200, 500, 200))
        ws.setAlgorithm(.dwindle, mode: .accordion)
        XCTAssertEqual(ws.windows.count, 4)
        XCTAssertEqual(ws.root.mode, .accordion)
        XCTAssertEqual(ws.focused, 1)
    }

    func testChangingDwindleToAccordionReconfiguresExistingWindows() {
        var ws = workspace(3)
        ws.setAlgorithm(.dwindle, mode: .accordion)
        XCTAssertEqual(ws.root.mode, .accordion)
        XCTAssertEqual(ws.windows.count, 3)
        ws.setAlgorithm(.dwindle, mode: .tiles)
        XCTAssertEqual(ws.root.mode, .tiles)
    }

    func testMoveSwapsCellsAndCanFillAHoleWithoutBreakingTheTemplate() {
        var ws = Workspace(bounds: rect(0, 0, 900, 600), algorithm: .fixed(rows: 2, columns: 3, expand: .columns))
        ws.insert(1)
        ws.insert(2)
        ws.focus(2)
        XCTAssertTrue(ws.move(.left))
        XCTAssertEqual(ws.layout().frames[2], rect(0, 0, 300, 300))
        XCTAssertEqual(ws.layout().frames[1], rect(300, 0, 300, 300))
        XCTAssertTrue(ws.move(.down))
        XCTAssertEqual(ws.layout().frames[2], rect(0, 300, 300, 300))
        ws.insert(3)
        XCTAssertEqual(ws.layout().frames[3], rect(0, 0, 300, 300))
    }

    func testEmptyEditedTreeRestoresTheFixedTemplate() {
        var ws = Workspace(bounds: rect(0, 0, 1200, 900), algorithm: .fixed(rows: 3, columns: 2, expand: .columns))
        ws.insert(1)
        ws.flatten()
        ws.remove(1)
        ws.insert(2)
        XCTAssertEqual(ws.layout().frames[2], rect(0, 0, 600, 300))
    }

    func testMovingOutOfOverflowReclaimsEmptyRow() {
        var ws = Workspace(bounds: rect(0, 0, 1200, 900), algorithm: .fixed(rows: 1, columns: 2, expand: .rows))
        for id in 1...3 { ws.insert(WindowID(id)) }
        ws.remove(2)
        ws.focus(3)
        XCTAssertTrue(ws.move(.right))
        XCTAssertTrue(ws.move(.up))
        XCTAssertEqual(ws.layout().frames[1], rect(0, 0, 600, 900))
        XCTAssertEqual(ws.layout().frames[3], rect(600, 0, 600, 900))
    }
}

final class RemoveTests: XCTestCase {
    func testRemoveRedistributesProportionally() {
        var ws = workspace(3, bounds: rect(0, 0, 3000, 500))
        ws.focus(1)
        ws.resize(by: 500) // 1 grows to 1/3 + 1/6
        ws.remove(3)
        assertRatios(ws.root.ratios, [0.5 / (0.5 + 0.25), 0.25 / (0.5 + 0.25)])
    }

    func testRemoveCollapsesSingleChildContainer() {
        var ws = workspace(3)
        ws.remove(2)
        XCTAssertEqual(shape(ws.root), "h[1 3]")
        assertRatios(ws.root.ratios, [0.5, 0.5])
    }

    func testRemoveSplicesSameOrientationContainerKeepingOrder() {
        var ws = workspace(4) // h[1 v[2 h[3 4]]]
        ws.remove(2)
        XCTAssertEqual(shape(ws.root), "h[1 3 4]")
        assertRatios(ws.root.ratios, [0.5, 0.25, 0.25])
    }

    func testRemoveUnwrapsRoot() {
        var ws = workspace(3) // h[1 v[2 3]]
        ws.remove(1)
        XCTAssertEqual(shape(ws.root), "v[2 3]")
    }

    func testRemoveLastWindowLeavesEmptyRoot() {
        var ws = workspace(1)
        ws.remove(1)
        XCTAssertEqual(ws.windows, [])
        XCTAssertNil(ws.focused)
    }

    func testRemovingFocusedFocusesWindowInItsPlace() {
        var ws = workspace(3, bounds: rect(0, 0, 3000, 500))
        ws.focus(2)
        ws.remove(2)
        XCTAssertEqual(ws.focused, 3)
    }

    func testRemovingOtherWindowKeepsFocus() {
        var ws = workspace(3)
        ws.remove(1)
        XCTAssertEqual(ws.focused, 3)
    }
}

final class FlattenAndModeTests: XCTestCase {
    func testFlattenCollapsesToOneContainer() {
        var ws = workspace(5)
        ws.flatten()
        XCTAssertEqual(shape(ws.root), "h[1 2 3 4 5]")
        assertRatios(ws.root.ratios, Array(repeating: 0.2, count: 5))
        XCTAssertEqual(ws.focused, 5)
    }

    func testSetModeChangesFocusedParent() {
        var ws = workspace(3)
        ws.setMode(.accordion)
        XCTAssertEqual(shape(ws.root), "h[1 av[2 3]]")
    }
}

final class ReplaceTests: XCTestCase {
    func testReplaceKeepsPlaceSizeAndFocus() {
        var ws = workspace(3)
        ws.focus(2)
        ws.toggleFullscreen()
        let before = ws.layout()
        ws.replace(2, with: 9)
        XCTAssertEqual(shape(ws.root), "h[1 v[9 3]]")
        XCTAssertEqual(ws.focused, 9)
        XCTAssertEqual(ws.fullscreen, 9)
        XCTAssertEqual(ws.layout().frames[9], before.frames[2])
    }

    func testReplaceIgnoresMissingOrPresentWindows() {
        var ws = workspace(2)
        ws.replace(7, with: 9)
        ws.replace(1, with: 2)
        XCTAssertEqual(shape(ws.root), "h[1 2]")
    }
}
