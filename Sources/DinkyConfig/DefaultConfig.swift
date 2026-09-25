// The config dinky ships with: the PLAN.md draft with every binding written out.

extension Config {
    public static let defaultTOML = """
    config-version = 1
    start-at-login = true
    auto-reload-config = true
    workspaces = 5                 # per display; dinky creates missing Spaces, never removes

    [layout]
    default = 'tiles'              # tiles | accordion
    accordion-padding = 30

    [gaps]
    inner = 8
    outer = { top = 8, bottom = 8, left = 8, right = 8 }

    [borders]
    enabled = true
    width = 4
    active-color = '#e1e3e4'
    inactive-color = '#494d64'
    style = 'round'                # round | square
    order = 'below'                # below | above (a click-through ring over the window)
    exclude-apps = []              # bundle IDs that get no border
    only-apps = []                 # when set, only these bundle IDs get borders

    [switching]
    follow-app-activation = true   # Cmd-Tab and Dock clicks go through the fast switch

    [[on-window-detected]]
    if.app-id = 'com.apple.systempreferences'
    run = 'layout floating'

    [mode.main.binding]
    ctrl-left = 'workspace prev'
    ctrl-right = 'workspace next'
    alt-1 = 'workspace 1'
    alt-2 = 'workspace 2'
    alt-3 = 'workspace 3'
    alt-4 = 'workspace 4'
    alt-5 = 'workspace 5'
    alt-6 = 'workspace 6'
    alt-7 = 'workspace 7'
    alt-8 = 'workspace 8'
    alt-9 = 'workspace 9'
    alt-shift-1 = 'move-window-to-workspace 1'
    alt-shift-2 = 'move-window-to-workspace 2'
    alt-shift-3 = 'move-window-to-workspace 3'
    alt-shift-4 = 'move-window-to-workspace 4'
    alt-shift-5 = 'move-window-to-workspace 5'
    alt-shift-6 = 'move-window-to-workspace 6'
    alt-shift-7 = 'move-window-to-workspace 7'
    alt-shift-8 = 'move-window-to-workspace 8'
    alt-shift-9 = 'move-window-to-workspace 9'
    alt-tab = 'workspace-back-and-forth'
    alt-h = 'focus left'
    alt-j = 'focus down'
    alt-k = 'focus up'
    alt-l = 'focus right'
    alt-shift-h = 'move left'
    alt-shift-j = 'move down'
    alt-shift-k = 'move up'
    alt-shift-l = 'move right'
    alt-minus = 'resize smart -50'
    alt-equal = 'resize smart +50'
    alt-f = 'fullscreen'
    alt-shift-f = 'layout floating tiling'
    alt-comma = 'layout accordion'
    alt-slash = 'layout tiles'
    alt-shift-n = 'move-window-to-display next'
    alt-shift-semicolon = 'mode service'

    [mode.service.binding]
    esc = ['reload-config', 'mode main']
    r = ['flatten-workspace-tree', 'mode main']
    alt-shift-h = ['join-with left', 'mode main']
    alt-shift-j = ['join-with down', 'mode main']
    alt-shift-k = ['join-with up', 'mode main']
    alt-shift-l = ['join-with right', 'mode main']
    """
}
