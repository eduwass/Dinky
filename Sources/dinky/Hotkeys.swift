import AppKit
import DinkyConfig

// `dinky hotkeys`: the engine with the default config's bindings, printing each binding's commands
// instead of running them. Handles `mode <name>` itself so the service mode round trip is testable.
// `dinky hotkeys --check`: lists key names from the config vocabulary that have no keycode.
func runHotkeys(_ args: [String]) -> Int32 {
    if args.contains("--check") {
        let unmapped = KeyCombo.keyNames.filter { keyCodes[$0] == nil }.sorted()
        for name in unmapped { print(name) }
        print("\(unmapped.count) unmapped of \(KeyCombo.keyNames.count) key names")
        return unmapped.isEmpty ? 0 : 1
    }
    var engine: HotkeyEngine!
    engine = HotkeyEngine { commands in
        print("[\(engine.currentMode)] \(commands)")
        for command in commands where command.hasPrefix("mode ") {
            engine.setMode(String(command.dropFirst("mode ".count)))
        }
        fflush(stdout)
    }
    engine.load(modes: Config.default.modes)
    guard engine.start() else { return 1 }
    print("hotkeys: default bindings, printing commands")
    fflush(stdout)
    CFRunLoopRun()
    return 0
}
