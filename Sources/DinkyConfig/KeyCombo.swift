/// A key binding such as `alt-shift-h`: modifiers plus a key name, joined by `-`. The leading words that
/// name modifiers are the modifiers; the rest is the key, so `alt-page-up` is `alt` and `page-up`.
/// Parsing only; the hotkey engine maps key names to keycodes.
public struct KeyCombo: Hashable, CustomStringConvertible {
    public struct Modifiers: OptionSet, Hashable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let alt = Modifiers(rawValue: 1 << 0)
        public static let ctrl = Modifiers(rawValue: 1 << 1)
        public static let cmd = Modifiers(rawValue: 1 << 2)
        public static let shift = Modifiers(rawValue: 1 << 3)

        /// In canonical order.
        static let names: [(String, Modifiers)] = [("alt", .alt), ("ctrl", .ctrl), ("cmd", .cmd), ("shift", .shift)]
    }

    public var modifiers: Modifiers
    public var key: String

    public init(modifiers: Modifiers = [], key: String) {
        self.modifiers = modifiers
        self.key = key
    }

    public init(_ combo: String) throws(ConfigError) {
        var parts = combo.split(separator: "-", omittingEmptySubsequences: false).map(String.init)[...]
        var modifiers: Modifiers = []
        while let first = parts.first, let modifier = Modifiers.names.first(where: { $0.0 == first })?.1, parts.count > 1 {
            modifiers.insert(modifier)
            parts.removeFirst()
        }
        let key = parts.joined(separator: "-")
        guard KeyCombo.keyNames.contains(key) else {
            throw ConfigError("unknown key '\(key)' in '\(combo)', expected modifiers (alt, ctrl, cmd, shift) and a key name")
        }
        self.init(modifiers: modifiers, key: key)
    }

    /// Canonical form, e.g. `alt-shift-h`, whatever order the config wrote the modifiers in.
    public var description: String {
        let names = Modifiers.names.filter { modifiers.contains($0.1) }.map(\.0)
        return (names + [key]).joined(separator: "-")
    }

    /// Every key name, for a qwerty layout.
    public static let keyNames: Set<String> = {
        let letters = "abcdefghijklmnopqrstuvwxyz".map(String.init)
        let digits = (0...9).map(String.init)
        let functionKeys = (1...20).map { "f\($0)" }
        let keypad = (0...9).map { "keypad-\($0)" } + [
            "keypad-clear", "keypad-decimal", "keypad-divide", "keypad-enter",
            "keypad-equal", "keypad-minus", "keypad-multiply", "keypad-plus",
        ]
        let punctuation = [
            "section", "minus", "equal", "left-bracket", "right-bracket", "backslash",
            "semicolon", "quote", "comma", "period", "slash", "backtick",
        ]
        let special = [
            "page-up", "page-down", "home", "end", "forward-delete",
            "space", "enter", "esc", "backspace", "tab", "left", "down", "up", "right",
        ]
        return Set(letters + digits + functionKeys + keypad + punctuation + special)
    }()
}
