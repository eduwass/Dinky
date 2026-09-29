import XCTest
@testable import DinkyConfig

/// Runs plans against a simulated WindowServer: displays with Spaces, and windows per Space.
final class WorkspacePlanTests: XCTestCase {
    private struct World {
        var displays: [PlanDisplay]
        var windows: [UInt64: Int] = [:]  // count per Space
        var binding: [Int: UInt64] = [:]
        var nextSpace: UInt64 = 1000
        var actions: [PlanAction] = []

        /// Steps until the plan is done, applying each action as WindowServer would.
        mutating func settle(_ plan: WorkspacePlan, limit: Int = 50) {
            for _ in 0..<limit {
                let step = plan.step(displays, binding: binding, occupied: { windows[$0, default: 0] > 0 })
                binding = step.binding
                guard let action = step.action else { return }
                actions.append(action)
                switch action {
                case .create(let uuid):
                    let i = displays.firstIndex { $0.uuid == uuid }!
                    displays[i].spaces.append(nextSpace)
                    nextSpace += 1
                case .move(let from, let to):
                    windows[to, default: 0] += windows[from, default: 0]
                    windows[from] = 0
                case .remove(let space):
                    let i = displays.firstIndex { $0.spaces.contains(space) }!
                    displays[i].spaces.removeAll { $0 == space }
                    if displays[i].current == space { displays[i].current = displays[i].spaces[0] }
                }
            }
            XCTFail("no fixed point after \(limit) steps: \(actions)")
        }

        func spaces(_ uuid: String) -> [UInt64] { displays.first { $0.uuid == uuid }!.spaces }
        func numbers(on uuid: String) -> [Int] { spaces(uuid).compactMap { s in binding.first { $0.value == s }?.key } }
    }

    private static func display(_ uuid: String, _ name: String, main: Bool, count: Int, _ spaces: [UInt64]) -> PlanDisplay {
        PlanDisplay(uuid: uuid, monitor: Monitor(name: name, isMain: main, count: count), spaces: spaces, current: spaces[0])
    }

    private let fivePlusSide = WorkspacePlan(count: 5, assignments: [5: [.secondary]])

    func testStartupBindsWorkspacesToSpacesInOrder() {
        var world = World(displays: [Self.display("L", "Built-in", main: true, count: 1, [1, 2, 3])])
        world.windows = [1: 2, 3: 1]
        world.settle(fivePlusSide)
        XCTAssertEqual(world.actions, [.create(display: "L"), .create(display: "L")])
        XCTAssertEqual(world.numbers(on: "L"), [1, 2, 3, 4, 5])
        XCTAssertEqual(world.binding[1], 1)
        XCTAssertEqual(world.binding[3], 3)
    }

    func testDockingMovesTheAssignedWorkspaceAndRemovesItsOldSpace() {
        // Undocked: five Spaces on the laptop, workspace 5 with windows. Docked in clamshell: the laptop's Spaces
        // move to the new main display, and the side display arrives with a Space of its own.
        var world = World(displays: [Self.display("L", "Built-in", main: true, count: 1, [1, 2, 3, 4, 5])])
        world.windows = [1: 1, 5: 2]
        world.settle(fivePlusSide)
        XCTAssertEqual(world.actions, [])

        world.displays = [Self.display("P", "PG27UCDM", main: true, count: 2, [1, 2, 3, 4, 5]),
                          Self.display("S", "LS24D60xU", main: false, count: 2, [9])]
        world.settle(fivePlusSide)
        XCTAssertEqual(world.actions, [.move(from: 5, to: 9), .remove(space: 5)])
        XCTAssertEqual(world.numbers(on: "P"), [1, 2, 3, 4])
        XCTAssertEqual(world.numbers(on: "S"), [5])
        XCTAssertEqual(world.windows[9], 2)
    }

    func testUndockingKeepsTheMergedSpaceAndPutsItBackInOrder() {
        var world = World(displays: [Self.display("P", "PG27UCDM", main: true, count: 2, [1, 2, 3, 4]),
                                     Self.display("S", "LS24D60xU", main: false, count: 2, [9])])
        world.windows = [9: 2]
        world.settle(fivePlusSide)
        XCTAssertEqual(world.numbers(on: "S"), [5])

        // macOS merges the side display's Space onto the laptop, not necessarily at the end.
        world.actions = []
        world.displays = [Self.display("L", "Built-in", main: true, count: 1, [1, 9, 2, 3, 4])]
        world.settle(fivePlusSide)
        XCTAssertEqual(world.actions, [.create(display: "L"), .move(from: 9, to: 1000), .remove(space: 9)])
        XCTAssertEqual(world.numbers(on: "L"), [1, 2, 3, 4, 5])
        XCTAssertEqual(world.windows[1000], 2)
    }

