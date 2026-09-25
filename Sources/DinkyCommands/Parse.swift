import DinkyLayout

/// A command string that does not parse. `description` names the string and the accepted form.
public struct CommandError: Error, Equatable, CustomStringConvertible {
    public let input: String
    public let message: String

    public var description: String { message }
}

extension Command {
    /// Parses a command string such as `workspace 3`, `move-window-to-workspace 3 --follow` or `focus left`.
    public static func parse(_ string: String) throws(CommandError) -> Command {
        let words = string.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let name = words.first else {
            throw CommandError(input: string, message: "empty command")
        }
        guard let doc = all.first(where: { $0.name == name }) else {
            let names = all.map(\.name).joined(separator: ", ")
            throw CommandError(input: string, message: "unknown command '\(string)', expected one of: \(names)")
        }
        guard let command = parse(name, Array(words.dropFirst())) else {
            throw CommandError(input: string, message: "can't parse '\(string)', expected '\(doc.syntax)'")
        }
        return command
    }

    private static func parse(_ name: String, _ args: [String]) -> Command? {
        let none = args.isEmpty
        let one = args.count == 1 ? args[0] : nil
        switch name {
        case "workspace":
            return one.flatMap(workspaceTarget).map { .workspace($0) }
        case "workspace-back-and-forth":
            return none ? .workspaceBackAndForth : nil
        case "move-window-to-workspace":
            let (rest, follow) = followFlag(args)
            guard rest.count == 1, let target = workspaceTarget(rest[0]) else { return nil }
            return .moveWindowToWorkspace(target, follow: follow)
        case "move-window-to-display":
            let (rest, follow) = followFlag(args)
            guard rest.count == 1, let target = DisplayTarget(rawValue: rest[0]) else { return nil }
            return .moveWindowToDisplay(target, follow: follow)
        case "focus":
            return one.flatMap(Direction.init).map { .focus($0) }
        case "move":
            return one.flatMap(Direction.init).map { .move($0) }
        case "join-with":
            return one.flatMap(Direction.init).map { .joinWith($0) }
        case "resize":
            guard args.count == 2, let dimension = ResizeDimension(rawValue: args[0]),
                  args[1].hasPrefix("+") || args[1].hasPrefix("-"), let delta = Int(args[1]) else { return nil }
            return .resize(dimension, by: delta)
        case "layout":
            let layouts = args.compactMap(LayoutName.init(rawValue:))
            guard !none, layouts.count == args.count else { return nil }
            return .layout(layouts)
        case "fullscreen":
            return none ? .fullscreen : nil
        case "flatten-workspace-tree":
            return none ? .flattenWorkspaceTree : nil
        case "retile":
            return none ? .retile : nil
        case "mode":
            return one.map { .mode($0) }
        case "reload-config":
            return none ? .reloadConfig : nil
        case "enable":
            return one.flatMap(Toggle.init(rawValue:)).map { .enable($0) }
        case "list-windows":
            return none ? .listWindows : nil
        case "list-workspaces":
            return none ? .listWorkspaces : nil
        case "list-displays":
            return none ? .listDisplays : nil
        default:
            return nil
        }
    }

    private static func workspaceTarget(_ word: String) -> WorkspaceTarget? {
        switch word {
        case "prev": return .prev
        case "next": return .next
        default:
            guard let n = Int(word), n >= 1 else { return nil }
            return .number(n)
        }
    }

    private static func followFlag(_ args: [String]) -> (rest: [String], follow: Bool) {
        (args.filter { $0 != "--follow" }, args.contains("--follow"))
    }
}
