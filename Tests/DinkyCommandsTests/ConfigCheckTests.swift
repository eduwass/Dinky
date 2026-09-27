import XCTest
import DinkyConfig
@testable import DinkyCommands

final class ConfigCheckTests: XCTestCase {
    private func check(_ toml: String, known: Set<String> = ["h", "1", "esc", "r"]) throws -> [ConfigFinding] {
        checkConfig(try Config.parse(toml), keyIsKnown: { known.contains($0) })
    }

    func testDefaultConfigIsClean() throws {
        let findings = checkConfig(Config.default, keyIsKnown: { _ in true })
        XCTAssertEqual(findings, [])
    }

    func testMissingMainModeIsAWarning() throws {
        let findings = try check("workspaces = 3")
        XCTAssertEqual(findings.map(\.level), [.warning])
        XCTAssertTrue(findings[0].message.contains("[mode.main]"))
    }

    func testUnknownCommandInBinding() throws {
        let findings = try check("[mode.main]\nalt-h = 'fly left'")
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings[0].level, .error)
        XCTAssertTrue(findings[0].message.hasPrefix("mode.main.alt-h:"))
    }

    func testModeCommandMustNameAMode() throws {
        let findings = try check("[mode.main]\nalt-h = 'mode resize'")
        XCTAssertEqual(findings.count, 1)
        XCTAssertTrue(findings[0].message.contains("names a mode that is not in the config"))
        XCTAssertEqual(try check("[mode.main]\nalt-h = 'mode resize'\n[mode.resize]\nesc = 'mode main'"), [])
    }

    func testUnknownKeyName() throws {
        let findings = try check("[mode.main]\nalt-h = 'focus left'", known: [])
        XCTAssertEqual(findings.count, 1)
        XCTAssertTrue(findings[0].message.contains("unknown key 'h'"))
    }

    func testRuleAndHookCommandsAreChecked() throws {
        let findings = try check("""
        [hooks]
        focus-changed = ['exec-and-forget true', 'nonsense']
        [mode.main]
        alt-h = 'focus left'
        [[rules]]
        app-id = 'com.apple.finder'
        run = 'layout floating'
        [[rules]]
        run = 'float'
        """)
        XCTAssertEqual(findings.count, 2)
        XCTAssertTrue(findings[0].message.hasPrefix("rules[1].run:"), findings[0].message)
        XCTAssertTrue(findings[1].message.hasPrefix("hooks.focus-changed:"), findings[1].message)
    }

    func testStartupHookIsChecked() throws {
        let findings = try check("""
        [hooks]
        startup = ['exec-and-forget true', 'balance-sizes', 'focus-monitor next', 'focus left --boundaries nowhere']
        """)
        XCTAssertEqual(findings.map(\.level), [.warning, .error])
        XCTAssertTrue(findings[1].message.hasPrefix("hooks.startup:"), findings[1].message)
    }
}
