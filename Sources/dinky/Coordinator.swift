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
        didSet { if enabled, !oldValue { reconcile() } }
    }

    private let displays: DisplayModel
    private var config: Config
    private let applier = FrameApplier()
    private var borders: BorderManager?
    private(set) var workspaces: [SpaceKey: Workspace] = [:]
    var placements: [WindowID: Placement] = [:]
    private var dirty: Set<SpaceKey> = []
    /// Classification attempts for windows whose AX element has not appeared yet.
    private var attempts: [WindowID: Int] = [:]
    /// A window dinky just focused, and until when focus reads that disagree are taken as stale.
    private var focusing: (id: WindowID, until: Date)?

    init(displays: DisplayModel, config: Config) {
        self.displays = displays
        self.config = config
    }

    func start() {
        model.onChange = { [weak self] event in self?.handle(event) }
        displays.onChange = { [weak self] _ in self?.reconcile() }
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
            workspaces[key]!.gaps = DinkyLayout.Gaps(config.gaps)
            workspaces[key]!.accordionPadding = CGFloat(config.layout.accordionPadding)
        }
        dirty.formUnion(workspaces.keys)
        flush()
    }

    // MARK: Events

    private func handle(_ event: WindowEvent) {
        borders?.handle(event)
        if let window = event.window {
            event.change == .removed ? forget(window.id) : track(window)
        }
        if [.frontApp, .windowReorder, .windowCreate].contains(event.kind) { syncFocus() }
        flush()
    }

    /// Re-reads every window and display, moves windows to the trees of the Spaces they are on now
    /// (so a window dragged to another Space stays there), and re-applies every tree on screen.
    func reconcile() {
        model.reconcile()
        for window in model.windows.values.sorted(by: { $0.id < $1.id }) { track(window) }
        for id in placements.keys where model.windows[id] == nil { forget(id) }
        for display in displays.displays {
            for key in workspaces.keys where key.display == display.uuid { workspaces[key]!.bounds = area(of: display) }
        }
        syncFocus()
        dirty.formUnion(workspaces.keys)
        flush()
    }

    /// Classifies a window the first time it is on screen, then keeps it in the tree of its current Space
    /// while it is not minimized.
    func track(_ window: Window) {
        if placements[window.id] == nil {
            // AX only lists windows on a Space that is on screen; the rest are classified when theirs is.
            guard window.isNormal, isVisible(window.spaceID), let floating = classify(window) else { return }
            placements[window.id] = Placement(floating: floating, space: nil)
        }
        guard !placements[window.id]!.floating else { return }
        let old = placements[window.id]!.space
        let new = window.isMinimized ? nil : key(of: window)
        guard old != new else { return }
        if let old { edit(old) { $0.remove(window.id) } }
        if let new { edit(new) { $0.insert(window.id) } }
        placements[window.id]!.space = new
    }

    private func forget(_ id: WindowID) {
        attempts[id] = nil
        guard let placement = placements.removeValue(forKey: id), let space = placement.space else { return }
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
            workspaces[key] = Workspace(bounds: area(of: display), gaps: DinkyLayout.Gaps(config.gaps),
                                        accordionPadding: CGFloat(config.layout.accordionPadding),
                                        mode: config.layout.default == .accordion ? .accordion : .tiles)
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

    private func isVisible(_ space: UInt64) -> Bool {
        displays.displays.contains { $0.currentSpaceID == space }
    }

    /// Writes the tree's frames around the minimum sizes windows have shown. Overlapping layouts (accordion,
    /// fullscreen) also bring the focused window to the front when it is on the focused Space: AX raise alone
    /// does not lift it above another app. A window that refuses its frame gets the tree laid out again around it.
    private func apply(_ key: SpaceKey) {
        guard var workspace = workspaces[key] else { return }
        workspace.minimumSizes = minimumSizes(in: workspace)
        workspaces[key] = workspace
        let layout = workspace.layout()
        let pids = Dictionary(uniqueKeysWithValues: layout.order.compactMap { id in model.windows[id].map { (id, $0.pid) } })
        let overlaps = !layout.raises(current: []).isEmpty
        let front = overlaps ? workspace.focused.flatMap { model.windows[$0] } : nil
        let focusedHere = placements[focusedWindow]?.space == key
        applier.apply(layout, pids: pids) { _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let front, focusedHere { focus(front.id) }
                if minimumSizes(in: workspace) != workspace.minimumSizes {
                    dirty.insert(key)
                    flush()
                }
            }
        }
    }

    private func minimumSizes(in workspace: Workspace) -> [WindowID: CGSize] {
        applier.minimumSizes.filter { workspace.contains($0.key) }
    }

    // MARK: Classification

    /// False for a window to tile, true for one to float, nil while its AX element is not there yet
    /// (a retry is scheduled; after a few, the window floats since dinky could not move it anyway).
    private func classify(_ window: Window) -> Bool? {
        guard let element = axWindow(pid: window.pid, wid: window.id, timeout: FrameApplier.timeout) else {
            let tries = attempts[window.id, default: 0] + 1
            attempts[window.id] = tries
            guard tries < 5 else { return true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self, let window = model.windows[window.id] else { return }
                track(window)
                flush()
            }
            return nil
        }
        attempts[window.id] = nil
        let kind = windowKind(subrole: axString(element, kAXSubroleAttribute))
        var resizable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &resizable)
        let title = axString(element, kAXTitleAttribute) ?? ""
        let rules = config.commands(for: window, kind: kind, title: title)
        // Other rule commands, such as move-window-to-workspace, run for this window once it is placed.
        for command in rules where command != .layout([.floating]) {
            DispatchQueue.main.async {
                let reply = Dispatcher.run(command, window: window.id)
                if !reply.ok { fputs("on-window-detected: \(reply.text)\n", stderr) }
            }
        }
        return kind != .normal || !resizable.boolValue || rules.contains(.layout([.floating]))
    }
}

/// The display's frame minus menu bar and Dock, in CG coordinates (top-left origin at the primary display).
private func area(of display: Display) -> CGRect {
    let number = NSDeviceDescriptionKey("NSScreenNumber")
    guard let primary = NSScreen.screens.first,
          let screen = NSScreen.screens.first(where: { ($0.deviceDescription[number] as? NSNumber)?.uint32Value == display.id })
    else { return display.frame }
    let visible = screen.visibleFrame
    return CGRect(x: visible.minX, y: primary.frame.maxY - visible.maxY, width: visible.width, height: visible.height)
}

extension DinkyLayout.Gaps {
    init(_ gaps: DinkyConfig.Gaps) {
        self.init(inner: CGFloat(gaps.inner), top: CGFloat(gaps.outer.top), bottom: CGFloat(gaps.outer.bottom),
                  left: CGFloat(gaps.outer.left), right: CGFloat(gaps.outer.right))
    }
}
