import DinkyConfig

/// A problem `dinky doctor` found in a config that still parsed.
public struct ConfigFinding: Equatable, CustomStringConvertible {
    public enum Level: String { case error, warning }
    public let level: Level
    public let message: String

    public var description: String { "\(level.rawValue): \(message)" }
}

/// Checks a parsed config beyond what parsing guarantees: every binding and rule command is in the
/// vocabulary, every `mode X` names a mode, every key name has a keycode, and there is a main mode.
/// `keyIsKnown` comes from the app's key table so this stays free of AppKit.
public func checkConfig(_ config: Config, keyIsKnown: (String) -> Bool) -> [ConfigFinding] {
    var findings: [ConfigFinding] = []
    func check(_ commands: [String], at place: String) {
        for text in commands {
            do {
                if case .mode(let name) = try Command.parse(text), config.modes[name] == nil {
                    findings.append(.init(level: .error, message: "\(place): '\(text)' names a mode that is not in the config"))
                }
            } catch {
                findings.append(.init(level: .error, message: "\(place): \(error)"))
            }
        }
    }
    if config.modes["main"] == nil {
        findings.append(.init(level: .warning, message: "no [mode.main.binding]: no key bindings are active"))
    }
    for (name, mode) in config.modes.sorted(by: { $0.key < $1.key }) {
        for (combo, commands) in mode.bindings.sorted(by: { $0.key.description < $1.key.description }) {
            let place = "mode.\(name).binding.\(combo)"
            if !keyIsKnown(combo.key) {
                findings.append(.init(level: .error, message: "\(place): unknown key '\(combo.key)'"))
            }
            check(commands, at: place)
        }
    }
    for (i, rule) in config.onWindowDetected.enumerated() {
        check(rule.run, at: "on-window-detected[\(i)].run")
    }
    check(config.onFocusChanged, at: "on-focus-changed")
    check(config.onModeChanged, at: "on-mode-changed")
    check(config.afterStartupCommand, at: "after-startup-command")
    if let program = config.execOnWorkspaceChange.first, program.isEmpty {
        findings.append(.init(level: .error, message: "exec-on-workspace-change: the first element must be the program"))
    }
    return findings
}
