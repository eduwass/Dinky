import CoreGraphics

/// A display's visible frame with its top edge put where the menu bar is now, in AppKit coordinates
/// (bottom-left origin). AppKit's visible frame can keep the old menu bar after the bar hides and shows several
/// times in quick succession, and nothing refreshes it until the next change. WindowServer's autohide flag does
/// not lag, so the top edge follows that.
/// - `safeTop`: the screen's top safe-area inset, the notch, which a hidden menu bar still leaves.
/// - `knownInset`: the bar's height as the visible frame last showed it on this display; nil if it never has,
///   as on a display without a menu bar, whose visible frame is then trusted.
public func menuBarCorrected(visible: CGRect, screen: CGRect, safeTop: CGFloat, autohides: Bool,
                             knownInset: CGFloat?) -> CGRect {
    let top: CGFloat
    if autohides {
        top = screen.maxY - safeTop
    } else if visible.maxY >= screen.maxY - safeTop, let inset = knownInset {
        top = screen.maxY - inset
    } else {
        return visible
    }
    return CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: top - visible.minY)
}
