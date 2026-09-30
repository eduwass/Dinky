import XCTest
@testable import DinkyConfig

final class ConfigTests: XCTestCase {
    func testDefaultConfigLoads() throws {
        let config = try Config.parse(Config.defaultTOML)
        XCTAssertEqual(config, Config.default)
        XCTAssertTrue(config.startAtLogin)
        XCTAssertEqual(config.workspaces, 5)
        XCTAssertEqual(config.defaultLayout, .tiles)
        XCTAssertTrue(config.defaultTiling)
        XCTAssertTrue(config.followAppActivation)
        XCTAssertEqual(config.accordion.padding, 30)
        XCTAssertEqual(config.accordion.orientation, .auto)
        XCTAssertEqual(config.gaps, Gaps())
        XCTAssertEqual(config.displays, [])
        XCTAssertTrue(config.borders.enabled)
        XCTAssertEqual(config.borders.width, 4)
        XCTAssertEqual(config.borders.activeColor, Color(red: 0xE1 / 255, green: 0xE3 / 255, blue: 0xE4 / 255))
        XCTAssertEqual(config.hooks, Hooks())
        XCTAssertEqual(config.rules.count, 1)
        XCTAssertEqual(config.rules[0].appId, "com.apple.systempreferences")
        XCTAssertEqual(config.rules[0].run, ["layout floating"])
        XCTAssertEqual(Set(config.modes.keys), ["main", "service"])
        let main = config.modes["main"]!.bindings
        XCTAssertEqual(main[try KeyCombo("ctrl-left")], ["workspace prev"])
        XCTAssertEqual(main[try KeyCombo("alt-9")], ["workspace 9"])
        XCTAssertEqual(main[try KeyCombo("alt-shift-9")], ["move-window-to-workspace 9"])
        XCTAssertEqual(main[try KeyCombo("alt-k")], ["focus up"])
        XCTAssertEqual(main[try KeyCombo("alt-shift-l")], ["move right"])
        XCTAssertEqual(main[try KeyCombo("alt-shift-semicolon")], ["mode service"])
        XCTAssertEqual(main.count, 37)
        XCTAssertEqual(config.modes["service"]!.bindings[try KeyCombo("esc")], ["reload-config", "mode main"])
        XCTAssertEqual(config.modes["service"]!.bindings[try KeyCombo("alt-shift-j")], ["join-with down", "mode main"])
    }

    func testShippedFileIsTheDefaultsPlusRulesAndBindings() throws {
        var shipped = Config.default
        shipped.rules = []
        shipped.modes = [:]
        XCTAssertEqual(shipped, Config(), "a key left out of a user's file must mean what the shipped file says")
    }

    func testEmptyConfigUsesDefaults() throws {
        XCTAssertEqual(try Config.parse(""), Config())
    }

    func testTopLevelKeys() throws {
        let config = try Config.parse("""
        start-at-login = false
        workspaces = 3
        default-layout = 'accordion'
        follow-app-activation = false
        """)
        XCTAssertFalse(config.startAtLogin)
        XCTAssertEqual(config.workspaces, 3)
        XCTAssertEqual(config.defaultLayout, .accordion)
        XCTAssertFalse(config.followAppActivation)
        assertError("workspaces = 0\n", path: "workspaces", line: 1, contains: "at least 1")
        assertError("default-layout = 'stack'\n", path: "default-layout", line: 1, contains: "'tiles', 'dwindle', 'accordion', 'fixed'")
    }

