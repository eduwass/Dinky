// The config draft from PLAN.md, verbatim.
let planDraft = """
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

    [switching]
    follow-app-activation = true   # Cmd-Tab and Dock clicks go through the fast switch

    [[on-window-detected]]
    if.app-id = 'com.apple.systempreferences'
    run = 'layout floating'

    [mode.main.binding]
    ctrl-left = 'workspace prev'
    ctrl-right = 'workspace next'
    alt-1 = 'workspace 1'          # ... alt-9
    alt-shift-1 = 'move-window-to-workspace 1'
    alt-tab = 'workspace-back-and-forth'
    alt-h = 'focus left'           # j k l
    alt-shift-h = 'move left'      # j k l
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
    alt-shift-h = ['join-with left', 'mode main']   # j k l
    """
