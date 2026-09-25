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
            description: "Move the focused window to the next or previous display. With --follow, focus it there."),
        Doc(syntax: "focus <left|down|up|right>",
            description: "Focus the nearest window in a direction."),
        Doc(syntax: "move <left|down|up|right>",
            description: "Move the focused window in a direction within the layout tree."),
        Doc(syntax: "join-with <left|down|up|right>",
            description: "Put the focused window and its neighbour in a new container."),
        Doc(syntax: "resize <smart|width|height> <+N|-N>",
            description: "Grow or shrink the focused window by N points."),
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
        Doc(syntax: "list-windows",
            description: "Print windows: id, app, title, frame, workspace and display."),
        Doc(syntax: "list-workspaces",
            description: "Print each display's workspaces, marking the current one."),
        Doc(syntax: "list-displays",
            description: "Print displays: index, id, UUID and whether it is the main one."),
    ]
}
