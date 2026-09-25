import CoreGraphics
import DinkyConfig
import Foundation

/// Tag dinky puts on the key events it posts itself (switch.m), so the tap lets them through.
let selfPostedEventTag: Int64 = 0x64696E6B

/// One key-down event tap with per-mode bindings. A bound key is swallowed and its command list
/// handed to `onCommands`; anything else passes through untouched. Mode commands are the caller's
/// job: it sees `mode service` among the commands and calls `setMode`.
final class HotkeyEngine {
    private let onCommands: ([String]) -> Void
    private var modes: [String: [KeyPress: [String]]] = [:]
    private(set) var currentMode = "main"
    var enabled = true
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    /// `onCommands` is called on the main queue with the binding's commands, in order.
    init(onCommands: @escaping ([String]) -> Void) {
        self.onCommands = onCommands
    }

    /// Replaces all bindings and goes back to `main`. Keys without a keycode are logged and skipped.
    func load(modes: [String: Mode]) {
        self.modes = modes.mapValues { mode in
            var bindings: [KeyPress: [String]] = [:]
            for (combo, commands) in mode.bindings {
                guard let press = KeyPress(combo) else {
                    fputs("hotkeys: no keycode for '\(combo)', skipped\n", stderr)
                    continue
                }
                bindings[press] = commands
            }
            return bindings
        }
        currentMode = "main"
    }

    func setMode(_ name: String) {
        guard modes[name] != nil else {
            fputs("hotkeys: unknown mode '\(name)', staying in '\(currentMode)'\n", stderr)
            return
        }
        currentMode = name
    }

    /// Creates the tap on the current run loop. False if it could not (Accessibility missing).
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: hotkeyCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            fputs("hotkeys: could not create event tap (Accessibility?)\n", stderr)
            return false
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopSourceInvalidate(source) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        self.source = nil
    }

    deinit { stop() }

    /// The commands bound to this event in the current mode, if dinky should take it.
    fileprivate func commands(for event: CGEvent) -> [String]? {
        guard enabled, event.getIntegerValueField(.eventSourceUserData) != selfPostedEventTag else { return nil }
        return modes[currentMode]?[KeyPress(event)]
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown, let commands = commands(for: event) else { return Unmanaged.passUnretained(event) }
        // Run the commands after the callback returns, so slow commands never time the tap out.
        DispatchQueue.main.async { self.onCommands(commands) }
        return nil
    }
}

private func hotkeyCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                            refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<HotkeyEngine>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
}
