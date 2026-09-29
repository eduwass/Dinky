import Foundation
import TOMLDecoder

// Config types and TOML loading. No AppKit here.
// TOML keys are kebab-case, Swift properties camelCase. Every key is optional; the defaults are the
// property initial values, and the shipped file (DefaultConfig.swift) spells out the same values.

public struct Config: Equatable {
    public var startAtLogin = true
    /// Workspaces across all displays, numbered from 1. Each is one native Space.
    public var workspaces = 5
    /// `[workspace-to-display]`: by workspace number, the display patterns it lives on, the first that matches
    /// a connected display winning. Other workspaces, and these when no pattern matches, live on the main display.
    public var workspaceDisplays: [Int: [MonitorPattern]] = [:]
    /// Workspace layout, with 'tiles' retained as the old name for dwindle.
    public var defaultLayout = LayoutKind.tiles
    /// Whether dinky tiles numbered workspaces unless overridden.
    public var defaultTiling = true
    /// Workspace numbers (1-based) with their own tiling settings.
    public var workspaceLayouts: [Int: WorkspaceLayout] = [:]
    /// Cmd-Tab and Dock clicks go through the fast switch.
    public var followAppActivation = true
    public var accordion = Accordion()
    public var gaps = Gaps()
    /// `[display.<pattern>]` overrides, in file order.
    public var displays: [DisplayOverride] = []
    public var borders = Borders()
    public var focusFollowsMouse = FocusFollowsMouse()
    public var hooks = Hooks()
    /// `[[rules]]`, in file order.
    public var rules: [WindowRule] = []
    /// Keyed by mode name, e.g. `main`, `service`.
    public var modes: [String: Mode] = [:]

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
        startAtLogin = try t.bool("start-at-login") ?? startAtLogin
        workspaces = try t.int("workspaces") ?? workspaces
        guard workspaces >= 1 else { throw ConfigError(path: "workspaces", "must be at least 1") }
        if let assignments = try t.table("workspace-to-display") {
            for key in assignments.keys {
                guard let n = Int(key), (1...workspaces).contains(n) else {
                    throw ConfigError(path: assignments.path(key), "'\(key)' is not a workspace number from 1 to \(workspaces)")
                }
                let patterns = try assignments.stringOrStrings(key)!
                guard !patterns.isEmpty, !patterns.contains("") else {
                    throw ConfigError(path: assignments.path(key), "a display pattern can't be empty")
                }
                workspaceDisplays[n] = patterns.map(MonitorPattern.init)
            }
            try assignments.done()
        }
        defaultLayout = try t.choice("default-layout") ?? defaultLayout
        defaultTiling = try t.bool("default-tiling") ?? defaultTiling
        if let workspacesTable = try t.table("workspace") {
            for number in workspacesTable.keys {
                guard let index = Int(number), index > 0, String(index) == number else {
                    throw ConfigError(path: workspacesTable.path(number), "expected a positive workspace number")
                }
                let settings = try WorkspaceLayout(workspacesTable.table(number)!)
                if (settings.columns != nil || settings.rows != nil || settings.expand != nil)
                    && (settings.layout ?? defaultLayout) != .fixed {
                    let key = settings.columns != nil ? "columns" : settings.rows != nil ? "rows" : "expand"
                    throw ConfigError(path: workspacesTable.path("\(number).\(key)"), "only valid for a fixed layout")
                }
                workspaceLayouts[index] = settings
            }
        }
        followAppActivation = try t.bool("follow-app-activation") ?? followAppActivation
        accordion = try t.table("accordion").map(Accordion.init) ?? accordion
        gaps = try t.table("gaps").map { try gaps.applying(GapsPatch($0)) } ?? gaps
        if let displayTable = try t.table("display") {
            for pattern in displayTable.keys {
                displays.append(try DisplayOverride(pattern, displayTable.table(pattern)!))
            }
        }
        borders = try t.table("borders").map(Borders.init) ?? borders
        focusFollowsMouse = try t.table("focus-follows-mouse").map(FocusFollowsMouse.init) ?? focusFollowsMouse
        hooks = try t.table("hooks").map(Hooks.init) ?? hooks
        rules = try t.tables("rules")?.map(WindowRule.init) ?? []
        if let modeTable = try t.table("mode") {
            for name in modeTable.keys {
                modes[name] = try Mode(modeTable.table(name)!)
            }
        }
        try t.done()
    }
}

public enum LayoutKind: String, CaseIterable {
    case tiles, dwindle, accordion, fixed
}

public enum ExpansionKind: String, CaseIterable {
    case rows, columns, accordion
}

