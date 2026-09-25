import DinkyConfig
import DinkyLayout
import XCTest
@testable import DinkyCommands

private func parse(_ s: String) throws -> Command { try Command.parse(s) }

final class ParseTests: XCTestCase {
    func testWorkspace() throws {
        XCTAssertEqual(try parse("workspace 3"), .workspace(.number(3)))
        XCTAssertEqual(try parse("workspace prev"), .workspace(.prev))
        XCTAssertEqual(try parse("workspace next"), .workspace(.next))
        XCTAssertEqual(try parse("workspace-back-and-forth"), .workspaceBackAndForth)
    }

    func testMoveWindowToWorkspace() throws {
        XCTAssertEqual(try parse("move-window-to-workspace 1"), .moveWindowToWorkspace(.number(1), follow: false))
        XCTAssertEqual(try parse("move-window-to-workspace 3 --follow"), .moveWindowToWorkspace(.number(3), follow: true))
        XCTAssertEqual(try parse("move-window-to-workspace --follow next"), .moveWindowToWorkspace(.next, follow: true))
        XCTAssertEqual(try parse("move-window-to-workspace prev"), .moveWindowToWorkspace(.prev, follow: false))
    }

    func testMoveWindowToDisplay() throws {
        XCTAssertEqual(try parse("move-window-to-display next"), .moveWindowToDisplay(.next, follow: false))
        XCTAssertEqual(try parse("move-window-to-display prev --follow"), .moveWindowToDisplay(.prev, follow: true))
    }

    func testDirectional() throws {
        for (word, dir) in [("left", Direction.left), ("down", .down), ("up", .up), ("right", .right)] {
            XCTAssertEqual(try parse("focus \(word)"), .focus(dir))
            XCTAssertEqual(try parse("move \(word)"), .move(dir))
            XCTAssertEqual(try parse("join-with \(word)"), .joinWith(dir))
        }
    }

    func testResize() throws {
        XCTAssertEqual(try parse("resize smart -50"), .resize(.smart, by: -50))
        XCTAssertEqual(try parse("resize smart +50"), .resize(.smart, by: 50))
        XCTAssertEqual(try parse("resize width +10"), .resize(.width, by: 10))
        XCTAssertEqual(try parse("resize height -20"), .resize(.height, by: -20))
    }

    func testLayout() throws {
        XCTAssertEqual(try parse("layout tiles"), .layout([.tiles]))
        XCTAssertEqual(try parse("layout accordion"), .layout([.accordion]))
        XCTAssertEqual(try parse("layout floating"), .layout([.floating]))
        XCTAssertEqual(try parse("layout tiling"), .layout([.tiling]))
        XCTAssertEqual(try parse("layout floating tiling"), .layout([.floating, .tiling]))
        XCTAssertEqual(try parse("layout accordion tiles"), .layout([.accordion, .tiles]))
    }

    func testSimpleCommands() throws {
        XCTAssertEqual(try parse("fullscreen"), .fullscreen)
        XCTAssertEqual(try parse("flatten-workspace-tree"), .flattenWorkspaceTree)
        XCTAssertEqual(try parse("mode service"), .mode("service"))
        XCTAssertEqual(try parse("reload-config"), .reloadConfig)
        XCTAssertEqual(try parse("enable on"), .enable(.on))
        XCTAssertEqual(try parse("enable off"), .enable(.off))
        XCTAssertEqual(try parse("enable toggle"), .enable(.toggle))
        XCTAssertEqual(try parse("retile"), .retile)
        XCTAssertEqual(try parse("list-windows"), .listWindows)
        XCTAssertEqual(try parse("list-workspaces"), .listWorkspaces)
        XCTAssertEqual(try parse("list-displays"), .listDisplays)
    }

    func testExtraWhitespaceIsIgnored() throws {
        XCTAssertEqual(try parse("  workspace   2 \n"), .workspace(.number(2)))
    }

    func testEveryDefaultBindingParses() throws {
        let commands = Config.default.modes.values.flatMap { $0.bindings.values.flatMap { $0 } }
        XCTAssertFalse(commands.isEmpty)
        for command in commands + Config.default.onWindowDetected.flatMap(\.run) {
            XCTAssertNoThrow(try parse(command), command)
        }
    }

    func testEveryDocumentedNameParsesSomething() {
        XCTAssertEqual(Set(Command.all.map(\.name)).count, Command.all.count)
        for doc in Command.all {
            XCTAssertThrowsError(try parse("\(doc.name) bogus extra words"), doc.name)
        }
    }
}

final class ParseErrorTests: XCTestCase {
    private func message(_ s: String) -> String {
        do {
            _ = try Command.parse(s)
            return "parsed"
        } catch {
            XCTAssertEqual(error.input, s)
            return error.description
        }
    }

    func testUnknownCommandNamesStringAndCommands() {
        let m = message("frobnicate 3")
        XCTAssertTrue(m.contains("'frobnicate 3'"), m)
        XCTAssertTrue(m.contains("workspace-back-and-forth"), m)
    }

    func testBadArgumentsNameStringAndSyntax() {
        let m = message("workspace zero")
        XCTAssertTrue(m.contains("'workspace zero'"), m)
        XCTAssertTrue(m.contains("workspace <number|prev|next>"), m)
    }

    func testBadStrings() {
        for s in ["", "   ", "workspace", "workspace 0", "workspace -1", "workspace 1 2", "focus sideways",
                  "resize smart 50", "resize diagonal +50", "resize smart +x", "layout", "layout grid",
                  "layout tiles grid", "move-window-to-display 2", "move-window-to-workspace --follow",
                  "mode", "mode a b", "enable maybe", "fullscreen now", "Workspace 1"] {
            XCTAssertNotEqual(message(s), "parsed", s)
        }
    }

    func testEmpty() {
        XCTAssertEqual(message(""), "empty command")
    }
}
