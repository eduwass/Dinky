import AppKit
import DinkyPrivate

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError

func windowPID(_ wid: UInt32) -> pid_t? {
    let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, wid) as? [[String: Any]] ?? []
    return info.first?[kCGWindowOwnerPID as String] as? pid_t
}

// A non-zero `timeout` (seconds) bounds how long AX calls on the app and the window may block.
func axWindow(pid: pid_t, wid: UInt32, timeout: Float = 0) -> AXUIElement? {
    let app = AXUIElementCreateApplication(pid)
    if timeout > 0 { AXUIElementSetMessagingTimeout(app, timeout) }
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
          let windows = value as? [AXUIElement],
          let window = windows.first(where: { axWindowID($0) == wid }) else { return nil }
    if timeout > 0 { AXUIElementSetMessagingTimeout(window, timeout) }
    return window
}

private func axWindowID(_ element: AXUIElement) -> UInt32 {
    var wid: CGWindowID = 0
    return _AXUIElementGetWindow(element, &wid) == .success ? wid : 0
}

func frontWindowID() -> UInt32 {
    guard let app = NSWorkspace.shared.frontmostApplication else { return 0 }
    var value: CFTypeRef?
    let element = AXUIElementCreateApplication(app.processIdentifier)
    guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value) == .success,
          let window = value else { return 0 }
    return axWindowID(window as! AXUIElement)
}

/// Focuses a window on a Space that is on screen: AX raise, then activate its app. Never switches Spaces:
/// the activation is dinky's own, so the activation follower is told not to chase the app's frontmost
/// window, which can still be one on another Space when the activation lands. This is the primitive for windows
/// no tree models (e.g. `focusOnScreen` when the coordinator is not running); a window the coordinator models is
/// focused through `Coordinator.focus(_:)`, which also arms the grace against stale focus reads.
func focusWindow(pid: pid_t, id: UInt32) {
    // Focus is on a window again, even when it is the one that had it before a `focus-monitor`.
    AppState.shared.displays.focusOverride = nil
    if let display = AppState.shared.displays.display(ofWindow: id) {
        noteOwnSwitch(to: display.currentSpaceID, on: display.uuid)
    }
    if let element = axWindow(pid: pid, wid: id, timeout: FrameApplier.timeout) {
        // Raise alone makes the window main; the app's key window can stay one on another Space, and the
        // next command would then act on that one. Make this window main and key explicitly.
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }
    NSRunningApplication(processIdentifier: pid)?.activate()
}
