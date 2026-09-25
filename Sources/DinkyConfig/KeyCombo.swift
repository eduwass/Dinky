// Key syntax and key names follow AeroSpace (MIT, github.com/nikitabobko/AeroSpace,
// Sources/AppBundle/config/keysMap.swift) so existing binding tables carry over.

/// A key binding such as `alt-shift-h`: modifiers plus a key name. Parsing only; the
/// hotkey engine maps key names to keycodes.
public struct KeyCombo: Hashable, CustomStringConvertible {
    public struct Modifiers: OptionSet, Hashable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let alt = Modifiers(rawValue: 1 << 0)
        public static let ctrl = Modifiers(rawValue: 1 << 1)
        public static let cmd = Modifiers(rawValue: 1 << 2)
        public static let shift = Modifiers(rawValue: 1 << 3)

        /// In AeroSpace's canonical order.
        static let names: [(String, Modifiers)] = [("alt", .alt), ("ctrl", .ctrl), ("cmd", .cmd), ("shift", .shift)]
    }

    public var modifiers: Modifiers
    public var key: String

    public init(modifiers: Modifiers = [], key: String) {
        self.modifiers = modifiers
        self.key = key
    }

    public init(_ combo: String) throws(ConfigError) {
        let parts = combo.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        var modifiers: Modifiers = []
        for name in parts.dropLast() {
            guard let modifier = Modifiers.names.first(where: { $0.0 == name })?.1 else {
                throw ConfigError("unknown modifier '\(name)' in '\(combo)', expected alt, ctrl, cmd or shift")
            }
            modifiers.insert(modifier)
        }
        let key = parts.last ?? ""
        guard KeyCombo.keyNames.contains(key) else {
            throw ConfigError("unknown key '\(key)' in '\(combo)'")
        }
        self.init(modifiers: modifiers, key: key)
    }

    /// Canonical form, e.g. `alt-shift-h`, whatever order the config wrote the modifiers in.
    public var description: String {
        let names = Modifiers.names.filter { modifiers.contains($0.1) }.map(\.0)
        return (names + [key]).joined(separator: "-")
    }

    /// Every key name AeroSpace accepts on a qwerty layout.
    public static let keyNames: Set<String> = {
        let letters = "abcdefghijklmnopqrstuvwxyz".map(String.init)
        let digits = (0...9).map(String.init)
        let functionKeys = (1...20).map { "f\($0)" }
        let keypad = (0...9).map { "keypad\($0)" } + [
            "keypadClear", "keypadDecimalMark", "keypadDivide", "keypadEnter",
            "keypadEqual", "keypadMinus", "keypadMultiply", "keypadPlus",
        ]
        let punctuation = [
            "sectionSign", "minus", "equal", "leftSquareBracket", "rightSquareBracket", "backslash",
            "semicolon", "quote", "comma", "period", "slash", "backtick",
        ]
        let special = [
            "pageUp", "pageDown", "home", "end", "forwardDelete",
            "space", "enter", "esc", "backspace", "tab", "left", "down", "up", "right",
        ]
        return Set(letters + digits + functionKeys + keypad + punctuation + special)
    }()
}
