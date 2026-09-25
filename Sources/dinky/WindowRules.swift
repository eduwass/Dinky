import AppKit
import DinkyCommands
import DinkyConfig

// Window classification helpers for the coordinator: the AX window kind and the on-window-detected rules.

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

