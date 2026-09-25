import DinkyCommands
import Foundation

// `dinky <command>`: checks the command, sends it to the running app and prints the reply.
func runCli(_ args: [String]) -> Int32 {
    let line = args.joined(separator: " ")
    do {
        _ = try Command.parse(line)
    } catch {
        fputs("dinky: \(error)\n", stderr)
        return 1
    }
    guard let reply = sendToApp(line) else {
        fputs("dinky: app is not running (\(socketPath))\n", stderr)
        return 1
    }
    if !reply.text.isEmpty { fputs(reply.text + "\n", reply.ok ? stdout : stderr) }
    return reply.ok ? 0 : 1
}

// `dinky help`: the command reference.
func runHelp() -> Int32 {
    print("usage: dinky <command>, sent to the running app over \(socketPath)\n")
    for doc in Command.all {
        print("  \(doc.syntax)\n      \(doc.description)")
    }
    print("\ncommand line only:")
    print("  app\n      Run the app in the foreground, logging to the terminal.")
    print("  recover\n      Ask the running app to restore windows a crashed session left tiled.")
    print("  debug events|windows\n      Print the live window event stream, or the current windows, for bug reports.")
    return 0
}
