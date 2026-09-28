import XCTest
@testable import DinkyConfig

final class GapsTests: XCTestCase {
    private let builtIn = Monitor(name: "Built-in Retina Display", isMain: false, count: 2)
    private let dell = Monitor(name: "DELL U2723QE", isMain: true, count: 2)

    func testNumbersAndTables() throws {
        let gaps = try Config.parse("[gaps]\ninner = 6\nouter = 4\n").gaps
        XCTAssertEqual(gaps.inner, Inner(6))
        XCTAssertEqual(gaps.outer, Sides(4))
        let split = try Config.parse("[gaps]\ninner = { horizontal = 8, vertical = 6 }\nouter = { top = 44, left = 2 }\n").gaps
        XCTAssertEqual(split.inner, Inner(horizontal: 8, vertical: 6))
        XCTAssertEqual(split.outer, Sides(top: 44, bottom: 8, left: 2, right: 8), "sides left out keep the default")
        let dotted = try Config.parse("[gaps]\ninner.vertical = 0\nouter.top = 44\n").gaps
        XCTAssertEqual(dotted.inner, Inner(horizontal: 8, vertical: 0))
        XCTAssertEqual(dotted.outer.top, 44)
    }

    func testDisplayOverrides() throws {
        let config = try Config.parse("""
        [gaps]
        inner = 12
        outer = 8

        [display.main]
        gaps.outer.top = 44

        [display.built-in]
        gaps.outer.top = 10
        gaps.inner = 6
        """)
        XCTAssertEqual(config.displays.count, 2)
        XCTAssertEqual(config.gaps(for: dell), Gaps(inner: Inner(12), outer: Sides(top: 44, bottom: 8, left: 8, right: 8)))
        XCTAssertEqual(config.gaps(for: builtIn), Gaps(inner: Inner(6), outer: Sides(top: 10, bottom: 8, left: 8, right: 8)))
        XCTAssertEqual(config.gaps(for: Monitor(name: "LG", isMain: false, count: 3)), config.gaps, "no match, no change")
    }

    func testNamePatternBeatsMainAndLongerNameBeatsShorter() throws {
        let config = try Config.parse("""
        [display.main]
        gaps.outer.top = 1
        gaps.outer.bottom = 1
        [display.dell]
        gaps.outer.top = 2
        [display."dell u2723"]
        gaps.outer.top = 3
        """)
        let gaps = config.gaps(for: dell)
        XCTAssertEqual(gaps.outer.top, 3)
        XCTAssertEqual(gaps.outer.bottom, 1, "the overrides layer, each one only changes what it sets")
    }

    func testWorkspacesPerDisplay() throws {
        let config = try Config.parse("""
        workspaces = 4
        [display.secondary]
        workspaces = 1
        [display.dell]
        gaps.outer.top = 2
        """)
        XCTAssertEqual(config.workspaces(for: builtIn), 1, "secondary of two")
        XCTAssertEqual(config.workspaces(for: dell), 4, "a table without workspaces keeps the general count")
        XCTAssertEqual(config.workspaces(for: Monitor(name: "LG", isMain: false, count: 3)), 4)
        XCTAssertThrowsError(try Config.parse("[display.main]\nworkspaces = 0\n"))
    }

    func testPatterns() {
        XCTAssertTrue(MonitorPattern.main.matches(dell))
        XCTAssertFalse(MonitorPattern.main.matches(builtIn))
        XCTAssertTrue(MonitorPattern.secondary.matches(builtIn))
        XCTAssertFalse(MonitorPattern.secondary.matches(Monitor(name: "x", isMain: false, count: 3)))
        XCTAssertTrue(MonitorPattern.name("built-in").matches(builtIn))
        XCTAssertTrue(MonitorPattern.name("dell").matches(dell), "case-insensitive substring")
        XCTAssertFalse(MonitorPattern.name("built-in").matches(Monitor(name: "Apple Virtual Display", isMain: true, count: 1)))
    }

    func testBadGapsFail() {
        assertError("[gaps]\nouter.top = 'wide'\n", path: "gaps.outer.top", contains: "expected an integer")
        assertError("[gaps]\nouter.top = [{ monitor.main = 44 }, 8]\n", path: "gaps.outer.top", contains: "expected an integer")
        assertError("[gaps]\ninner.diagonal = 3\n", path: "gaps.inner.diagonal", contains: "unknown key")
        assertError("[display.main]\nborders.width = 2\n", path: "display.main.borders", contains: "unknown key")
        assertError("[display.main]\ngaps.outer.tpo = 2\n", path: "display.main.gaps.outer.tpo", contains: "unknown key")
        assertError("[display]\ngaps.outer.top = 2\n", path: "display.gaps.outer", contains: "unknown key")
    }

    private func assertError(_ toml: String, path: String, contains text: String, file: StaticString = #filePath, line: UInt = #line) {
        do {
            _ = try Config.parse(toml)
            XCTFail("expected an error for \(path)", file: file, line: line)
        } catch {
            XCTAssertEqual(error.path, path, "\(error)", file: file, line: line)
            XCTAssertTrue(error.description.contains(text), error.description, file: file, line: line)
        }
    }
}
