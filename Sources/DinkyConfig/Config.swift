import Foundation
import TOMLDecoder

// Config types and TOML loading. No AppKit here.
// Shape and key names follow AeroSpace's config (MIT, github.com/nikitabobko/AeroSpace) where
// dinky has the same feature. TOML keys are kebab-case, Swift properties camelCase.
// Every key is optional; the defaults are the property initial values.

public struct Config: Equatable {
    public var configVersion = 1
    public var startAtLogin = false
    public var autoReloadConfig = true
    /// Spaces per display. dinky creates missing ones and never removes any.
    public var workspaces = 5
    public var layout = Layout()
    public var gaps = Gaps()
    public var borders = Borders()
    public var switching = Switching()
    public var onWindowDetected: [WindowRule] = []
    /// Keyed by mode name, e.g. `main`, `service`.
    public var modes: [String: Mode] = [:]
    /// A program and its arguments, run when a display's current workspace changes.
    public var execOnWorkspaceChange: [String] = []
    /// Commands run when the focused window changes.
    public var onFocusChanged: [String] = []
    /// Commands run when the binding mode changes.
    public var onModeChanged: [String] = []
    /// Commands run once, after dinky has first read the windows and displays.
    public var afterStartupCommand: [String] = []

    public init() {}

    /// `~/.config/dinky/dinky.toml`
    public static var userConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/dinky/dinky.toml")
    }

    /// The config shipped with dinky, used when the user has none.
    public static let `default` = try! parse(defaultTOML)

    public static func load(from url: URL) throws(ConfigError) -> Config {
        let toml: String
        do {
            toml = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ConfigError("can't read \(url.path): \(error.localizedDescription)")
        }
        return try parse(toml)
    }

    public static func parse(_ toml: String) throws(ConfigError) -> Config {
        let root: TOMLTable
        do {
            root = try TOMLTable(source: toml)
        } catch {
            // Syntax errors; TOMLDecoder's text already carries the line.
            throw ConfigError("\(error)")
        }
        do {
            return try Config(Table(root))
        } catch let error as ConfigError {
            var error = error
            error.line = error.line ?? lineNumber(of: error.path, in: toml)
            throw error
        } catch {
            throw ConfigError("\(error)")
        }
    }

    init(_ t: Table) throws {
        configVersion = try t.int("config-version") ?? configVersion
        guard configVersion == 1 else {
            throw ConfigError(path: "config-version", "unsupported version \(configVersion), expected 1")
        }
        startAtLogin = try t.bool("start-at-login") ?? startAtLogin
        autoReloadConfig = try t.bool("auto-reload-config") ?? autoReloadConfig
        workspaces = try t.int("workspaces") ?? workspaces
        guard workspaces >= 1 else { throw ConfigError(path: "workspaces", "must be at least 1") }
        layout = try t.table("layout").map(Layout.init) ?? layout
        gaps = try t.table("gaps").map(Gaps.init) ?? gaps
        borders = try t.table("borders").map(Borders.init) ?? borders
        switching = try t.table("switching").map(Switching.init) ?? switching
        onWindowDetected = try t.tables("on-window-detected")?.map(WindowRule.init) ?? []
        execOnWorkspaceChange = try t.strings("exec-on-workspace-change") ?? []
        onFocusChanged = try t.strings("on-focus-changed") ?? []
        onModeChanged = try t.strings("on-mode-changed") ?? []
        afterStartupCommand = try t.strings("after-startup-command") ?? []
        if let modeTable = try t.table("mode") {
            for name in modeTable.keys {
                modes[name] = try Mode(modeTable.table(name)!)
            }
        }
        try t.done()
    }
}

public enum LayoutKind: String, CaseIterable {
    case tiles, accordion
}

public struct Layout: Equatable {
    public var `default` = LayoutKind.tiles
    public var accordionPadding = 30

    public init() {}

    init(_ t: Table) throws {
        self.default = try t.choice("default") ?? self.default
        accordionPadding = try t.int("accordion-padding") ?? accordionPadding
        try t.done()
    }
}

/// Gaps in points. Each value is a number or a per-display list, see `PerMonitor`.
public struct Gaps: Equatable {
    public var inner = Inner(8)
    public var outer = Sides(8)

    public init() {}

    init(_ t: Table) throws {
        // `inner = 8`, or AeroSpace's `inner.horizontal = 8` and `inner.vertical = 8`.
        if t.isTable("inner") {
            inner = try Inner(t.table("inner")!)
        } else {
            inner = try t.perMonitor("inner").map(Inner.init) ?? inner
        }
        // `outer = 8`, or per side: `outer = { top = 8, ... }`, `outer.top = 8`.
        if t.isTable("outer") {
            outer = try Sides(t.table("outer")!)
        } else {
            outer = try t.perMonitor("outer").map(Sides.init) ?? outer
        }
        try t.done()
    }
}

/// The gap between side-by-side windows (`horizontal`) and between stacked ones (`vertical`).
public struct Inner: Equatable {
    public var horizontal, vertical: PerMonitor

    public init(_ both: PerMonitor) { (horizontal, vertical) = (both, both) }

    init(_ t: Table) throws {
        horizontal = try t.perMonitor("horizontal") ?? 0
        vertical = try t.perMonitor("vertical") ?? 0
        try t.done()
    }
}

/// Per-side gaps. Sides left out of a table are 0.
public struct Sides: Equatable {
    public var top, bottom, left, right: PerMonitor

    public init(_ all: PerMonitor) { (top, bottom, left, right) = (all, all, all, all) }

    init(_ t: Table) throws {
        top = try t.perMonitor("top") ?? 0
        bottom = try t.perMonitor("bottom") ?? 0
        left = try t.perMonitor("left") ?? 0
        right = try t.perMonitor("right") ?? 0
        try t.done()
    }
}

public enum BorderStyle: String, CaseIterable {
    case round, square
}

/// Below the target, or above it as a ring that never covers content or takes clicks.
public enum BorderOrder: String, CaseIterable {
    case below, above
}

public struct Borders: Equatable {
    public var enabled = true
    public var width = 4.0
    public var activeColor = try! Color(hex: "#e1e3e4")
    public var inactiveColor = try! Color(hex: "#494d64")
    public var style = BorderStyle.round
    public var order = BorderOrder.below
    /// Bundle IDs whose windows get no border.
    public var excludeApps: [String] = []
    /// Bundle IDs that alone get borders, when not empty.
    public var onlyApps: [String] = []

    public init() {}

    init(_ t: Table) throws {
        enabled = try t.bool("enabled") ?? enabled
        width = try t.double("width") ?? width
        activeColor = try t.color("active-color") ?? activeColor
        inactiveColor = try t.color("inactive-color") ?? inactiveColor
        style = try t.choice("style") ?? style
        order = try t.choice("order") ?? order
        excludeApps = try t.strings("exclude-apps") ?? excludeApps
        onlyApps = try t.strings("only-apps") ?? onlyApps
        try t.done()
    }

    /// Whether windows of the app with this bundle ID get a border.
    public func decorates(bundleID: String?) -> Bool {
        if !onlyApps.isEmpty { return bundleID.map(onlyApps.contains) ?? false }
        return !(bundleID.map(excludeApps.contains) ?? false)
    }
}

public struct Switching: Equatable {
    /// Cmd-Tab and Dock clicks go through the fast switch.
    public var followAppActivation = true

    public init() {}

    init(_ t: Table) throws {
        followAppActivation = try t.bool("follow-app-activation") ?? followAppActivation
        try t.done()
    }
}
