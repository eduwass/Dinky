import AppKit
import DinkyConfig
import DinkyPrivate

// Workspace numbers: which native Space each workspace is. Workspaces are numbered across displays and live
// where `[workspace-to-display]` puts them, else on the main display. `arrange()` makes the Spaces match: it
// runs `WorkspacePlan`'s steps (create a Space, move a Space's windows, remove an empty Space) until there are
// none left. It runs at launch, on config reload, and a moment after displays or Spaces come and go. Between
// runs a workspace stays on its Space by ID, wherever macOS moves that Space. Main thread only.
final class WorkspaceNumbers {
    /// Workspace number to Space.
    private(set) var binding: [Int: UInt64] = [:]
    private var observers: [() -> Void] = []
    private var pending: DispatchWorkItem?
    private var arranging = false
    /// Spaces this removed, whose `spaceDestroyed` events are not news.
    private var removed: Set<UInt64> = []

    var count: Int { AppState.shared.config.workspaces }

    func space(of n: Int) -> UInt64? { binding[n] }
    func number(of space: UInt64) -> Int? { binding.first { $0.value == space }?.key }
    /// The workspaces on a display, in number order.
    func workspaces(on display: Display) -> [Int] { binding.filter { display.userSpaces.contains($0.value) }.keys.sorted() }
    /// The display's current workspace, nil on a Space that is none (full-screen, or a display without any).
    func current(on display: Display) -> Int? { number(of: display.currentSpaceID) }
    /// "3", or "" off the numbered workspaces, as hooks and logs print it.
    func label(of space: UInt64) -> String { number(of: space).map { "\($0)" } ?? "" }

    /// Calls `handler` whenever the numbering changes.
    func observe(_ handler: @escaping () -> Void) { observers.append(handler) }

    /// Starts following display and Space changes. Call once, after the first `arrange()`.
    func start() {
        let model = AppState.shared.displays
        var known = Set(model.displays.map(\.uuid))
        var main = model.displays.first(where: \.isMain)?.uuid
        // A display coming or going, or another becoming main, moves workspaces.
        model.observe { [weak self] model in
            let now = Set(model.displays.map(\.uuid))
            let nowMain = model.displays.first(where: \.isMain)?.uuid
            guard now != known || nowMain != main else { return }
            let (connected, disconnected) = (now.subtracting(known), known.subtracting(now))
            (known, main) = (now, nowMain)
            if !connected.isEmpty { print("displays: connected \(connected.sorted())") }
            if !disconnected.isEmpty { print("displays: disconnected \(disconnected.sorted())") }
            fflush(stdout)
            self?.arrangeSoon()
        }
        // A Space removed in Mission Control leaves its workspace without one.
        EventHub.shared.subscribe { [weak self] event in
            guard let self, event.kind == .spaceDestroyed, !arranging, removed.remove(event.spaceID) == nil else { return }
            arrangeSoon()
        }
    }

    /// Arranges once things have been quiet for `delay` seconds: the Spaces of a display that just came or went
    /// take a moment to settle in WindowServer, and docking changes several displays in a row.
    func arrangeSoon(after delay: Double = 1) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.arrange() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Runs the plan's steps until the Spaces match the config. Blocks the main thread while it works; each step
    /// waits for WindowServer to show its result, normally within a poll or two.
    func arrange() {
        guard !arranging else { return }
        // A swipe in flight would land on a Space this may remove.
        guard !SpaceSwitcher.shared.switching else { return arrangeSoon(after: 0.3) }
        arranging = true
        defer { arranging = false }
        let model = AppState.shared.displays
        let plan = WorkspacePlan(AppState.shared.config)
        let start = binding
        // The plan forgets a workspace whose Space is not listed. One that is only between displays, listed by
        // WindowServer while CoreGraphics already calls its display offline, gets a moment to reappear.
        func unlisted() -> Bool {
            model.reconcile()
            return !Set(binding.values).isSubset(of: model.displays.flatMap(\.userSpaces))
        }
        if unlisted() { _ = waitUntil(2) { !unlisted() } }
        for _ in 0..<50 {
            model.reconcile()
            let displays = model.displays.map {
                PlanDisplay(uuid: $0.uuid, monitor: model.monitor($0), spaces: $0.userSpaces, current: $0.currentSpaceID)
            }
            guard !displays.isEmpty else { break }
            let occupied = occupiedSpaces(among: displays.flatMap(\.spaces))
            let before = binding
            let step = plan.step(displays, binding: binding, occupied: occupied)
            binding = step.binding
            guard let action = step.action else { break }
            guard perform(action) else {
                // A workspace whose windows did not all move stays where they are, so the next run moves it again.
                if case .move = action { binding = before }
                print("workspaces: stopped; the next display change or config reload tries again")
                break
            }
        }
        // Observers hear the result once, not every step on the way.
        if binding != start {
            print("workspaces: " + binding.keys.sorted().map { "\($0)=\(binding[$0]!)" }.joined(separator: " "))
            observers.forEach { $0() }
        }
        fflush(stdout)
        AppState.shared.coordinator?.reconcile()
    }

