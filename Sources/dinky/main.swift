import Foundation

let usage = "usage: dinky <command> (see dinky help) | app\n"

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    // Launched from the app bundle with no arguments: run the menu bar app.
    if Bundle.main.bundleIdentifier != nil { exit(runApp([])) }
    fputs(usage, stderr)
    exit(64)
}

let rest = Array(args.dropFirst())
switch command {
case "ls": exit(runLs(rest))
case "switch": exit(runSwitch(rest))
// The spike's `move` and `focus` take a window id; with a direction they are commands for the app.
case "move" where rest == ["--check"] || UInt32(rest.first ?? "") != nil: exit(runMove(rest))
case "focus" where UInt32(rest.first ?? "") != nil: exit(runFocus(rest))
case "tile": exit(runTile(rest))
case "hotkeys": exit(runHotkeys(rest))
case "app": exit(runApp(rest))
case "spaces": exit(runSpaces(rest))
case "events": exit(runEvents(rest))
case "borders": exit(runBorders(rest))
case "recover": exit(runRecover())
case "help", "--help", "-h": exit(runHelp())
default: exit(runCli(args))
}
