import DinkyLayout
import XCTest
@testable import DinkyCommands

private func parse(_ s: String) throws -> Command { try Command.parse(s) }

final class FocusParseTests: XCTestCase {
    func testDefaultsAreWorkspaceAndStop() throws {
        XCTAssertEqual(try parse("focus left"), .focus(.left, boundaries: .workspace, action: .stop))
    }

    func testBoundariesFlagsInAnyOrder() throws {
        XCTAssertEqual(try parse("focus --boundaries all-monitors-outer-frame left"),
                       .focus(.left, boundaries: .allMonitorsOuterFrame, action: .stop))
        XCTAssertEqual(try parse("focus down --boundaries-action wrap-around-the-workspace"),
                       .focus(.down, boundaries: .workspace, action: .wrapAroundTheWorkspace))
        XCTAssertEqual(try parse("focus --boundaries-action fail --boundaries workspace up"),
                       .focus(.up, boundaries: .workspace, action: .fail))
        XCTAssertEqual(try parse("focus right --boundaries all-monitors-outer-frame --boundaries-action wrap-around-all-monitors"),
                       .focus(.right, boundaries: .allMonitorsOuterFrame, action: .wrapAroundAllMonitors))
        XCTAssertEqual(try parse("focus --wrap-around left"), .focus(.left, boundaries: .workspace, action: .wrapAroundTheWorkspace))
    }

    func testBadFocusFlags() {
        for s in ["focus", "focus --boundaries left", "focus left --boundaries screen", "focus left --boundaries-action loop",
                  "focus left right", "focus left --frobnicate"] {
            XCTAssertThrowsError(try parse(s), s)
        }
    }

    func testWrapAroundAllMonitorsNeedsTheOuterFrame() {
        XCTAssertThrowsError(try parse("focus left --boundaries-action wrap-around-all-monitors")) { error in
            XCTAssertTrue("\(error)".contains("all-monitors-outer-frame"), "\(error)")
        }
    }

    func testFocusMonitor() throws {
        for word in ["left", "right", "up", "down", "next", "prev"] {
            XCTAssertEqual(try parse("focus-monitor \(word)"), .focusMonitor(MonitorTarget(rawValue: word)!))
        }
        XCTAssertEqual(MonitorTarget.up.direction, .up)
        XCTAssertNil(MonitorTarget.next.direction)
        XCTAssertThrowsError(try parse("focus-monitor"))
        XCTAssertThrowsError(try parse("focus-monitor main"))
        XCTAssertEqual(try parse("focus-monitor 2"), .focusMonitorNumber(2))
        XCTAssertThrowsError(try parse("focus-monitor 0"))
    }

    func testBalanceSizes() throws {
        XCTAssertEqual(try parse("balance-sizes"), .balanceSizes)
        XCTAssertThrowsError(try parse("balance-sizes --workspace 2"))
    }
}