    func testWorkspaceLayouts() throws {
        let config = try Config.parse("""
        default-tiling = false
        [workspace.2]
        tiling = true
        layout = 'fixed'
        columns = 2
        rows = 3
        expand = 'accordion'
        [workspace.3]
        layout = 'accordion'
        """)
        XCTAssertFalse(config.tiling(forWorkspace: 1))
        XCTAssertTrue(config.tiling(forWorkspace: 2))
        XCTAssertEqual(config.layout(forWorkspace: 2), .fixed)
        XCTAssertEqual(config.fixedColumns(forWorkspace: 2), 2)
        XCTAssertEqual(config.fixedRows(forWorkspace: 2), 3)
        XCTAssertEqual(config.expansion(forWorkspace: 2), .accordion)
        XCTAssertEqual(config.layout(forWorkspace: 3), .accordion)
        XCTAssertEqual(config.fixedRows(forWorkspace: 3), 1)
        XCTAssertEqual(config.fixedColumns(forWorkspace: 3), 1)
        XCTAssertEqual(config.expansion(forWorkspace: 3), .columns)
        assertError("[workspace.0]\nlayout = 'fixed'\n", path: "workspace.0", line: 1, contains: "positive workspace number")
        assertError("[workspace.2]\nlayout = 'fixed'\ncolumns = 0\n", path: "workspace.2.columns", line: 3, contains: "at least 1")
        assertError("[workspace.2]\nlayout = 'fixed'\nrows = 0\n", path: "workspace.2.rows", line: 3, contains: "at least 1")
        assertError("[workspace.2]\nlayout = 'dwindle'\ncolumns = 2\n", path: "workspace.2.columns", line: 3, contains: "only valid")
        assertError("[workspace.2]\ncolumns = 2\n", path: "workspace.2.columns", line: 2, contains: "only valid")
        let inherited = try Config.parse("default-layout = 'fixed'\n[workspace.2]\ncolumns = 3\n")
        XCTAssertEqual(inherited.fixedColumns(forWorkspace: 2), 3)
        XCTAssertEqual(inherited.fixedRows(forWorkspace: 2), 1)
        let oneByOne = try Config.parse("[workspace.2]\nlayout = 'fixed'\n")
        XCTAssertEqual(oneByOne.fixedColumns(forWorkspace: 2), 1)
        XCTAssertEqual(oneByOne.fixedRows(forWorkspace: 2), 1)
        assertError("[workspace.2]\nlayout = 'fixed'\nexpand = 'diagonal'\n", path: "workspace.2.expand", line: 3, contains: "'rows', 'columns', 'accordion'")
    }

    func testUnknownTopLevelKeyFails() {
        assertError("workspaces = 3\ngap = 8\n", path: "gap", line: 2, contains: "unknown key")
        assertError("config-version = 1\n", path: "config-version", line: 1, contains: "unknown key")
        assertError("auto-reload-config = true\n", path: "auto-reload-config", line: 1, contains: "unknown key")
    }

    func testUnknownKeyInTableFails() {
        assertError("[gaps]\ninner = 8\n\n[borders]\nwidht = 4\n", path: "borders.widht", line: 5, contains: "unknown key")
        assertError("[gaps]\nouter = { top = 8, tpo = 8 }\n", path: "gaps.outer.tpo", line: 2, contains: "unknown key")
        assertError("[[rules]]\napp-idd = 'x'\nrun = 'y'\n", path: "rules[0].app-idd", line: 2, contains: "unknown key")
        assertError("[switching]\nfollow-app-activation = true\n", path: "switching", line: 1, contains: "unknown key")
        assertError("[layout]\ndefault = 'tiles'\n", path: "layout", line: 1, contains: "unknown key")
        assertError("[borders]\nonly-apps = []\n", path: "borders.only-apps", line: 2, contains: "unknown key")
    }

    func testBadTypeFails() {
        assertError("[gaps]\ninner = 'wide'\n", path: "gaps.inner", line: 2, contains: "expected an integer")
        assertError("workspaces = true\n", path: "workspaces", line: 1, contains: "expected an integer")
        assertError("gaps = 8\n", path: "gaps", line: 1, contains: "expected a table")
        assertError("[accordion]\norientation = 'sideways'\n", path: "accordion.orientation", line: 2, contains: "'auto', 'keep'")
    }

    func testAccordion() throws {
        let accordion = try Config.parse("[accordion]\npadding = 12\norientation = 'keep'\n").accordion
        XCTAssertEqual(accordion.padding, 12)
        XCTAssertEqual(accordion.orientation, .keep)
    }

    func testSyntaxErrorHasLine() {
        XCTAssertThrowsError(try Config.parse("workspaces = 5\n[gaps\n")) { error in
            XCTAssertTrue("\(error)".contains("Line 2"), "\(error)")
        }
    }

    func testColours() throws {
        XCTAssertEqual(try Color(hex: "#ff000080"), Color(red: 1, green: 0, blue: 0, alpha: 128 / 255))
        XCTAssertEqual(try Color(hex: "#00FF00"), Color(red: 0, green: 1, blue: 0))
        for bad in ["e1e3e4", "#e1e3", "#e1e3e4g", "#+1e3e4", "0xff0000", "0x80ff0000"] {
            XCTAssertThrowsError(try Color(hex: bad), bad)
        }
        assertError("[borders]\nactive-color = 'red'\n", path: "borders.active-color", line: 2, contains: "'red' is not a colour")
    }

