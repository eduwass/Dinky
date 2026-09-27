import Carbon.HIToolbox
import CoreGraphics
import DinkyConfig

// Key names (KeyCombo.keyNames) to macOS virtual keycodes, qwerty layout.

/// A key press as the event tap sees it: keycode plus the modifiers bindings care about.
struct KeyPress: Hashable {
    var code: CGKeyCode
    var modifiers: KeyCombo.Modifiers
}

extension KeyPress {
    /// Nil if the combo names a key without a keycode.
    init?(_ combo: KeyCombo) {
        guard let code = keyCodes[combo.key] else { return nil }
        self.init(code: code, modifiers: combo.modifiers)
    }

    /// Only alt, ctrl, cmd and shift count. Arrow and function keys carry the secondary-fn
    /// flag on Apple keyboards, and caps lock adds its own; both are ignored so that
    /// `ctrl-left` matches however the keyboard reports it.
    init(_ event: CGEvent) {
        var modifiers: KeyCombo.Modifiers = []
        for (flag, modifier) in modifierFlags where event.flags.contains(flag) { modifiers.insert(modifier) }
        self.init(code: CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)), modifiers: modifiers)
    }
}

let modifierFlags: [(CGEventFlags, KeyCombo.Modifiers)] = [
    (.maskAlternate, .alt), (.maskControl, .ctrl), (.maskCommand, .cmd), (.maskShift, .shift),
]

let keyCodes: [String: CGKeyCode] = {
    let codes: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
        "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
        "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
        "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
        "z": kVK_ANSI_Z,

        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
        "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,

        "section": kVK_ISO_Section, "minus": kVK_ANSI_Minus, "equal": kVK_ANSI_Equal,
        "left-bracket": kVK_ANSI_LeftBracket, "right-bracket": kVK_ANSI_RightBracket,
        "backslash": kVK_ANSI_Backslash, "semicolon": kVK_ANSI_Semicolon, "quote": kVK_ANSI_Quote,
        "comma": kVK_ANSI_Comma, "period": kVK_ANSI_Period, "slash": kVK_ANSI_Slash, "backtick": kVK_ANSI_Grave,

        "keypad-0": kVK_ANSI_Keypad0, "keypad-1": kVK_ANSI_Keypad1, "keypad-2": kVK_ANSI_Keypad2,
        "keypad-3": kVK_ANSI_Keypad3, "keypad-4": kVK_ANSI_Keypad4, "keypad-5": kVK_ANSI_Keypad5,
        "keypad-6": kVK_ANSI_Keypad6, "keypad-7": kVK_ANSI_Keypad7, "keypad-8": kVK_ANSI_Keypad8,
        "keypad-9": kVK_ANSI_Keypad9, "keypad-clear": kVK_ANSI_KeypadClear,
        "keypad-decimal": kVK_ANSI_KeypadDecimal, "keypad-divide": kVK_ANSI_KeypadDivide,
        "keypad-enter": kVK_ANSI_KeypadEnter, "keypad-equal": kVK_ANSI_KeypadEquals,
        "keypad-minus": kVK_ANSI_KeypadMinus, "keypad-multiply": kVK_ANSI_KeypadMultiply,
        "keypad-plus": kVK_ANSI_KeypadPlus,

        "page-up": kVK_PageUp, "page-down": kVK_PageDown, "home": kVK_Home, "end": kVK_End,
        "forward-delete": kVK_ForwardDelete, "space": kVK_Space, "enter": kVK_Return, "esc": kVK_Escape,
        "backspace": kVK_Delete, "tab": kVK_Tab,
        "left": kVK_LeftArrow, "down": kVK_DownArrow, "up": kVK_UpArrow, "right": kVK_RightArrow,

        "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5,
        "f6": kVK_F6, "f7": kVK_F7, "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10,
        "f11": kVK_F11, "f12": kVK_F12, "f13": kVK_F13, "f14": kVK_F14, "f15": kVK_F15,
        "f16": kVK_F16, "f17": kVK_F17, "f18": kVK_F18, "f19": kVK_F19, "f20": kVK_F20,
    ]
    return codes.mapValues { CGKeyCode($0) }
}()
