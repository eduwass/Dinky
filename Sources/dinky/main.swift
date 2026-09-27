import Foundation

/// `~/Library/Logs/dinky.log`, where the app launched from its bundle writes what `dinky app` prints to the terminal.
let logURL = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/dinky.log")

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    // Launched from the app bundle with no arguments: run the menu bar app, logging to a file.
    if Bundle.main.bundleIdentifier != nil {
        if (try? logURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 > 5_000_000 {
            try? FileManager.default.removeItem(at: logURL)
        }
        for stream in [stdout, stderr] { freopen(logURL.path, "a", stream); setlinebuf(stream) }
        exit(runApp())
    }
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
