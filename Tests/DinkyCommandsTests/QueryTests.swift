import XCTest
@testable import DinkyCommands

private func parse(_ s: String) throws -> Command { try Command.parse(s) }

final class QueryParseTests: XCTestCase {
    func testDebugState() throws {
        XCTAssertEqual(try parse("debug-state"), .debugState)
        XCTAssertThrowsError(try parse("debug-state --all"))
    }

    func testListWorkspaces() throws {
        XCTAssertEqual(try parse("list-workspaces"), .listWorkspaces(WorkspaceQuery()))
        var all = WorkspaceQuery()
        all.monitors = [.all]
        XCTAssertEqual(try parse("list-workspaces --all"), .listWorkspaces(all))
        XCTAssertEqual(try parse("list-workspaces --monitor all"), .listWorkspaces(all))
        var focused = WorkspaceQuery()
        focused.visible = true
        XCTAssertEqual(try parse("list-workspaces --focused"), .listWorkspaces(focused))
        var q = WorkspaceQuery()
        q.monitors = [.number(2), .focused]
        q.visible = false
        q.empty = true
        q.format = try Format("%{monitor-id}:%{workspace}", variables: WorkspaceQuery.variables)
        XCTAssertEqual(try parse("list-workspaces --monitor 2 focused --visible no --empty --format '%{monitor-id}:%{workspace}'"),
                       .listWorkspaces(q))
        var nonEmpty = WorkspaceQuery()
        (nonEmpty.empty, nonEmpty.visible) = (false, true)
        XCTAssertEqual(try parse("list-workspaces --empty no --visible yes"), .listWorkspaces(nonEmpty))
    }

    func testListWindows() throws {
        XCTAssertEqual(try parse("list-windows"), .listWindows(WindowQuery()))
        var q = WindowQuery()
        q.workspaces = [.number(1), .focused, .number(3), .visible]
        XCTAssertEqual(try parse("list-windows --workspace 1 focused --workspace 3 visible"), .listWindows(q))
        q = WindowQuery()
        q.focused = true
        q.format = try Format("%{window-layout}", variables: WindowQuery.variables)
        XCTAssertEqual(try parse("list-windows --focused --format %{window-layout}"), .listWindows(q))
        q = WindowQuery()
        q.monitors = [.all]
        q.appBundleID = "com.apple.Safari"
        XCTAssertEqual(try parse("list-windows --all --app-bundle-id com.apple.Safari"), .listWindows(q))
        q.monitors = [.number(1)]
        XCTAssertEqual(try parse("list-windows --monitor 1 --app-id com.apple.Safari"), .listWindows(q))
    }

    func testListMonitors() throws {
        XCTAssertEqual(try parse("list-monitors"), .listMonitors(MonitorQuery()))
        XCTAssertEqual(try parse("list-displays"), .listMonitors(MonitorQuery()))
        var q = MonitorQuery()
        q.focused = true
        XCTAssertEqual(try parse("list-monitors --focused"), .listMonitors(q))
        q.focused = false
        q.format = try Format("%{monitor-name}", variables: MonitorQuery.variables)
        XCTAssertEqual(try parse("list-displays --focused no --format '%{monitor-name}'"), .listMonitors(q))
    }

    func testErrors() {
        let cases = [
            "list-windows --bogus": "unknown flag '--bogus'",
            "list-workspaces extra": "unknown flag 'extra'",
            "list-monitors --all": "unknown flag '--all'",
            "list-windows --workspace": "--workspace needs a value",
            "list-windows --workspace zero": "not 'zero'",
            "list-workspaces --monitor left": "not 'left'",
            "list-windows --format": "--format needs a value",
            "list-windows --format '%{workspace-name}'": "unknown format variable '%{workspace-name}'",
            "list-workspaces --format '%{window-id}'": "unknown format variable '%{window-id}'",
            "list-monitors --format '%{monitor-id'": "unclosed '%{'",
        ]
        for (input, expected) in cases {
            do {
                _ = try Command.parse(input)
                XCTFail("parsed \(input)")
            } catch {
                XCTAssertEqual(error.input, input)
                XCTAssertTrue(error.message.contains(expected), error.message)
                XCTAssertTrue(error.message.contains("can't parse '\(input)'"), error.message)
            }
        }
    }
}

final class FormatTests: XCTestCase {
    private func render(_ format: String, _ rows: [[String: String]]) throws -> String {
        try Format(format, variables: ["a", "b"]).render(rows)
    }

    func testSubstitutesVariablesAndKeepsText() throws {
        XCTAssertEqual(try render("x %{a}-%{b} y", [["a": "1", "b": "2"], ["a": "3"]]), "x 1-2 y\nx 3- y")
        XCTAssertEqual(try render("%{a}%{tab}%{b}%{newline}", [["a": "1", "b": "2"]]), "1\t2\n")
        XCTAssertEqual(try render("100%", [[:]]), "100%")
        XCTAssertEqual(try render("%{a}", []), "")
    }

    func testRightPaddingAlignsColumns() throws {
        let rows = [["a": "1", "b": "Safari"], ["a": "12345", "b": "Terminal"], ["a": "77", "b": "Finder"]]
        XCTAssertEqual(try render("%{a}%{right-padding} | %{b}", rows), "1     | Safari\n12345 | Terminal\n77    | Finder")
    }

    func testDefaultFormatsMatchAeroSpace() {
        let rows = [["window-id": "7", "app-name": "Safari", "window-title": "Home"],
                    ["window-id": "123", "app-name": "Terminal", "window-title": "zsh"]]
        XCTAssertEqual(WindowQuery().format.render(rows), "7   | Safari   | Home\n123 | Terminal | zsh")
        XCTAssertEqual(WorkspaceQuery().format.render([["workspace": "1"], ["workspace": "2"]]), "1\n2")
        XCTAssertEqual(MonitorQuery().format.render([["monitor-id": "1", "monitor-name": "Built-in"]]), "1 | Built-in")
    }

    func testUnknownVariableFails() {
        XCTAssertThrowsError(try render("%{c}", [])) { error in
            XCTAssertTrue("\(error)".contains("%{c}"), "\(error)")
            XCTAssertTrue("\(error)".contains("%{a}, %{b}"), "\(error)")
        }
    }
}
