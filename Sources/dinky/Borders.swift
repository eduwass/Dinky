import AppKit
import DinkyConfig
import DinkyPrivate

// din-nt98: focus borders. One BorderWindow per document window on a visible Space; the
// focused window's border gets the active colour, the rest the inactive one (JankyBorders'
// behaviour). `onlyFocused` draws the focused window's border alone.
//
// The owner feeds it the WindowModel's events through handle(_:).
final class BorderManager {
    var onlyFocused = false { didSet { syncAll() } }

    private var config: Borders
    private let model: WindowModel
    private var borders: [UInt32: BorderWindow] = [:]
    private var focusedID: UInt32 = 0
    private var visibleSpaces: Set<UInt64> = []

    init(config: Borders, model: WindowModel) {
        self.config = config
        self.model = model
        refreshSpaces()
        focusedID = dinky_border_focused_window()
        syncAll()
    }

    func update(config: Borders) {
        guard config != self.config else { return }
        self.config = config
        syncAll()
    }

    func handle(_ event: WindowEvent) {
        switch event.kind {
        case .spaceChange, .spaceCreated, .spaceDestroyed:
            refreshSpaces()
            refocus()
            syncAll()
            return
        case .frontApp:
            refocus()
            // The new app's front window can settle a few ms after the app (JankyBorders waits 20 ms).
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(20)) { [weak self] in self?.refocus() }
        case .windowReorder, .windowCreate, .windowDestroy, .windowUpdate, .windowTitle:
            refocus()
        default:
            break
        }

        guard let window = event.window else { return }
        if event.change == .removed {
            borders[window.id] = nil
        } else {
            sync(window)
        }
    }

    private func syncAll() {
        for id in borders.keys where model.windows[id] == nil { borders[id] = nil }
        for window in model.windows.values { sync(window) }
    }

    private func sync(_ window: Window) {
        guard config.enabled, window.isDocument, config.decorates(bundleID: window.bundleID) else {
            borders[window.id] = nil
            return
        }
        let focused = window.id == focusedID
        let shown = window.isOrderedIn && !window.isMinimized && visibleSpaces.contains(window.spaceID)
            && (focused || !onlyFocused)
        guard shown else {
            borders[window.id]?.hide()
            return
        }
        let border = borders[window.id] ?? BorderWindow(target: window.id)
        borders[window.id] = border
        border.update(window, color: focused ? config.activeColor : config.inactiveColor, config: config)
    }

    private func refocus() {
        let id = dinky_border_focused_window()
        guard id != focusedID else { return }
        let old = focusedID
        focusedID = id
        for id in [old, id] {
            if let window = model.windows[id] { sync(window) }
        }
    }

    // The current Space of every display, full-screen Spaces left out.
    private func refreshSpaces() {
        visibleSpaces = Set(dinky_displays().compactMap { display in
            let current = display.spaces.first { $0.spaceID == display.currentSpaceID }
            return current?.isFullscreen == true ? nil : display.currentSpaceID
        })
    }
}
