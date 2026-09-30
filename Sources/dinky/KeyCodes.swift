import CoreGraphics
import DinkyConfig

/// A key press as the event tap sees it: keycode plus the modifiers bindings care about.
struct KeyPress: Hashable {
    var code: CGKeyCode
    var modifiers: KeyCombo.Modifiers
}

extension KeyPress {
    /// Parsing a combo guarantees its key is in `KeyCombo.keyCodes`.
    init(_ combo: KeyCombo) {
        self.init(code: KeyCombo.keyCodes[combo.key]!, modifiers: combo.modifiers)
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