    /// The Spaces among `spaces` with windows dinky would tile or restore there: helper windows some apps keep
    /// on every Space don't count. Without a window model to ask, any window counts.
    private func occupiedSpaces(among spaces: [UInt64]) -> Set<UInt64> {
        guard let model = AppState.shared.coordinator?.model, !model.windows.isEmpty else {
            return Set(spaces.filter { !dinky_space_window_ids($0, true).isEmpty })
        }
        let occupied = model.windows.values.filter { $0.isNormal || $0.isMinimized }.map { dinky_window_space_id($0.id) }
        return Set(occupied).intersection(spaces)
    }

    /// Whether a Space has windows dinky would tile or restore there.
    private func occupied(_ space: UInt64) -> Bool { !occupiedSpaces(among: [space]).isEmpty }

    private func perform(_ action: PlanAction) -> Bool {
        let model = AppState.shared.displays
        switch action {
        case .create(let uuid):
            let name = model.displays.first { $0.uuid == uuid }.map(displayName) ?? uuid
            let space = dinky_create_space(uuid as CFString)
            guard space != 0, waitUntil(2, { model.reconcile(); return model.display(containingSpace: space) != nil }) else {
                print("workspaces: could not create a Space on \(name)")
                return false
            }
            print("workspaces: created Space \(space) on \(name)")
            return true

        case .move(let from, let to):
            // Every window goes, helper windows included; only the ones `occupied` counts must arrive.
            var ids = dinky_space_window_ids(from, true).map(\.uint32Value)
            AppState.shared.coordinator?.moveTree(from: from, to: to)
            if !ids.isEmpty, dinky_move_windows_to_space(&ids, Int32(ids.count), to) {
                _ = waitUntil(1) { !occupied(from) }
            }
            guard !occupied(from) else {
                AppState.shared.coordinator?.moveTree(from: to, to: from)
                print("workspaces: windows stayed on Space \(from) instead of moving to \(to)")
                return false
            }
            print("workspaces: moved the windows of Space \(from) to \(to)")
            return true

        case .remove(let space):
            // Removing the Space a display shows drops it to its first Space; leave for a workspace first.
            if let display = model.displays.first(where: { $0.currentSpaceID == space }) {
                let previous = model.previousSpace(on: display).flatMap { display.userSpaces.contains($0) && number(of: $0) != nil ? $0 : nil }
                if let target = previous ?? workspaces(on: display).first.flatMap(space(of:)), target != space,
                   switchSpace(toSpaceID: target, on: display) {
                    _ = waitUntil(1.5) { dinky_current_space_id(display.uuid as CFString) == target }
                }
            }
            guard dinky_destroy_space(space),
                  waitUntil(2, { model.reconcile(); return model.display(containingSpace: space) == nil }) else {
                print("workspaces: could not remove Space \(space)")
                return false
            }
            removed.insert(space)
            print("workspaces: removed Space \(space)")
            return true
        }
    }

    private func displayName(_ display: Display) -> String {
        display.name.isEmpty ? "display \(display.id)" : display.name
    }
}
