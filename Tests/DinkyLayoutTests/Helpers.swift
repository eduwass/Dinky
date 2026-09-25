import CoreGraphics
import XCTest
@testable import DinkyLayout

/// Tree shape as text: "h[1 v[2 3]]", accordions prefixed with "a", e.g. "ah[1 2]".
func shape(_ c: Container) -> String {
    let kind = (c.mode == .accordion ? "a" : "") + (c.orientation == .horizontal ? "h" : "v")
    let inner = c.children.map { node -> String in
        switch node {
        case .window(let id): "\(id)"
        case .container(let child): shape(child)
        }
    }
    return kind + "[" + inner.joined(separator: " ") + "]"
}

/// A workspace with windows 1...n inserted in order.
func workspace(_ n: Int, bounds: CGRect = CGRect(x: 0, y: 0, width: 1000, height: 600),
               gaps: Gaps = .zero, mode: LayoutMode = .tiles, padding: CGFloat = 30) -> Workspace {
    var ws = Workspace(bounds: bounds, gaps: gaps, accordionPadding: padding, mode: mode)
    for id in 0..<n { ws.insert(WindowID(id + 1)) }
    return ws
}

func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(x: x, y: y, width: w, height: h)
}

func assertRatios(_ actual: [Double], _ expected: [Double], file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(actual.count, expected.count, file: file, line: line)
    for (a, e) in zip(actual, expected) { XCTAssertEqual(a, e, accuracy: 1e-9, file: file, line: line) }
    XCTAssertEqual(actual.reduce(0, +), 1, accuracy: 1e-9, file: file, line: line)
}
