import AppKit
import DinkyConfig
import DinkyLayout

// What the layout needs from a display: its NSScreen, name and visible area, and the config's gaps
// resolved for it.
extension Display {
    var screen: NSScreen? {
        let number = NSDeviceDescriptionKey("NSScreenNumber")
        return NSScreen.screens.first { ($0.deviceDescription[number] as? NSNumber)?.uint32Value == id }
    }

    /// The name System Settings shows, such as "Built-in Retina Display".
    var name: String { screen?.localizedName ?? "" }

    /// The frame minus menu bar and Dock, in CG coordinates (top-left origin at the primary display).
    var visibleArea: CGRect {
        guard let primary = NSScreen.screens.first, let screen else { return frame }
        let visible = screen.visibleFrame
        return CGRect(x: visible.minX, y: primary.frame.maxY - visible.maxY, width: visible.width, height: visible.height)
    }
}

extension DisplayModel {
    /// What per-monitor config values are matched against.
    func monitor(_ display: Display) -> Monitor {
        Monitor(name: display.name, isMain: display.isMain, count: displays.count)
    }
}

extension DinkyLayout.Gaps {
    /// The config's gaps as they apply on `monitor`.
    init(_ gaps: DinkyConfig.Gaps, on monitor: Monitor) {
        func value(_ v: PerMonitor) -> CGFloat { CGFloat(v.value(for: monitor)) }
        self.init(horizontal: value(gaps.inner.horizontal), vertical: value(gaps.inner.vertical),
                  top: value(gaps.outer.top), bottom: value(gaps.outer.bottom),
                  left: value(gaps.outer.left), right: value(gaps.outer.right))
    }
}
