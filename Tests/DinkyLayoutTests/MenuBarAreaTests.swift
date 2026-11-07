import CoreGraphics
import Testing
@testable import DinkyLayout

struct MenuBarAreaTests {
    let screen = rect(0, 0, 3200, 1350)
    let shown = rect(0, 0, 3200, 1325)

    @Test func `Trusts a visible frame that agrees with the menu bar`() {
        #expect(menuBarCorrected(visible: shown, screen: screen, safeTop: 0, autohides: false, knownInset: 25) == shown)
        #expect(menuBarCorrected(visible: screen, screen: screen, safeTop: 0, autohides: true, knownInset: 25) == screen)
    }

    @Test func `Drops a stale menu bar once it hides`() {
        #expect(menuBarCorrected(visible: shown, screen: screen, safeTop: 0, autohides: true, knownInset: 25) == screen)
    }

    @Test func `Puts back a menu bar the visible frame missed`() {
        #expect(menuBarCorrected(visible: screen, screen: screen, safeTop: 0, autohides: false, knownInset: 25) == shown)
    }

    @Test func `Trusts a display that never showed a menu bar`() {
        #expect(menuBarCorrected(visible: screen, screen: screen, safeTop: 0, autohides: false, knownInset: nil) == screen)
    }

    @Test func `Keeps the Dock at the bottom`() {
        let docked = rect(0, 80, 3200, 1245)
        #expect(menuBarCorrected(visible: docked, screen: screen, safeTop: 0, autohides: true, knownInset: 25)
            == rect(0, 80, 3200, 1270))
    }

    @Test func `Stops under the notch when the menu bar hides`() {
        let laptop = rect(0, 0, 1512, 982), shownUnderNotch = rect(0, 0, 1512, 945)
        #expect(menuBarCorrected(visible: shownUnderNotch, screen: laptop, safeTop: 32, autohides: true, knownInset: 37)
            == rect(0, 0, 1512, 950))
        #expect(menuBarCorrected(visible: rect(0, 0, 1512, 950), screen: laptop, safeTop: 32, autohides: false, knownInset: 37)
            == shownUnderNotch)
    }
}
