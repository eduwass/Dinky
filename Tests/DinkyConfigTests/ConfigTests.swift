import XCTest
@testable import DinkyConfig

final class ConfigTests: XCTestCase {
    func testPlanDraftLoads() throws {
        let config = try Config.parse(planDraft)
        XCTAssertEqual(config.configVersion, 1)
        XCTAssertTrue(config.startAtLogin)
        XCTAssertTrue(config.autoReloadConfig)
        XCTAssertEqual(config.workspaces, 5)
        XCTAssertEqual(config.layout.default, .tiles)
        XCTAssertEqual(config.layout.accordionPadding, 30)
        XCTAssertEqual(config.layout.accordionOrientation, .auto)
        XCTAssertEqual(config.gaps.inner, Inner(8))
        XCTAssertEqual(config.gaps.outer, Sides(8))
        XCTAssertTrue(config.borders.enabled)
        XCTAssertEqual(config.borders.width, 4)
        XCTAssertEqual(config.borders.activeColor, Color(red: 0xE1 / 255, green: 0xE3 / 255, blue: 0xE4 / 255))
        XCTAssertEqual(config.borders.style, .round)
        XCTAssertTrue(config.switching.followAppActivation)
        XCTAssertEqual(config.onWindowDetected.count, 1)
        XCTAssertEqual(config.onWindowDetected[0].matcher.appId, "com.apple.systempreferences")
        XCTAssertEqual(config.onWindowDetected[0].run, ["layout floating"])
        XCTAssertEqual(Set(config.modes.keys), ["main", "service"])
        let main = config.modes["main"]!.bindings
        XCTAssertEqual(main[try KeyCombo("ctrl-left")], ["workspace prev"])
        XCTAssertEqual(main[try KeyCombo("alt-shift-semicolon")], ["mode service"])
        XCTAssertEqual(config.modes["service"]!.bindings[try KeyCombo("esc")], ["reload-config", "mode main"])
    }

    func testDefaultConfigLoads() throws {
        let config = try Config.parse(Config.defaultTOML)
        XCTAssertEqual(config, Config.default)
        let main = config.modes["main"]!.bindings
        XCTAssertEqual(main[try KeyCombo("alt-9")], ["workspace 9"])
        XCTAssertEqual(main[try KeyCombo("alt-shift-9")], ["move-window-to-workspace 9"])
        XCTAssertEqual(main[try KeyCombo("alt-k")], ["focus up"])
        XCTAssertEqual(main[try KeyCombo("alt-shift-l")], ["move right"])
        XCTAssertEqual(config.modes["service"]!.bindings[try KeyCombo("alt-shift-j")], ["join-with down", "mode main"])
        XCTAssertEqual(main.count, 37)
    }

    func testEmptyConfigUsesDefaults() throws {
        XCTAssertEqual(try Config.parse(""), Config())
    }

    func testUnknownTopLevelKeyFails() {
        assertError("workspaces = 3\ngap = 8\n", path: "gap", line: 2, contains: "unknown key")
    }

    func testUnknownKeyInTableFails() {
        assertError("[gaps]\ninner = 8\n\n[borders]\nwidht = 4\n", path: "borders.widht", line: 5, contains: "unknown key")
        assertError("[gaps]\nouter = { top = 8, tpo = 8 }\n", path: "gaps.outer.tpo", line: 2, contains: "unknown key")
        assertError("[[on-window-detected]]\nif.app-idd = 'x'\nrun = 'y'\n", path: "on-window-detected[0].if.app-idd", line: 2, contains: "unknown key")
    }

    func testBadTypeFails() {
        assertError("[gaps]\ninner = 'wide'\n", path: "gaps.inner", line: 2, contains: "expected a number or a list")
        assertError("workspaces = true\n", path: "workspaces", line: 1, contains: "expected an integer")
        assertError("gaps = 8\n", path: "gaps", line: 1, contains: "expected a table")
        assertError("[layout]\ndefault = 'stack'\n", path: "layout.default", line: 2, contains: "'tiles', 'accordion'")
        assertError("[layout]\naccordion-orientation = 'sideways'\n", path: "layout.accordion-orientation", line: 2, contains: "'auto', 'keep'")
    }

