// Values that differ per display, as AeroSpace's gaps do: `44`, or a list such as
// `[{ monitor."built-in" = 12 }, { monitor.main = 44 }, 8]`. Entries are tried in order; the first
// whose pattern matches the display wins, and a bare number matches every display.

/// What a monitor pattern is matched against. dinky fills it in per display.
public struct Monitor: Equatable {
    /// The display's name, such as "Built-in Retina Display" or "DELL U2723QE".
    public var name: String
    /// Whether this is the main display (System Settings, Displays, "Use as: Main display").
    public var isMain: Bool
    /// How many displays there are.
    public var count: Int

    public init(name: String, isMain: Bool, count: Int) {
        self.name = name
        self.isMain = isMain
        self.count = count
    }
}

/// `main`, `secondary` (the non-main display when there are exactly two), or a case-insensitive
/// substring of the display's name, such as `built-in` or `dell`. AeroSpace takes a regex here; a
/// substring covers the common patterns.
public enum MonitorPattern: Equatable {
    case main, secondary
    case name(String)

    init(_ text: String) {
        switch text {
        case "main": self = .main
        case "secondary": self = .secondary
        default: self = .name(text)
        }
    }

    public func matches(_ monitor: Monitor) -> Bool {
        switch self {
        case .main: monitor.isMain
        case .secondary: monitor.count == 2 && !monitor.isMain
        case .name(let text): monitor.name.localizedCaseInsensitiveContains(text)
        }
    }
}

public struct PerMonitor: Equatable, ExpressibleByIntegerLiteral {
    public struct Entry: Equatable {
        /// Nil for a bare number, which matches every display.
        public var pattern: MonitorPattern?
        public var value: Int

        public init(_ pattern: MonitorPattern?, _ value: Int) {
            self.pattern = pattern
            self.value = value
        }
    }

    public var entries: [Entry]

    public init(_ entries: [Entry]) { self.entries = entries }
    public init(_ value: Int) { self.init([Entry(nil, value)]) }
    public init(integerLiteral value: Int) { self.init(value) }

    /// The first matching entry's value, 0 if none matches.
    public func value(for monitor: Monitor) -> Int {
        entries.first { $0.pattern?.matches(monitor) ?? true }?.value ?? 0
    }
}

extension Table {
    /// A number, or a list of numbers and `{ monitor.<pattern> = number }` tables.
    func perMonitor(_ key: String) throws -> PerMonitor? {
        guard contains(key) else { return nil }
        if let value = try? int(key) { return PerMonitor(value) }
        let error = ConfigError(path: path(key), "expected a number or a list of numbers and { monitor.<pattern> = number } tables")
        guard let array = try array(key) else { throw error }
        return PerMonitor(try (0..<array.count).map { index in
            if let value = try? array.integer(atIndex: index) { return PerMonitor.Entry(nil, Int(value)) }
            guard let nested = try? array.table(atIndex: index) else { throw error }
            let entry = Table(nested, path: "\(path(key))[\(index)]")
            guard let monitor = try entry.table("monitor"), monitor.keys.count == 1, let pattern = monitor.keys.first else {
                throw ConfigError(path: entry.path, "expected { monitor.<pattern> = number }")
            }
            let value = try monitor.int(pattern)!
            try entry.done()
            return PerMonitor.Entry(MonitorPattern(pattern), value)
        })
    }
}
