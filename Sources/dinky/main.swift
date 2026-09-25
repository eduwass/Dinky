import Foundation

let usage = "usage: dinky ls | switch <space-index> | move <window-id> <space-index> [--follow] | focus <window-id> | tile | hotkeys | app\n"

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    fputs(usage, stderr)
    exit(64)
}

let rest = Array(args.dropFirst())
switch command {
case "ls": exit(runLs(rest))
case "switch": exit(runSwitch(rest))
case "move": exit(runMove(rest))
case "focus": exit(runFocus(rest))
case "tile": exit(runTile(rest))
case "hotkeys": exit(runHotkeys(rest))
case "app": exit(runApp(rest))
default:
    fputs(usage, stderr)
    exit(64)
}