    func testAccordionOrientation() throws {
        XCTAssertEqual(try Config.parse("[layout]\naccordion-orientation = 'keep'\n").layout.accordionOrientation, .keep)
        XCTAssertEqual(try Config.parse("").layout.accordionOrientation, .auto)
    }

    func testSyntaxErrorHasLine() {
        XCTAssertThrowsError(try Config.parse("workspaces = 5\n[gaps\n")) { error in
            XCTAssertTrue("\(error)".contains("Line 2"), "\(error)")
        }
    }

    func testColours() throws {
        XCTAssertEqual(try Color(hex: "#ff000080"), Color(red: 1, green: 0, blue: 0, alpha: 128 / 255))
        XCTAssertEqual(try Color(hex: "0x80ff0000"), Color(red: 1, green: 0, blue: 0, alpha: 128 / 255))
        XCTAssertEqual(try Color(hex: "0xff0000"), Color(red: 1, green: 0, blue: 0, alpha: 1))
        XCTAssertEqual(try Color(hex: "#00FF00"), Color(red: 0, green: 1, blue: 0))
        for bad in ["e1e3e4", "#e1e3", "#e1e3e4g", "#+1e3e4"] {
            XCTAssertThrowsError(try Color(hex: bad), bad)
        }
        assertError("[borders]\nactive-color = 'red'\n", path: "borders.active-color", line: 2, contains: "'red' is not a colour")
    }

    func testBorderOrderAndAppLists() throws {
        XCTAssertEqual(Config().borders.order, .below)
        let borders = try Config.parse("""
        [borders]
        order = 'above'
        exclude-apps = ['com.apple.finder', 'com.apple.Terminal']
        only-apps = []
        """).borders
        XCTAssertEqual(borders.order, .above)
        XCTAssertEqual(borders.excludeApps, ["com.apple.finder", "com.apple.Terminal"])
        XCTAssertEqual(borders.onlyApps, [])
        XCTAssertFalse(borders.decorates(bundleID: "com.apple.finder"))
        XCTAssertTrue(borders.decorates(bundleID: "com.apple.TextEdit"))
        XCTAssertTrue(borders.decorates(bundleID: nil))

        var only = Borders()
        only.onlyApps = ["com.apple.TextEdit"]
        XCTAssertTrue(only.decorates(bundleID: "com.apple.TextEdit"))
        XCTAssertFalse(only.decorates(bundleID: "com.apple.finder"))
        XCTAssertFalse(only.decorates(bundleID: nil))

        assertError("[borders]\norder = 'over'\n", path: "borders.order", line: 2, contains: "'below', 'above'")
        assertError("[borders]\nexclude-apps = 'com.apple.finder'\n", path: "borders.exclude-apps", line: 2, contains: "list of strings")
        assertError("[borders]\nonly-apps = [1]\n", path: "borders.only-apps", line: 2, contains: "list of strings")
    }

    func testBindingValues() throws {
        let config = try Config.parse("""
        [mode.main.binding]
        alt-a = 'workspace 1'
        alt-b = ['layout floating', 'mode main']
        """)
        let bindings = config.modes["main"]!.bindings
        XCTAssertEqual(bindings[KeyCombo(modifiers: .alt, key: "a")], ["workspace 1"])
        XCTAssertEqual(bindings[KeyCombo(modifiers: .alt, key: "b")], ["layout floating", "mode main"])
    }

    func testBadBindingValuesFail() {
        assertError("[mode.main.binding]\nalt-a = ''\n", path: "mode.main.binding.alt-a", line: 2, contains: "can't be empty")
        assertError("[mode.main.binding]\nalt-a = []\n", path: "mode.main.binding.alt-a", line: 2, contains: "can't be empty")
        assertError("[mode.main.binding]\nalt-a = 3\n", path: "mode.main.binding.alt-a", line: 2, contains: "command string")
        assertError("[mode.main.binding]\nalt-a = ['x', 3]\n", path: "mode.main.binding.alt-a", line: 2, contains: "command string")
        assertError("[mode.main.binding]\nalt-hyper-a = 'x'\n", path: "mode.main.binding.alt-hyper-a", line: 2, contains: "'alt-hyper-a'")
        assertError("[mode.main.binding]\nalt-shift-a = 'x'\nshift-alt-a = 'y'\n", path: "mode.main.binding.shift-alt-a", line: 3, contains: "bound twice")
    }