/// A `[workspace.N]` override. Omitted keys inherit the top-level settings.
public struct WorkspaceLayout: Equatable {
    public var tiling: Bool?
    public var layout: LayoutKind?
    public var columns: Int?
    public var rows: Int?
    public var expand: ExpansionKind?

    init(_ t: Table) throws {
        tiling = try t.bool("tiling")
        layout = try t.choice("layout")
        columns = try t.int("columns")
        rows = try t.int("rows")
        expand = try t.choice("expand")
        if let columns, columns < 1 { throw ConfigError(path: t.path("columns"), "must be at least 1") }
        if let rows, rows < 1 { throw ConfigError(path: t.path("rows"), "must be at least 1") }
        try t.done()
    }
}

extension Config {
    public func tiling(forWorkspace number: Int) -> Bool {
        workspaceLayouts[number]?.tiling ?? defaultTiling
    }

    public func layout(forWorkspace number: Int) -> LayoutKind {
        workspaceLayouts[number]?.layout ?? defaultLayout
    }

    public func fixedRows(forWorkspace number: Int) -> Int {
        workspaceLayouts[number]?.rows ?? 1
    }

    public func fixedColumns(forWorkspace number: Int) -> Int {
        workspaceLayouts[number]?.columns ?? 1
    }

    public func expansion(forWorkspace number: Int) -> ExpansionKind {
        workspaceLayouts[number]?.expand ?? .columns
    }
}

/// What a container's orientation becomes when it switches to accordion: `auto`, following its longer side,
/// or `keep`, the orientation it had. An orientation chosen with a `layout` command is always kept.
public enum AccordionOrientation: String, CaseIterable {
    case auto, keep
}

public struct Accordion: Equatable {
    /// Points by which neighbouring windows peek out.
    public var padding = 30
    public var orientation = AccordionOrientation.auto

    public init() {}

    init(_ t: Table) throws {
        padding = try t.int("padding") ?? padding
        orientation = try t.choice("orientation") ?? orientation
        try t.done()
    }
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
    public var order = BorderOrder.below
    /// Bundle IDs whose windows get no border.
    public var excludeApps: [String] = []

    public init() {}

    init(_ t: Table) throws {
        enabled = try t.bool("enabled") ?? enabled
        width = try t.double("width") ?? width
        activeColor = try t.color("active-color") ?? activeColor
        inactiveColor = try t.color("inactive-color") ?? inactiveColor
        order = try t.choice("order") ?? order
        excludeApps = try t.strings("exclude-apps") ?? excludeApps
        try t.done()
    }

    /// Whether windows of the app with this bundle ID get a border.
    public func decorates(bundleID: String?) -> Bool {
        !(bundleID.map(excludeApps.contains) ?? false)
    }
}

public struct FocusFollowsMouse: Equatable {
    public var enabled = false
    /// How long the pointer must rest on a window before it takes focus.
    public var delayMs = 100
    /// Whether resting on the peeking edge of an accordion child focuses it. Off, only the front child does.
    public var accordionEdges = true

    public init() {}

    init(_ t: Table) throws {
        enabled = try t.bool("enabled") ?? enabled
        delayMs = try t.int("delay-ms") ?? delayMs
        guard delayMs >= 0 else { throw ConfigError(path: t.path("delay-ms"), "must be 0 or more") }
        accordionEdges = try t.bool("accordion-edges") ?? accordionEdges
        try t.done()
    }
}

/// `[hooks]`: dinky commands run on events. Each is a command string or a list, empty by default.
public struct Hooks: Equatable {
    /// Once, after dinky has first read the windows and displays.
    public var startup: [String] = []
    /// When dinky starts switching a display to a workspace, or a switch in flight gets a new target.
    public var workspaceChanging: [String] = []
    /// When a display's current workspace changes, by dinky or natively, and when a dinky switch gives up.
    public var workspaceChanged: [String] = []
    /// When the focused window changes.
    public var focusChanged: [String] = []
    /// When the binding mode changes.
    public var modeChanged: [String] = []

    public init() {}

    init(_ t: Table) throws {
        startup = try t.commands("startup", allowEmpty: true) ?? startup
        workspaceChanging = try t.commands("workspace-changing", allowEmpty: true) ?? workspaceChanging
        workspaceChanged = try t.commands("workspace-changed", allowEmpty: true) ?? workspaceChanged
        focusChanged = try t.commands("focus-changed", allowEmpty: true) ?? focusChanged
        modeChanged = try t.commands("mode-changed", allowEmpty: true) ?? modeChanged
        try t.done()
    }
}
