import AppKit
import DinkyCommands
import DinkyConfig
import DinkyLayout
import DinkyPrivate

/// One tree per Space: the display it is on and the Space itself.
struct SpaceKey: Hashable {
    let display: String
    let space: UInt64
}

/// What the coordinator knows about a window it has classified. `space` is nil off the user Spaces
/// (on a native full-screen Space), where nothing is tiled.
struct Placement {
    let floating: Bool
    var space: SpaceKey?
}

// The serialized owner of layout state: one Workspace per Space, fed by the window and display models,
// applied through the frame applier. Every change marks the trees it touched dirty; `flush` applies the
// dirty trees that are on screen. Main thread only.
final class Coordinator {
    let model = WindowModel()
    var enabled = true {
        didSet {
            if !enabled { applier.cancel(); animator.cancel() }
            if enabled, !oldValue { reconcile() }
        }
    }

    private let displays: DisplayModel
    private(set) var config: Config
    let applier = FrameApplier()
    private lazy var animator = Animator(applier: applier)
    private var borders: BorderManager?
    func isBorderWindow(_ id: WindowID) -> Bool { borders?.isBorder(id) ?? false }
    private(set) var workspaces: [SpaceKey: Workspace] = [:]
    var placements: [WindowID: Placement] = [:]
    var dirty: Set<SpaceKey> = []
    /// Classification attempts for windows whose AX element has not appeared yet.
    var attempts: [WindowID: Int] = [:]
    /// Newly shown windows at the exact frame of a tile of their app, held out of the trees for a moment in case
    /// they are a tab switch: by newcomer, the tile's window. See Tabs.swift.
    var heldTabs: [WindowID: WindowID] = [:]
    /// Newcomers held once and not confirmed as tabs. They are tiled like any window from then on.
    var notTabs: Set<WindowID> = []
    /// The tiled window being dragged with the mouse, until the button is released. See Drag.swift.
    var dragging: WindowID?
    lazy var placeholders = DragPlaceholders()
    /// Called when the focused window changes.
    var onFocusChange: (() -> Void)?
    private var lastFocused: WindowID = 0
    /// A window dinky just focused, and until when focus reads that disagree are taken as stale.
    private var focusing: (id: WindowID, until: Date)?

    init(displays: DisplayModel, config: Config) {
        self.displays = displays
        self.config = config
    }

