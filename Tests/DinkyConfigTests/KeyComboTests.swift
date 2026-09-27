import XCTest
@testable import DinkyConfig

final class KeyComboTests: XCTestCase {
    func testForms() throws {
        XCTAssertEqual(try KeyCombo("esc"), KeyCombo(key: "esc"))
        XCTAssertEqual(try KeyCombo("r"), KeyCombo(key: "r"))
        XCTAssertEqual(try KeyCombo("ctrl-left"), KeyCombo(modifiers: .ctrl, key: "left"))
        XCTAssertEqual(try KeyCombo("alt-1"), KeyCombo(modifiers: .alt, key: "1"))
        XCTAssertEqual(try KeyCombo("alt-shift-h"), KeyCombo(modifiers: [.alt, .shift], key: "h"))
        XCTAssertEqual(try KeyCombo("alt-shift-semicolon"), KeyCombo(modifiers: [.alt, .shift], key: "semicolon"))
        XCTAssertEqual(try KeyCombo("cmd-ctrl-alt-shift-f12"), KeyCombo(modifiers: [.alt, .ctrl, .cmd, .shift], key: "f12"))
        XCTAssertEqual(try KeyCombo("alt-minus").key, "minus")
        XCTAssertEqual(try KeyCombo("keypad-enter").key, "keypad-enter")
        XCTAssertEqual(try KeyCombo("alt-page-up"), KeyCombo(modifiers: .alt, key: "page-up"))
        XCTAssertEqual(try KeyCombo("page-down"), KeyCombo(key: "page-down"))
        XCTAssertEqual(try KeyCombo("shift-alt-left-bracket").description, "alt-shift-left-bracket")
        for name in KeyCombo.keyNames {
            XCTAssertEqual(try KeyCombo("alt-\(name)").key, name)
            XCTAssertEqual(try KeyCombo(name).key, name)
        }
    }

    func testKeyNamesAreKebabCase() {
        for name in KeyCombo.keyNames {
            XCTAssertEqual(name, name.lowercased(), name)
        }
    }

    func testBadCombos() {
        for combo in ["", "alt-", "alt--", "hyper-a", "alt-shift-hh", "alt-Semicolon", "-a", "option-a", "pageUp", "alt-page"] {
            XCTAssertThrowsError(try KeyCombo(combo), combo) { error in
                XCTAssertTrue("\(error)".contains("'\(combo)'"), "\(error)")
            }
        }
    }
}