    func testWindowsNeverMoveOntoALeftoverSpaceWithWindows() {
        var world = World(displays: [Self.display("P", "PG27UCDM", main: true, count: 2, [1, 2, 3, 4]),
                                     Self.display("S", "LS24D60xU", main: false, count: 2, [9])])
        world.windows = [9: 2]
        world.settle(fivePlusSide)
        // A leftover Space with windows (X = 50) sits on the laptop when workspace 5's Space merges mid-list.
        world.actions = []
        world.displays = [Self.display("L", "Built-in", main: true, count: 1, [1, 9, 2, 3, 4, 50])]
        world.windows[50] = 1
        world.settle(fivePlusSide)
        XCTAssertEqual(world.actions, [.create(display: "L"), .move(from: 9, to: 1000), .remove(space: 9)])
        XCTAssertEqual(world.windows[50], 1, "the leftover keeps its own window")
        XCTAssertEqual(world.windows[1000], 2)
        XCTAssertEqual(world.numbers(on: "L"), [1, 2, 3, 4, 5])
    }

    func testUndockingWithTheMergedSpaceAtTheEndMovesNothing() {
        var world = World(displays: [Self.display("P", "PG27UCDM", main: true, count: 2, [1, 2, 3, 4]),
                                     Self.display("S", "LS24D60xU", main: false, count: 2, [9])])
        world.settle(fivePlusSide)
        world.actions = []
        world.displays = [Self.display("L", "Built-in", main: true, count: 1, [1, 2, 3, 4, 9])]
        world.settle(fivePlusSide)
        XCTAssertEqual(world.actions, [])
        XCTAssertEqual(world.binding[5], 9)
    }

    func testFallbackPatternsAndMain() {
        let plan = WorkspacePlan(count: 3, assignments: [2: [.name("dell"), .name("lg")], 3: [.name("dell")]])
        let displays = [Self.display("M", "Built-in", main: true, count: 2, [1]),
                        Self.display("G", "LG UltraFine", main: false, count: 2, [2])]
        XCTAssertEqual(plan.homes(displays), [1: "M", 2: "G", 3: "M"])
    }

    func testDisplayWithoutWorkspacesKeepsOneSpace() {
        var world = World(displays: [Self.display("M", "Built-in", main: true, count: 2, [1, 2]),
                                     Self.display("T", "Projector", main: false, count: 2, [7, 8, 9])])
        world.displays[1].current = 8
        world.windows = [9: 1]
        world.settle(WorkspacePlan(count: 2, assignments: [:]))
        XCTAssertEqual(world.actions, [.remove(space: 7)], "the current Space stays, the one with windows is left alone")
        XCTAssertEqual(world.spaces("T"), [8, 9])
        XCTAssertEqual(world.numbers(on: "T"), [])
    }

    func testFewerWorkspacesRemovesEmptySpacesAndLeavesOnesWithWindows() {
        var world = World(displays: [Self.display("L", "Built-in", main: true, count: 1, [1, 2, 3, 4, 5])])
        world.windows = [4: 1]
        world.settle(WorkspacePlan(count: 5, assignments: [:]))
        world.settle(WorkspacePlan(count: 3, assignments: [:]))
        XCTAssertEqual(world.actions, [.remove(space: 5)])
        XCTAssertEqual(world.spaces("L"), [1, 2, 3, 4])
        XCTAssertEqual(world.numbers(on: "L"), [1, 2, 3])
    }

    func testStaleAndDuplicateBindingsAreDropped() {
        let plan = WorkspacePlan(count: 2, assignments: [:])
        let displays = [Self.display("L", "Built-in", main: true, count: 1, [1, 2])]
        let step = plan.step(displays, binding: [1: 2, 2: 2, 7: 1, 3: 99], occupied: { _ in false })
        XCTAssertEqual(step.binding, [1: 2], "workspace 2 must get a Space after workspace 1's; there is none yet")
        XCTAssertEqual(step.action, .create(display: "L"))
    }

    func testRedockingIsStable() {
        var world = World(displays: [Self.display("L", "Built-in", main: true, count: 1, [1, 2, 3, 4, 5])])
        world.windows = [5: 1]
        world.settle(fivePlusSide)
        for _ in 0..<3 {
            world.displays = [Self.display("P", "PG27UCDM", main: true, count: 2, world.spaces(world.displays[0].uuid)),
                              Self.display("S", "LS24D60xU", main: false, count: 2, [world.nextSpace])]
            world.nextSpace += 1
            world.settle(fivePlusSide)
            XCTAssertEqual(world.numbers(on: "P"), [1, 2, 3, 4])
            XCTAssertEqual(world.numbers(on: "S"), [5])
            let side = world.spaces("S")
            world.displays = [Self.display("L", "Built-in", main: true, count: 1, world.spaces("P") + side)]
            world.settle(fivePlusSide)
            XCTAssertEqual(world.numbers(on: "L"), [1, 2, 3, 4, 5])
            XCTAssertEqual(world.windows[world.binding[5]!], 1, "workspace 5's window travels with it")
        }
    }
}
