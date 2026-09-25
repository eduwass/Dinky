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