    func testBorders() throws {
        XCTAssertEqual(Config().borders.order, .below)
        let borders = try Config.parse("""
        [borders]
        order = 'above'
        width = 2.5
        exclude-apps = ['com.apple.finder', 'com.apple.Terminal']
        """).borders
        XCTAssertEqual(borders.order, .above)
        XCTAssertEqual(borders.width, 2.5)
        XCTAssertEqual(borders.excludeApps, ["com.apple.finder", "com.apple.Terminal"])
        XCTAssertFalse(borders.decorates(bundleID: "com.apple.finder"))
        XCTAssertTrue(borders.decorates(bundleID: "com.apple.TextEdit"))
        XCTAssertTrue(borders.decorates(bundleID: nil))

        assertError("[borders]\norder = 'over'\n", path: "borders.order", line: 2, contains: "'below', 'above'")
        assertError("[borders]\nexclude-apps = 'com.apple.finder'\n", path: "borders.exclude-apps", line: 2, contains: "list of strings")
    }

    func testBindingValues() throws {
        let config = try Config.parse("""
        [mode.main]
        alt-a = 'workspace 1'
        alt-b = ['layout floating', 'mode main']

        [mode.resize]
        minus = 'resize smart -50'
        """)
        let bindings = config.modes["main"]!.bindings
        XCTAssertEqual(bindings[KeyCombo(modifiers: .alt, key: "a")], ["workspace 1"])
        XCTAssertEqual(bindings[KeyCombo(modifiers: .alt, key: "b")], ["layout floating", "mode main"])
        XCTAssertEqual(config.modes["resize"]!.bindings[KeyCombo(key: "minus")], ["resize smart -50"])
    }

    func testBadBindingValuesFail() {
        assertError("[mode.main]\nalt-a = ''\n", path: "mode.main.alt-a", line: 2, contains: "can't be empty")
        assertError("[mode.main]\nalt-a = []\n", path: "mode.main.alt-a", line: 2, contains: "can't be empty")
        assertError("[mode.main]\nalt-a = 3\n", path: "mode.main.alt-a", line: 2, contains: "command string")
        assertError("[mode.main]\nalt-a = ['x', 3]\n", path: "mode.main.alt-a", line: 2, contains: "command string")
        assertError("[mode.main]\nalt-hyper-a = 'x'\n", path: "mode.main.alt-hyper-a", line: 2, contains: "'alt-hyper-a'")
        assertError("[mode.main]\nalt-shift-a = 'x'\nshift-alt-a = 'y'\n", path: "mode.main.shift-alt-a", line: 3, contains: "bound twice")
        assertError("[mode.main.binding]\nalt-a = 'x'\n", path: "mode.main.binding", line: 1, contains: "unknown key 'binding'")
    }

    func testWindowRuleRoundTrips() throws {
        let config = try Config.parse("""
        [[rules]]
        app-id = 'com.apple.finder'
        app-name = 'find'
        title = '^Copy'
        kind = 'dialog'
        run = ['layout floating', 'move-window-to-workspace 2']

        [[rules]]
        run = 'layout tiling'
        """)
        var expected = WindowRule()
        expected.appId = "com.apple.finder"
        expected.appName = "find"
        expected.title = "^Copy"
        expected.kind = .dialog
        expected.run = ["layout floating", "move-window-to-workspace 2"]
        var second = WindowRule()
        second.run = ["layout tiling"]
        XCTAssertEqual(config.rules, [expected, second])

        XCTAssertTrue(expected.matches(appId: "com.apple.finder", appName: "Finder", title: "Copy 3 items", kind: .dialog))
        XCTAssertFalse(expected.matches(appId: "com.apple.finder", appName: "Finder", title: "Copy 3 items", kind: .normal))
        XCTAssertFalse(expected.matches(appId: "com.apple.finder", appName: "Finder", title: "Desktop", kind: .dialog))
        XCTAssertFalse(expected.matches(appId: "com.apple.Safari", appName: "Finder", title: "Copy", kind: .dialog))
        XCTAssertTrue(second.matches(appId: nil, appName: nil, title: "", kind: .normal), "a rule with no conditions matches everything")
    }

    func testBadWindowRulesFail() {
        assertError("[[rules]]\napp-id = 'x'\n", path: "rules[0].run", line: 1, contains: "every rule needs 'run'")
        assertError("[[rules]]\ntitle = '('\nrun = 'x'\n", path: "rules[0].title", line: 2, contains: "not a valid regex")
        assertError("[[rules]]\nkind = 'popup'\nrun = 'x'\n", path: "rules[0].kind", line: 2, contains: "'normal', 'dialog', 'sheet', 'panel'")
        assertError("[[rules]]\nif.app-id = 'x'\nrun = 'y'\n", path: "rules[0].if", line: 2, contains: "unknown key")
    }

