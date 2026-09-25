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
        XCTAssertEqual(try KeyCombo("keypadEnter").key, "keypadEnter")
        XCTAssertEqual(try KeyCombo("shift-alt-leftSquareBracket").description, "alt-shift-leftSquareBracket")
        for name in KeyCombo.keyNames {
            XCTAssertEqual(try KeyCombo("alt-\(name)").key, name)
        }
    }

    func testBadCombos() {
        for combo in ["", "alt-", "alt--", "hyper-a", "alt-shift-hh", "alt-Semicolon", "-a", "option-a"] {
            XCTAssertThrowsError(try KeyCombo(combo), combo) { error in
                XCTAssertTrue("\(error)".contains("'\(combo)'"), "\(error)")
            }
        }
    }
}
