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

/// What the coordinator knows about a window it has classified. `space` is nil off the numbered
/// workspaces (a native full-screen Space), where nothing is tiled.
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
            if !enabled { applier.cancel() }
            if enabled, !oldValue { reconcile() }
        }
    }

    private let displays: DisplayModel
    private(set) var config: Config
    let applier = FrameApplier()
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
        if config.borders.enabled {
            borders = borders ?? BorderManager(config: config.borders, model: model)
            borders?.update(config: config.borders)
        } else {
            borders = nil
        }
        for key in workspaces.keys {
            workspaces[key]!.accordionPadding = CGFloat(config.accordion.padding)
            workspaces[key]!.autoOrientAccordions = config.accordion.orientation == .auto
        }
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
        flush()
    }

    /// Re-reads every window and display, moves windows to the trees of the Spaces they are on now
    /// (so a window dragged to another Space stays there), and re-applies every tree on screen. The model
    /// publishes every window it re-reads, so `handle` tracks and forgets them.
    func reconcile() {
        model.reconcile()
        fitToDisplays()
        syncFocus()
        dirty.formUnion(workspaces.keys)
        flush()
    }

    /// Bounds and gaps of every tree from its display, which can have moved, resized or become main.
    private func fitToDisplays() {
        for display in displays.displays {
            let gaps = gaps(on: display)
            for key in workspaces.keys where key.display == display.uuid {
                workspaces[key]!.bounds = display.visibleArea
                workspaces[key]!.gaps = gaps
            }
        }
    }

    private func gaps(on display: Display) -> DinkyLayout.Gaps {
        DinkyLayout.Gaps(config.gaps(for: displays.monitor(display)))
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

    /// The tree of a numbered workspace, created on first use. Nil for Spaces dinky does not tile.
    private func key(of window: Window) -> SpaceKey? {
        guard let display = displays.display(containingSpace: window.spaceID),
              display.workspaces.contains(window.spaceID) else { return nil }
        let key = SpaceKey(display: display.uuid, space: window.spaceID)
        if workspaces[key] == nil {
            workspaces[key] = Workspace(bounds: display.visibleArea, gaps: gaps(on: display),
                                        accordionPadding: CGFloat(config.accordion.padding),
                                        autoOrientAccordions: config.accordion.orientation == .auto,
                                        mode: config.defaultLayout == .accordion ? .accordion : .tiles)
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

    /// Writes the tree's frames around the minimum sizes windows have shown. Overlapping layouts (accordion,
    /// fullscreen) also bring the focused window to the front when it is on the focused Space: AX raise alone
    /// does not lift it above another app. Minimum sizes found in a pass are laid out around all at once, when that
    /// moves anything.
    private func apply(_ key: SpaceKey) {
        guard var workspace = workspaces[key] else { return }
        workspace.minimumSizes = minimumSizes(in: workspace)
        workspaces[key] = workspace
        let layout = workspace.layout()
        let pids = Dictionary(uniqueKeysWithValues: layout.order.compactMap { id in model.windows[id].map { (id, $0.pid) } })
        let overlaps = !layout.raises(current: []).isEmpty
        let front = overlaps ? workspace.focused.flatMap { model.windows[$0] } : nil
        let focusedHere = placements[focusedWindow]?.space == key
        applier.apply(layout, pids: pids) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.enabled else { return }
                if let front, focusedHere { self.focus(front.id) }
                self.edit(key) { $0.minimumSizes = self.minimumSizes(in: $0) }
                self.flush()
            }
        }
    }

    private func minimumSizes(in workspace: Workspace) -> [WindowID: CGSize] {
        var sizes: [WindowID: CGSize] = [:]
        for id in workspace.windows { sizes[id] = applier.minimumSize(of: id, app: model.windows[id]?.bundleID) }
        return sizes
    }
}