    func start() {
        model.onChange = { [weak self] event in self?.handle(event) }
        animator.onArrive = { [weak self] ids in self?.borders?.arrived(ids) }
        displays.observe { [weak self] _ in self?.reconcile() }
        // A hidden app's windows can read as shown when their hide event arrives; re-read them once it is hidden.
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.reconcile() }
        }
        guard model.start() else {
            fputs("coordinator: no WindowServer events\n", stderr)
            return
        }
        update(config: config)
        reconcile()
    }

    func update(config: Config) {
        self.config = config
        animator.setDuration(ms: config.animations.durationMs)
        if config.borders.enabled {
            borders = borders ?? BorderManager(config: config.borders, model: model,
                                               isAnimating: { [unowned self] id in animator.isAnimating(id) })
            borders?.update(config: config.borders)
        } else {
            borders = nil
        }
        configureWorkspaces()
        // A workspace switched to/from floating must release/acquire its existing windows too.
        for window in model.windows.values { track(window) }
        fitToDisplays()
        dirty.formUnion(workspaces.keys)
        flush()
    }

    // MARK: Events

    private func handle(_ event: WindowEvent) {
        // Detected here, not in the border manager, so hover focus stands down even with borders off.
        if MissionControl.shared.update(from: model) { borders?.missionControlChanged() }
        borders?.handle(event)
        if let window = event.window {
            event.change == .removed ? forget(window.id) : track(window)
            if [.windowMove, .windowResize].contains(event.kind) { noteFrameChange(of: window.id) }
        }
        if [.frontApp, .windowReorder, .windowCreate].contains(event.kind) { syncFocus() }
        if event.kind == .frontApp {
            // The app's front window settles a few ms after the app, as the border manager also knows: Cmd-`
            // between one app's windows reports the app with its previous window still in front.
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(20)) { [weak self] in
                self?.syncFocus()
                self?.flush()
            }
        }
        flush()
    }

    /// Re-reads every window and display, moves windows to the trees of the Spaces they are on now
    /// (so a window dragged to another Space stays there), and re-applies every tree on screen. The model
    /// publishes every window it re-reads, so `handle` tracks and forgets them.
    func reconcile() {
        configureWorkspaces()
        model.reconcile()
        fitToDisplays()
        syncFocus()
        dirty.formUnion(workspaces.keys)
        flush()
    }

    /// Bounds and gaps of every tree from its display, which can have moved, resized or become main. A tree whose
    /// Space macOS moved to another display, as it does with a disconnected display's Spaces, goes along.
    private func fitToDisplays() {
        for key in workspaces.keys {
            guard let display = displays.display(containingSpace: key.space), display.uuid != key.display else { continue }
            rekey(key, to: SpaceKey(display: display.uuid, space: key.space))
        }
        for display in displays.displays {
            let gaps = gaps(on: display)
            for key in workspaces.keys where key.display == display.uuid {
                workspaces[key]!.bounds = display.visibleArea
                workspaces[key]!.gaps = gaps
            }
        }
    }

    /// Carries a Space's tree to another Space, before its windows are moved there, so they arrive in the layout
    /// they had. Kept when the other Space already has a tree with windows.
    func moveTree(from: UInt64, to: UInt64) {
        guard let old = workspaces.keys.first(where: { $0.space == from }),
              let display = displays.display(containingSpace: to) else { return }
        rekey(old, to: SpaceKey(display: display.uuid, space: to))
    }

    private func rekey(_ old: SpaceKey, to new: SpaceKey) {
        guard old != new, workspaces[new]?.windows.isEmpty != false, var tree = workspaces.removeValue(forKey: old) else { return }
        if let display = displays.displays.first(where: { $0.uuid == new.display }) {
            tree.bounds = display.visibleArea
            tree.gaps = gaps(on: display)
        }
        workspaces[new] = tree
        for (id, placement) in placements where placement.space == old { placements[id]!.space = new }
    }

    /// Resolve layout settings by a Space's current numbered position, which can change when Spaces are reordered.
    private func configureWorkspaces() {
        for key in workspaces.keys {
            workspaces[key]!.accordionPadding = CGFloat(config.accordion.padding)
            workspaces[key]!.autoOrientAccordions = config.accordion.orientation == .auto
            let mode: LayoutMode = layout(for: key.space) == .accordion ? .accordion : .tiles
            workspaces[key]!.setAlgorithm(algorithm(for: key.space), mode: mode)
        }
    }

    private func gaps(on display: Display) -> DinkyLayout.Gaps {
        DinkyLayout.Gaps(config.gaps(for: displays.monitor(display)))
    }

    private func layout(for space: UInt64) -> LayoutKind {
        AppState.shared.numbers.number(of: space).map { config.layout(forWorkspace: $0) } ?? config.defaultLayout
    }

    private func algorithm(for space: UInt64) -> TilingAlgorithm {
        guard layout(for: space) == .fixed else { return .dwindle }
        let number = AppState.shared.numbers.number(of: space)
        let expand: FixedExpansion = switch number.map({ config.expansion(forWorkspace: $0) }) ?? .columns {
        case .rows: .rows
        case .columns: .columns
        case .accordion: .accordion
        }
        return .fixed(rows: number.map { config.fixedRows(forWorkspace: $0) } ?? 1,
                      columns: number.map { config.fixedColumns(forWorkspace: $0) } ?? 1, expand: expand)
    }

    /// Classifies a window the first time it is on screen, then keeps it in the tree of its current Space
    /// while it is shown: minimized windows, windows of hidden apps and inactive tabs read as minimized.
    func track(_ window: Window) {
        if placements[window.id] == nil {
            // AX only lists windows on a Space that is on screen; the rest are classified when theirs is.
            guard window.isNormal, isVisible(window.spaceID), let floating = classify(window) else { return }
            placements[window.id] = Placement(floating: floating, space: nil)
        }
        guard !placements[window.id]!.floating else { return }
        let old = placements[window.id]!.space
        if let old, window.isMinimized || !window.isOrderedIn, takeOverTile(of: window.id, in: old) {
            placements[window.id]!.space = nil
            return
        }
        let new = window.isMinimized ? nil : key(of: window)
        guard old != new, heldTabs[window.id] == nil else { return }
        if let old { edit(old) { $0.remove(window.id) } }
        // A window coming from another Space's tree is moving, not switching tabs: tabs share a Space.
        if let new, old == nil, holdAsTab(window, in: new) { return }
        if let new { edit(new) { $0.insert(window.id) } }
        placements[window.id]!.space = new
    }

    private func forget(_ id: WindowID) {
        attempts[id] = nil
        heldTabs[id] = nil
        notTabs.remove(id)
        guard let placement = placements.removeValue(forKey: id), let space = placement.space,
              !takeOverTile(of: id, in: space) else { return }
        edit(space) { $0.remove(id) }
    }

    /// The front app's frontmost document window on a current Space.
    var focusedWindow: WindowID { dinky_border_focused_window() }

    /// Focuses a window, raising it and activating its app. For a moment after, focus events that still
    /// report the previous window are ignored, so they do not pull the trees back to it.
    func focus(_ id: WindowID) {
        guard let window = model.windows[id] else { return }
        focusing = (id, Date() + 0.5)
        focusWindow(pid: window.pid, id: id)
    }

    /// Follows focus into the trees, so new windows land beside the focused one and accordions show it.
    private func syncFocus() {
        let id = focusedWindow
        if id != lastFocused {
            lastFocused = id
            displays.focusOverride = nil
            onFocusChange?()
        }
        if let focusing, focusing.id != id, Date() < focusing.until { return }
        focusing = nil
        guard let key = placements[id]?.space, workspaces[key]?.focused != id else { return }
        edit(key) { $0.focus(id) }
    }

    /// The tree of a user Space, numbered workspace or not, created on first use. Nil for full-screen Spaces.
    private func key(of window: Window) -> SpaceKey? {
        guard let display = displays.display(containingSpace: window.spaceID),
              display.userSpaces.contains(window.spaceID) else { return nil }
        let number = AppState.shared.numbers.number(of: window.spaceID)
        guard number.map({ config.tiling(forWorkspace: $0) }) ?? config.defaultTiling else { return nil }
        let layout = layout(for: window.spaceID)
        let key = SpaceKey(display: display.uuid, space: window.spaceID)
        if workspaces[key] == nil {
            workspaces[key] = Workspace(bounds: display.visibleArea, gaps: gaps(on: display),
                                        accordionPadding: CGFloat(config.accordion.padding),
                                        autoOrientAccordions: config.accordion.orientation == .auto,
                                        mode: layout == .accordion ? .accordion : .tiles,
                                        algorithm: algorithm(for: window.spaceID))
        }
        return key
    }

    /// Runs `change` on a tree and marks it dirty if its layout changed. Returns what `change` returned.
    @discardableResult
    func edit<T>(_ key: SpaceKey, _ change: (inout Workspace) -> T) -> T? {
        guard var workspace = workspaces[key] else { return nil }
        let before = workspace.layout()
        let result = change(&workspace)
        workspaces[key] = workspace
        if workspace.layout() != before { dirty.insert(key) }
        return result
    }

    // MARK: Applying

    func flush() {
        let keys = dirty
        dirty = []
        guard enabled else { return }
        for key in keys where isVisible(key.space) { apply(key) }
    }

    /// Whether the Space is a display's current one.
    func isVisible(_ space: UInt64) -> Bool {
        displays.displays.contains { $0.currentSpaceID == space }
    }

    /// Writes the tree's frames around the minimum sizes windows have shown, then lets the applier raise
    /// overlapping windows (accordion, fullscreen) into the tree's stacking, with its focused window on top.
    /// Nothing is activated: the tree follows macOS's focus (`syncFocus`) and commands that choose a window
    /// focus it themselves, so a pass, which may have started before the latest focus change, must not.
    /// Minimum sizes found in a pass are laid out around all at once, when that moves anything.
    private func apply(_ key: SpaceKey) {
        guard var workspace = workspaces[key] else { return }
        workspace.minimumSizes = minimumSizes(in: workspace)
        workspaces[key] = workspace
        let layout = workspace.layout()
        let pids = Dictionary(uniqueKeysWithValues: layout.order.compactMap { id in model.windows[id].map { (id, $0.pid) } })
        let write = { [weak self] in
            guard let self else { return }
            applier.apply(layout, pids: pids, front: workspace.focused) { [weak self] results in
                DispatchQueue.main.async {
                    guard let self, self.enabled else { return }
                    self.animator.noteLanded(results)
                    self.edit(key) { $0.minimumSizes = self.minimumSizes(in: $0) }
                    self.flush()
                    // A refusal counts on the second pass; run it soon rather than on the next event.
                    if !self.applier.unconfirmedMinimums.isDisjoint(with: layout.order) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                            self?.dirty.insert(key)
                            self?.flush()
                        }
                    }
                }
            }
        }
        guard animates else { return write() }
        // Stacking first, so the window coming to the front of an accordion slides in on top.
        applier.raiseIntoOrder(layout, pids: pids, front: workspace.focused)
        let starts = Dictionary(uniqueKeysWithValues: layout.order.compactMap { id in
            id == dragging ? nil : model.windows[id].map { (id, $0.frame) }
        })
        animator.animate(key, from: starts, to: layout.frames, pids: pids, then: write)
    }

    /// Whether passes glide windows to their tiles.
    private var animates: Bool {
        config.animations.enabled && config.animations.durationMs > 0
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Whether dinky is gliding the window to its tile right now.
    func isAnimating(_ id: WindowID) -> Bool { animator.isAnimating(id) }

    /// The windows dinky is gliding to their tiles right now.
    var animatingWindows: [WindowID] { animator.animating }

    private func minimumSizes(in workspace: Workspace) -> [WindowID: CGSize] {
        var sizes: [WindowID: CGSize] = [:]
        for id in workspace.windows { sizes[id] = applier.minimumSize(of: id, app: model.windows[id]?.bundleID) }
        return sizes
    }
}
