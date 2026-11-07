import AppKit
import DinkyConfig
import DinkyLayout
import DinkyPrivate

/// The NSScreen showing a display.
func screen(of id: CGDirectDisplayID) -> NSScreen? {
    let number = NSDeviceDescriptionKey("NSScreenNumber")
    return NSScreen.screens.first { ($0.deviceDescription[number] as? NSNumber)?.uint32Value == id }
}

/// The menu bar's height as each display's visible frame last showed it, for `menuBarCorrected`.
private var menuBarInsets: [CGDirectDisplayID: CGFloat] = [:]

/// The frame minus menu bar and Dock, in CG coordinates (top-left origin at the primary display).
/// The menu bar's edge comes from WindowServer, not NSScreen alone, which can miss a quick hide or show.
func visibleArea(of id: CGDirectDisplayID) -> CGRect? {
    guard let primary = NSScreen.screens.first, let screen = screen(of: id) else { return nil }
    let safeTop = screen.safeAreaInsets.top
    let inset = screen.frame.maxY - screen.visibleFrame.maxY
    if inset > safeTop { menuBarInsets[id] = inset }
    let visible = menuBarCorrected(visible: screen.visibleFrame, screen: screen.frame, safeTop: safeTop,
                                   autohides: dinky_menu_bar_autohides(), knownInset: menuBarInsets[id])
    return CGRect(x: visible.minX, y: primary.frame.maxY - visible.maxY, width: visible.width, height: visible.height)
}

// What the layout needs from a display: its NSScreen, name, and the config's gaps
// resolved for it.
extension Display {
    /// The name System Settings shows, such as "Built-in Retina Display".
    var name: String { screen(of: id)?.localizedName ?? "" }
}

extension DisplayModel {
    /// What `[display.<pattern>]` tables are matched against.
    func monitor(_ display: Display) -> Monitor {
        Monitor(name: display.name, isMain: display.isMain, count: displays.count)
    }
}

extension DinkyLayout.Gaps {
    init(_ gaps: DinkyConfig.Gaps) {
        self.init(horizontal: CGFloat(gaps.inner.horizontal), vertical: CGFloat(gaps.inner.vertical),
                  top: CGFloat(gaps.outer.top), bottom: CGFloat(gaps.outer.bottom),
                  left: CGFloat(gaps.outer.left), right: CGFloat(gaps.outer.right))
    }
}
