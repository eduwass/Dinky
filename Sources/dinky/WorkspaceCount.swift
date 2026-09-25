import DinkyPrivate
import Foundation

/// Gives every display at least `config.workspaces` user Spaces, creating the missing ones at the end of
/// each display's strip. Never removes one. Each new Space must show up in the display model (within 2 s)
/// before the next is created. If creation fails on a display, that is logged once and the display skipped.
/// Blocks the main thread while it works; a Space normally appears on the first poll.
func ensureWorkspaceCount() {
    let wanted = AppState.shared.config.workspaces
    let model = AppState.shared.displays
    model.reconcile()
    for display in model.displays where display.workspaces.count < wanted {
        var created: [UInt64] = []
        while display.workspaces.count + created.count < wanted {
            let space = dinky_create_space(display.uuid as CFString)
            guard space != 0 else {
                print("workspaces: can't create Spaces on display \(display.id), it keeps \(display.workspaces.count + created.count)")
                break
            }
            let appeared = waitUntil(2) {
                model.reconcile()
                return model.displays.first { $0.uuid == display.uuid }?.workspaces.contains(space) == true
            }
            guard appeared else {
                print("workspaces: created Space \(space) on display \(display.id) but it did not appear, stopping")
                break
            }
            created.append(space)
        }
        print("workspaces: display \(display.id) had \(display.workspaces.count), created \(created.count) \(created)")
    }
    fflush(stdout)
}
