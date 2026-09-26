import Foundation

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    // Launched from the app bundle with no arguments: run the menu bar app.
    if Bundle.main.bundleIdentifier != nil { exit(runApp()) }
    fputs("usage: dinky <command> (see dinky help) | app\n", stderr)
    exit(64)
}

let rest = Array(args.dropFirst())
switch command {
case "app": exit(runApp())
case "recover": exit(runRecover())
case "debug": exit(runDebug(rest))
case "doctor": exit(runDoctor(rest))
case "help", "--help", "-h": exit(runHelp())
case "version", "--version":
    let info = Bundle.main.infoDictionary
    print("dinky \(info?["CFBundleShortVersionString"] ?? "dev") (\(info?["CFBundleVersion"] ?? "0"))")
    exit(0)
default: exit(runCli(args))
}