    func testHooks() throws {
        XCTAssertEqual(Config.default.hooks, Hooks())
        let hooks = try Config.parse("""
        [hooks]
        startup = 'exec-and-forget brew services restart sketchybar'
        workspace-changing = 'exec-and-forget sketchybar --trigger workspace_changing'
        workspace-changed = ['exec-and-forget sketchybar --trigger workspace_change']
        focus-changed = []
        mode-changed = ['exec-and-forget sketchybar --trigger mode_changed', 'retile']
        """).hooks
        XCTAssertEqual(hooks.startup, ["exec-and-forget brew services restart sketchybar"])
        XCTAssertEqual(hooks.workspaceChanging, ["exec-and-forget sketchybar --trigger workspace_changing"])
        XCTAssertEqual(hooks.workspaceChanged, ["exec-and-forget sketchybar --trigger workspace_change"])
        XCTAssertEqual(hooks.focusChanged, [])
        XCTAssertEqual(hooks.modeChanged, ["exec-and-forget sketchybar --trigger mode_changed", "retile"])
        assertError("[hooks]\nmode-changed = [1]\n", path: "hooks.mode-changed", line: 2, contains: "command string")
        assertError("[hooks]\nstartup = ['']\n", path: "hooks.startup", line: 2, contains: "can't be empty")
        assertError("[hooks]\non-startup = 'x'\n", path: "hooks.on-startup", line: 2, contains: "unknown key")
        assertError("after-startup-command = ['x']\n", path: "after-startup-command", line: 1, contains: "unknown key")
    }

    func testFocusFollowsMouse() throws {
        let defaults = Config.default.focusFollowsMouse
        XCTAssertEqual(defaults, FocusFollowsMouse())
        XCTAssertFalse(defaults.enabled)
        XCTAssertEqual(defaults.delayMs, 100)
        XCTAssertTrue(defaults.accordionEdges)
        let ffm = try Config.parse("""
        [focus-follows-mouse]
        enabled = true
        delay-ms = 0
        accordion-edges = false
        """).focusFollowsMouse
        XCTAssertTrue(ffm.enabled)
        XCTAssertEqual(ffm.delayMs, 0)
        XCTAssertFalse(ffm.accordionEdges)
        assertError("[focus-follows-mouse]\ndelay-ms = -1\n", path: "focus-follows-mouse.delay-ms", line: 2, contains: "0 or more")
        assertError("[focus-follows-mouse]\naccordion = true\n", path: "focus-follows-mouse.accordion", line: 2, contains: "unknown key")
    }

    func testAnimationsAndDrag() throws {
        XCTAssertEqual(Config.default.animations, Animations())
        XCTAssertEqual(Config.default.drag, Drag())
        let config = try Config.parse("""
        [animations]
        enabled = false
        duration-ms = 300
        [drag]
        placeholders = false
        """)
        XCTAssertFalse(config.animations.enabled)
        XCTAssertEqual(config.animations.durationMs, 300)
        XCTAssertFalse(config.drag.placeholders)
        assertError("[animations]\nduration-ms = -1\n", path: "animations.duration-ms", line: 2, contains: "0 to 1000")
        assertError("[drag]\nghost = true\n", path: "drag.ghost", line: 2, contains: "unknown key")
    }

    func testLoadFromMissingFileFails() {
        XCTAssertThrowsError(try Config.load(from: URL(fileURLWithPath: "/nonexistent/dinky.toml"))) { error in
            XCTAssertTrue("\(error)".contains("/nonexistent/dinky.toml"))
        }
    }

    private func assertError(_ toml: String, path: String, line: Int?, contains text: String, file: StaticString = #filePath, lineNumber: UInt = #line) {
        do {
            _ = try Config.parse(toml)
            XCTFail("expected an error for \(path)", file: file, line: lineNumber)
        } catch {
            XCTAssertEqual(error.path, path, file: file, line: lineNumber)
            if let line { XCTAssertEqual(error.line, line, "\(error)", file: file, line: lineNumber) }
            XCTAssertTrue(error.description.contains(text), error.description, file: file, line: lineNumber)
            XCTAssertTrue(error.description.contains(path), error.description, file: file, line: lineNumber)
        }
    }
}
