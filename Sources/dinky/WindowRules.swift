import AppKit
import DinkyCommands
import DinkyConfig

// Window classification for the coordinator: the AX window kind and the on-window-detected rules.

extension Coordinator {
    /// False for a window to tile, true for one to float, nil while its AX element is not there yet
    /// (a retry is scheduled; after a few, the window floats since dinky could not move it anyway).
    func classify(_ window: Window) -> Bool? {
        guard let element = axWindow(pid: window.pid, wid: window.id, timeout: FrameApplier.timeout) else {
            let tries = attempts[window.id, default: 0] + 1
            attempts[window.id] = tries
            guard tries < 5 else { return true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self, let window = model.windows[window.id] else { return }
                track(window)
                flush()
            }
            return nil
        }
        attempts[window.id] = nil
        let kind = windowKind(subrole: axString(element, kAXSubroleAttribute))
        var resizable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &resizable)
        let title = axString(element, kAXTitleAttribute) ?? ""
        let rules = config.commands(for: window, kind: kind, title: title)
        // Other rule commands, such as move-window-to-workspace, run for this window once it is placed.
        for command in rules where command != .layout([.floating]) {
            DispatchQueue.main.async {
                let reply = Dispatcher.run(command, window: window.id)
                if !reply.ok { fputs("on-window-detected: \(reply.text)\n", stderr) }
            }
        }
        return kind != .normal || !resizable.boolValue || rules.contains(.layout([.floating]))
    }
}

extension Config {
    /// The commands the matching `on-window-detected` rules run, in order. Commands that do not parse are skipped.
    func commands(for window: Window, kind: WindowKind, title: String) -> [Command] {
        var commands: [Command] = []
        for rule in onWindowDetected where rule.matcher.matches(window, kind: kind, title: title) {
            commands += rule.run.compactMap { try? Command.parse($0) }
            if !rule.checkFurtherCallbacks { break }
        }
        return commands
    }
}

/// The on-window-detected kind for an AX subrole. Anything that is not a standard window, dialog or sheet is a panel.
func windowKind(subrole: String?) -> WindowKind {
    switch subrole {
    case kAXStandardWindowSubrole: .normal
    case kAXDialogSubrole, kAXSystemDialogSubrole: .dialog
    case "AXSheet": .sheet
    default: .panel
    }
}

private extension WindowMatcher {
    func matches(_ window: Window, kind: WindowKind, title: String) -> Bool {
        func search(_ pattern: String?, _ text: String?) -> Bool {
            guard let pattern else { return true }
            return text?.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        return (appId == nil || appId == window.bundleID) && (windowKind == nil || windowKind == kind)
            && search(appNameRegexSubstring, window.appName) && search(windowTitleRegexSubstring, title)
    }
}

func axString(_ element: AXUIElement, _ attribute: String) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
    return value as? String
}

