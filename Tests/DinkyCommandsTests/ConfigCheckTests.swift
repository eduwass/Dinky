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
        XCTAssertTrue(findings[0].message.contains("mode.main"))
    }

    func testUnknownCommandInBinding() throws {
        let findings = try check("[mode.main.binding]\nalt-h = 'fly left'")
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings[0].level, .error)
        XCTAssertTrue(findings[0].message.hasPrefix("mode.main.binding.alt-h:"))
    }

    func testModeCommandMustNameAMode() throws {
        let findings = try check("[mode.main.binding]\nalt-h = 'mode resize'")
        XCTAssertEqual(findings.count, 1)
        XCTAssertTrue(findings[0].message.contains("names a mode that is not in the config"))
        XCTAssertEqual(try check("[mode.main.binding]\nalt-h = 'mode resize'\n[mode.resize.binding]\nesc = 'mode main'"), [])
    }

    func testUnknownKeyName() throws {
        let findings = try check("[mode.main.binding]\nalt-h = 'focus left'", known: [])
        XCTAssertEqual(findings.count, 1)
        XCTAssertTrue(findings[0].message.contains("unknown key 'h'"))
    }

    func testRuleAndCallbackCommandsAreChecked() throws {
        let toml = """
        [mode.main.binding]
        alt-h = 'focus left'
        on-focus-changed = ['exec-and-forget true', 'nonsense']
        [[on-window-detected]]
        if.app-id = 'com.apple.finder'
        run = 'layout floating'
        """
        // Callbacks after a table header belong to that table in TOML, so put them first.
        let fixed = "on-focus-changed = ['exec-and-forget true', 'nonsense']\n" + toml.replacingOccurrences(of: "on-focus-changed = ['exec-and-forget true', 'nonsense']\n", with: "")
        let findings = try check(fixed)
        XCTAssertEqual(findings.count, 1)
        XCTAssertTrue(findings[0].message.hasPrefix("on-focus-changed:"))
    }
}
