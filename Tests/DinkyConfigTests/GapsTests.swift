import XCTest
@testable import DinkyConfig

final class GapsTests: XCTestCase {
    private let builtIn = Monitor(name: "Built-in Retina Display", isMain: false, count: 2)
    private let dell = Monitor(name: "DELL U2723QE", isMain: true, count: 2)

    func testPlainNumbersStillWork() throws {
        let gaps = try Config.parse("[gaps]\ninner = 6\nouter = 4\n").gaps
        XCTAssertEqual(gaps.inner, Inner(6))
        XCTAssertEqual(gaps.outer, Sides(4))
        let sides = try Config.parse("[gaps]\nouter = { top = 8, left = 2 }\n").gaps.outer
        XCTAssertEqual(sides.top.value(for: dell), 8)
        XCTAssertEqual(sides.left.value(for: dell), 2)
        XCTAssertEqual(sides.bottom.value(for: dell), 0)
    }

    func testAeroSpaceGapsSection() throws {
        let gaps = try Config.parse("""
        [gaps]
        inner.horizontal = 8
        inner.vertical = 6
        outer.left = 8
        outer.bottom = 8
        outer.top = [ { monitor."built-in" = 12 }, { monitor."main" = 44 }, 40 ]
        outer.right = 8
        """).gaps
        XCTAssertEqual(gaps.inner.horizontal, 8)
        XCTAssertEqual(gaps.inner.vertical, 6)
        XCTAssertEqual(gaps.outer.top.value(for: builtIn), 12)
        XCTAssertEqual(gaps.outer.top.value(for: dell), 44)
        XCTAssertEqual(gaps.outer.top.value(for: Monitor(name: "LG", isMain: false, count: 3)), 40)
        XCTAssertEqual(gaps.outer.right.value(for: builtIn), 8)
    }

    func testInnerAcceptsAPerMonitorList() throws {
        let inner = try Config.parse("[gaps]\ninner = [{ monitor.secondary = 2 }, 10]\n").gaps.inner
        XCTAssertEqual(inner.horizontal.value(for: builtIn), 2)
        XCTAssertEqual(inner.vertical.value(for: builtIn), 2)
        XCTAssertEqual(inner.horizontal.value(for: dell), 10)
    }

    func testFirstMatchWinsAndNoMatchIsZero() throws {
        let top = try Config.parse("[gaps]\nouter.top = [{ monitor.main = 1 }, { monitor.dell = 2 }]\n").gaps.outer.top
        XCTAssertEqual(top.value(for: dell), 1)
        XCTAssertEqual(top.value(for: builtIn), 0)
        let early = try Config.parse("[gaps]\nouter.top = [5, { monitor.main = 1 }]\n").gaps.outer.top
        XCTAssertEqual(early.value(for: dell), 5, "a bare number matches every display")
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

    func testBadPerMonitorValuesFail() {
        assertError("[gaps]\nouter.top = [{ monitor = 12 }]\n", path: "gaps.outer.top[0].monitor", contains: "expected a table")
        assertError("[gaps]\nouter.top = [{ monitor.main = 'wide' }]\n", path: "gaps.outer.top[0].monitor.main", contains: "expected an integer")
        assertError("[gaps]\nouter.top = [{ screen.main = 1 }]\n", path: "gaps.outer.top[0]", contains: "monitor.<pattern>")
        assertError("[gaps]\nouter.top = [{ monitor.main = 1, monitor.dell = 2 }]\n", path: "gaps.outer.top[0]", contains: "monitor.<pattern>")
        assertError("[gaps]\nouter.top = ['main']\n", path: "gaps.outer.top", contains: "expected a number or a list")
        assertError("[gaps]\ninner.diagonal = 3\n", path: "gaps.inner.diagonal", contains: "unknown key")
    }

    func testAfterStartupCommand() throws {
        XCTAssertEqual(Config.default.afterStartupCommand, [])
        let config = try Config.parse("after-startup-command = ['exec-and-forget brew services restart sketchybar']\n")
        XCTAssertEqual(config.afterStartupCommand, ["exec-and-forget brew services restart sketchybar"])
        assertError("after-startup-command = [1]\n", path: "after-startup-command", contains: "list of strings")
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