    func testWindowRuleRoundTrips() throws {
        let config = try Config.parse("""
        [[on-window-detected]]
        if.app-id = 'com.apple.finder'
        if.app-name-regex-substring = 'find'
        if.window-title-regex-substring = '^Copy'
        if.window-kind = 'dialog'
        check-further-callbacks = true
        run = ['layout floating', 'move-window-to-workspace 2']

        [[on-window-detected]]
        run = 'layout tiling'
        """)
        var expected = WindowRule()
        expected.matcher.appId = "com.apple.finder"
        expected.matcher.appNameRegexSubstring = "find"
        expected.matcher.windowTitleRegexSubstring = "^Copy"
        expected.matcher.windowKind = .dialog
        expected.checkFurtherCallbacks = true
        expected.run = ["layout floating", "move-window-to-workspace 2"]
        var second = WindowRule()
        second.run = ["layout tiling"]
        XCTAssertEqual(config.onWindowDetected, [expected, second])
    }

    func testBadWindowRulesFail() {
        assertError("[[on-window-detected]]\nif.app-id = 'x'\n", path: "on-window-detected[0].run", line: 1, contains: "every rule needs 'run'")
        assertError("[[on-window-detected]]\nif.window-title-regex-substring = '('\nrun = 'x'\n",
                    path: "on-window-detected[0].if.window-title-regex-substring", line: 2, contains: "not a valid regex")
    }

    func testCallbacks() throws {
        XCTAssertEqual(Config.default.execOnWorkspaceChange, [])
        XCTAssertEqual(Config.default.onFocusChanged, [])
        XCTAssertEqual(Config.default.onModeChanged, [])
        let config = try Config.parse("""
        exec-on-workspace-change = ['/bin/bash', '-c',
            'sketchybar --trigger aerospace_workspace_change FOCUSED_WORKSPACE=$AEROSPACE_FOCUSED_WORKSPACE'
        ]
        on-focus-changed = ['exec-and-forget sketchybar --trigger aerospace_mode_changed']
        on-mode-changed = ['exec-and-forget sketchybar --trigger aerospace_mode_changed', 'retile']
        """)
        XCTAssertEqual(config.execOnWorkspaceChange, ["/bin/bash", "-c",
                                                      "sketchybar --trigger aerospace_workspace_change FOCUSED_WORKSPACE=$AEROSPACE_FOCUSED_WORKSPACE"])
        XCTAssertEqual(config.onFocusChanged, ["exec-and-forget sketchybar --trigger aerospace_mode_changed"])
        XCTAssertEqual(config.onModeChanged, ["exec-and-forget sketchybar --trigger aerospace_mode_changed", "retile"])
        assertError("exec-on-workspace-change = '/bin/sh'\n", path: "exec-on-workspace-change", line: 1, contains: "list of strings")
        assertError("on-mode-changed = [1]\n", path: "on-mode-changed", line: 1, contains: "list of strings")
    }

    func testFocusFollowsMouse() throws {
        let defaults = Config.default.focusFollowsMouse
        XCTAssertEqual(defaults, FocusFollowsMouse())
        XCTAssertFalse(defaults.enabled)
        XCTAssertEqual(defaults.delayMs, 100)
        XCTAssertTrue(defaults.accordion)
        let ffm = try Config.parse("""
        [focus-follows-mouse]
        enabled = true
        delay-ms = 0
        accordion = false
        """).focusFollowsMouse
        XCTAssertTrue(ffm.enabled)
        XCTAssertEqual(ffm.delayMs, 0)
        XCTAssertFalse(ffm.accordion)
        assertError("[focus-follows-mouse]\ndelay-ms = -1\n", path: "focus-follows-mouse.delay-ms", line: 2, contains: "0 or more")
        assertError("[focus-follows-mouse]\ndelay = 5\n", path: "focus-follows-mouse.delay", line: 2, contains: "unknown key")
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
