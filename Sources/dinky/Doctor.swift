import AppKit
import DinkyCommands
import DinkyConfig
import DinkyPrivate

// `dinky doctor [--config <path>]`: checks the config and the environment without needing the app. Exit 1 on errors.
func runDoctor(_ args: [String]) -> Int32 {
    var errors = 0, warnings = 0
    func ok(_ text: String) { print("  ok: \(text)") }
    func warn(_ text: String) { warnings += 1; print("  warning: \(text)") }
    func fail(_ text: String) { errors += 1; print("  error: \(text)") }

    let os = ProcessInfo.processInfo.operatingSystemVersion
    print("dinky doctor")
    print("  macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion), dinky was built against 27.0")

    var url = Config.userConfigURL
    if let i = args.firstIndex(of: "--config"), i + 1 < args.count { url = URL(fileURLWithPath: args[i + 1]) }
    print("  config: \(url.path)")
    var config = Config.default
    if !FileManager.default.fileExists(atPath: url.path) {
        warn("no config file yet; the app writes the default one on first run")
    } else {
        do {
            config = try Config.load(from: url)
            ok("parses: \(config.workspaces) workspaces per display, \(config.modes.count) modes, \(config.onWindowDetected.count) window rules")
        } catch {
            fail("\(error)")
        }
    }
    for finding in checkConfig(config, keyIsKnown: { keyCodes[$0] != nil }) {
        finding.level == .error ? fail(finding.message) : warn(finding.message)
    }
    if let program = config.execOnWorkspaceChange.first, !program.isEmpty, !programExists(program) {
        warn("exec-on-workspace-change: '\(program)' was not found on PATH")
    }

    // Dock settings the design depends on. Both default to on when unset.
    if dockSetting("mru-spaces") ?? true {
        warn("\"Automatically rearrange Spaces based on most recent use\" is on; workspace numbers will move around. Turn it off in System Settings > Desktop & Dock")
    } else {
        ok("Spaces are not auto-rearranged")
    }
    if config.switching.followAppActivation {
        if dockSetting("workspaces-auto-swoosh") ?? true {
            warn("\"When switching to an application, switch to a Space with open windows\" is on; Cmd-Tab will use macOS's slow switch instead of dinky's. The app's onboarding can turn it off")
        } else {
            ok("Cmd-Tab switching goes through dinky")
        }
    }

    for (i, display) in dinky_displays().enumerated() {
        let user = display.spaces.filter(\.isUser).count
        if user < config.workspaces {
            ok("display \(i + 1) has \(user) of \(config.workspaces) workspaces; the app creates the rest on start")
        } else {
            ok("display \(i + 1) has \(user) workspaces")
        }
    }

    ok(AXIsProcessTrusted() ? "this terminal has Accessibility (the app needs its own grant)" : "this terminal has no Accessibility grant; only the app needs one")
    if let reply = sendToApp("list-monitors --focused --format '%{monitor-name}'"), reply.ok {
        ok("app is running, focused display: \(reply.text)")
    } else {
        warn("app is not running (\(socketPath))")
    }

    print("\(errors) errors, \(warnings) warnings")
    return errors == 0 ? 0 : 1
}

private func dockSetting(_ key: String) -> Bool? {
    CFPreferencesCopyAppValue(key as CFString, "com.apple.dock" as CFString) as? Bool
}

private func programExists(_ program: String) -> Bool {
    if program.contains("/") { return FileManager.default.isExecutableFile(atPath: program) }
    let path = (ProcessInfo.processInfo.environment["PATH"] ?? "") + ":/opt/homebrew/bin:/usr/local/bin"
    return path.split(separator: ":").contains { FileManager.default.isExecutableFile(atPath: "\($0)/\(program)") }
}
