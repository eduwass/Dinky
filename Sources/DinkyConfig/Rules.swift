import Foundation

/// One `[[on-window-detected]]` entry: when a new window matches `if`, run the commands.
/// Key names follow AeroSpace; `window-kind` is dinky's own.
public struct WindowRule: Equatable {
    public var matcher = WindowMatcher()
    public var checkFurtherCallbacks = false
    public var run: [String] = []

    public init() {}

    init(_ t: Table) throws {
        matcher = try t.table("if").map(WindowMatcher.init) ?? matcher
        checkFurtherCallbacks = try t.bool("check-further-callbacks") ?? checkFurtherCallbacks
        guard let run = try t.commands("run") else { throw ConfigError(path: t.path("run"), "missing, every rule needs 'run'") }
        self.run = run
        try t.done()
    }
}

/// Every condition that is set must hold. Regexes are case-insensitive substring matches, as in AeroSpace.
public struct WindowMatcher: Equatable {
    public var appId: String?
    public var appNameRegexSubstring: String?
    public var windowTitleRegexSubstring: String?
    public var windowKind: WindowKind?

    public init() {}

    init(_ t: Table) throws {
        appId = try t.string("app-id")
        appNameRegexSubstring = try regex(t, "app-name-regex-substring")
        windowTitleRegexSubstring = try regex(t, "window-title-regex-substring")
        windowKind = try t.choice("window-kind")
        try t.done()
    }
}

private func regex(_ t: Table, _ key: String) throws -> String? {
    guard let pattern = try t.string(key) else { return nil }
    if (try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)) == nil {
        throw ConfigError(path: t.path(key), "'\(pattern)' is not a valid regex")
    }
    return pattern
}

public enum WindowKind: String, CaseIterable {
    case normal, dialog, sheet, panel
}

/// `[mode.<name>.binding]`: key combos mapped to the commands they run, in order.
public struct Mode: Equatable {
    public var bindings: [KeyCombo: [String]] = [:]

    public init() {}

    init(_ t: Table) throws {
        if let table = try t.table("binding") {
            for key in table.keys {
                let combo: KeyCombo
                do {
                    combo = try KeyCombo(key)
                } catch {
                    throw ConfigError(path: table.path(key), error.message)
                }
                if bindings[combo] != nil {
                    throw ConfigError(path: table.path(key), "'\(combo)' is bound twice")
                }
                bindings[combo] = try table.commands(key)
            }
        }
        try t.done()
    }
}
