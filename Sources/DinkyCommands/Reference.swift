// The command reference: one line of syntax and one of description per command, in the order a user
// would look for them. Parse errors quote the syntax from here, and the docs are generated from it.

extension Command {
    public struct Doc: Equatable, Sendable {
        public let syntax: String
        public let description: String

        /// The command name, the first word of the syntax.
        public var name: String { String(syntax.prefix { $0 != " " }) }
    }

    public static let all: [Doc] = [
        Doc(syntax: "workspace <number|prev|next>",
            description: "Switch the focused display to a workspace (a native Space), numbered from 1."),
        Doc(syntax: "workspace-back-and-forth",
            description: "Switch to the workspace that was focused before the current one."),
        Doc(syntax: "move-window-to-workspace <number|prev|next> [--follow]",
            description: "Move the focused window to a workspace. With --follow, switch there too."),
        Doc(syntax: "move-window-to-display <next|prev> [--follow]",
            description: "Move the focused window to the next or previous display's current workspace. With --follow, focus it there."),
        Doc(syntax: "focus <left|down|up|right>",
            description: "Focus the neighbouring window in a direction in the layout tree. Never switches workspace."),
        Doc(syntax: "move <left|down|up|right>",
            description: "Move the focused window in a direction within the layout tree."),
        Doc(syntax: "join-with <left|down|up|right>",
            description: "Put the focused window and its neighbour in a new container."),
        Doc(syntax: "resize <smart|width|height> <+N|-N>",
            description: "Grow or shrink the focused window by N points: smart along its container, width or height along that axis."),
        Doc(syntax: "layout <tiles|accordion|floating|tiling>...",
            description: "Set the layout of the focused window's container, or float or tile the window. "
                + "With several, apply the first that is not current, so 'layout floating tiling' toggles."),
        Doc(syntax: "fullscreen",
            description: "Toggle the focused window filling the workspace. The tree is kept."),
        Doc(syntax: "flatten-workspace-tree",
            description: "Put every window on the workspace back into one flat container."),
        Doc(syntax: "retile",
            description: "Re-read every window and re-apply the layout of every workspace on screen."),
        Doc(syntax: "mode <name>",
            description: "Switch to a binding mode from the config, such as 'main' or 'service'."),
        Doc(syntax: "reload-config",
            description: "Reload ~/.config/dinky/dinky.toml. On an error the previous config stays."),
        Doc(syntax: "enable <on|off|toggle>",
            description: "Turn dinky's key bindings and app-activation following on or off."),
        Doc(syntax: "list-workspaces [--all|--focused|--monitor <focused|all|n>...] [--visible [no]] [--empty [no]] [--format <format>]",
            description: "Print workspace numbers, one per line, of the focused display by default. --all covers every display, "
                + "so numbers repeat unless --format adds %{monitor-id}. --focused prints the focused workspace. "
                + "Format variables: " + vars(WorkspaceQuery.variables) + "."),
        Doc(syntax: "list-windows [--all|--focused|--monitor <focused|all|n>...] [--workspace <focused|visible|n>...] "
                + "[--app-bundle-id <id>] [--format <format>]",
            description: "Print windows as 'id | app | title', of the focused display by default. --focused prints the focused window. "
                + "Format variables: " + vars(WindowQuery.variables) + "."),
        Doc(syntax: "list-monitors [--focused [no]] [--format <format>]",
            description: "Print displays as 'number | name'. Format variables: " + vars(MonitorQuery.variables) + "."),
        Doc(syntax: "list-displays [--focused [no]] [--format <format>]",
            description: "The same as list-monitors."),
        Doc(syntax: "exec-and-forget <shell command>",
            description: "Run the rest of the line with /bin/sh -c without waiting. Its output goes to dinky's log."),
    ]
}

private func vars(_ names: [String]) -> String {
    (names + ["right-padding", "newline", "tab"]).map { "%{\($0)}" }.joined(separator: ", ")
}
