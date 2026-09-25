import XCTest
@testable import DinkyConfig

final class ConfigWatcherTests: XCTestCase {
    func testFiresOnChange() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "dinky-\(UUID().uuidString).toml")
        try "workspaces = 3\n".write(to: url, atomically: false, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let changed = expectation(description: "reloaded")
        let broken = expectation(description: "error reported")
        let watcher = ConfigWatcher(url: url) { result in
            switch result {
            case .success(let config) where config.workspaces == 4: changed.fulfill()
            case .failure(let error) where error.path == "gap": broken.fulfill()
            default: break
            }
        }
        defer { watcher.stop() }

        try "workspaces = 4\n".write(to: url, atomically: false, encoding: .utf8)
        wait(for: [changed], timeout: 1)

        // Atomic save: a new file renamed over the old one.
        try "gap = 4\n".write(to: url, atomically: true, encoding: .utf8)
        wait(for: [broken], timeout: 1)
    }
}
