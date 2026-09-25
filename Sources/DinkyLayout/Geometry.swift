import CoreGraphics

/// Gaps in points: `inner` between siblings, the rest at the workspace edge.
public struct Gaps: Equatable, Sendable {
    public var inner: CGFloat
    public var top: CGFloat
    public var bottom: CGFloat
    public var left: CGFloat
    public var right: CGFloat

    /// No gaps at all.
    public static let zero = Gaps(inner: 0, top: 0, bottom: 0, left: 0, right: 0)

    public init(inner: CGFloat, top: CGFloat, bottom: CGFloat, left: CGFloat, right: CGFloat) {
        self.inner = inner
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
    }

    /// The same gap everywhere.
    public init(all: CGFloat) {
        self.init(inner: all, top: all, bottom: all, left: all, right: all)
    }

    /// `rect` shrunk by the outer gaps. Rects are top-left origin, as AX uses.
    public func inset(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX + left, y: rect.minY + top,
               width: rect.width - left - right, height: rect.height - top - bottom)
    }
}

/// The result of a layout pass.
public struct Layout: Equatable, Sendable {
    /// Frame per window, top-left origin.
    public var frames: [WindowID: CGRect] = [:]
    /// Windows front to back: the first should be frontmost.
    public var order: [WindowID] = []
}

extension Container {
    /// Lay out this container in `rect`: tiles split by ratios with `gap` between siblings,
    /// accordion children overlap with neighbours peeking out by `padding`. `virtual` lays accordions out as tiles.
    func layout(in rect: CGRect, gap: CGFloat, padding: CGFloat, virtual: Bool = false, into result: inout Layout) {
        let tiled = mode == .tiles || virtual
        let rects = tiled ? tileRects(in: rect, gap: gap) : accordionRects(in: rect, padding: padding)
        for i in stackingOrder {
            switch children[i] {
            case .window(let id):
                result.frames[id] = rects[i]
                result.order.append(id)
            case .container(let c):
                c.layout(in: rects[i], gap: gap, padding: padding, virtual: virtual, into: &result)
            }
        }
    }

    /// Child indices front to back: the active child, then by distance from it, lower index first on ties.
    var stackingOrder: [Int] {
        children.indices.sorted { (abs($0 - activeIndex), $0) < (abs($1 - activeIndex), $1) }
    }

    /// Split `rect` along the orientation by ratios, `gap` between children, edges rounded to whole points.
    func tileRects(in rect: CGRect, gap: CGFloat) -> [CGRect] {
        let horizontal = orientation == .horizontal
        let origin = horizontal ? rect.minX : rect.minY
        let extent = horizontal ? rect.width : rect.height
        let available = extent - gap * CGFloat(max(children.count - 1, 0))
        var start = origin
        return ratios.map { ratio in
            let end = start + available * CGFloat(ratio)
            let (a, b) = (start.rounded(), end.rounded())
            start = end + gap
            return horizontal
                ? CGRect(x: a, y: rect.minY, width: b - a, height: rect.height)
                : CGRect(x: rect.minX, y: a, width: rect.width, height: b - a)
        }
    }

    /// Accordion rects: each child gets `rect` shrunk along the axis so neighbours of the active child peek out.
    /// Adapted from AeroSpace's layoutAccordion (MIT, github.com/nikitabobko/AeroSpace).
    func accordionRects(in rect: CGRect, padding p: CGFloat) -> [CGRect] {
        let last = children.count - 1, active = activeIndex
        return children.indices.map { i in
            let (lead, trail): (CGFloat, CGFloat) = switch i {
            case 0 where last == 0: (0, 0)
            case 0: (0, p)
            case last: (p, 0)
            case active - 1: (0, 2 * p)
            case active + 1: (2 * p, 0)
            default: (p, p)
            }
            return orientation == .horizontal
                ? CGRect(x: rect.minX + lead, y: rect.minY, width: rect.width - lead - trail, height: rect.height)
                : CGRect(x: rect.minX, y: rect.minY + lead, width: rect.width, height: rect.height - lead - trail)
        }
    }

    /// Gap-free rect of the node at `path`, used for split decisions and resize arithmetic.
    func rect(at path: [Int], in rect: CGRect) -> CGRect {
        guard let first = path.first else { return rect }
        let childRect = mode == .tiles ? tileRects(in: rect, gap: 0)[first] : rect
        guard path.count > 1, case .container(let c) = children[first] else { return childRect }
        return c.rect(at: Array(path.dropFirst()), in: childRect)
    }
}
