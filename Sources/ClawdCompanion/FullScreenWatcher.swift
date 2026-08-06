import AppKit
import ApplicationServices

// Polls the frontmost application's focused/main window for the AXFullScreen
// attribute. NSWorkspace notifications only cover switching *between* apps,
// not toggling fullscreen on the app that's already frontmost (e.g. clicking
// the green button on the current window), so a FocusWatcher-style
// notification approach can't catch every case -- a lightweight poll (same
// pattern as HoverWatcher) is the reliable fallback. Requires Accessibility;
// silently reports false (never hides Clawd) if it isn't granted.
final class FullScreenWatcher {
    /// Fullscreen is machine-wide, not per-session, so this broadcasts to
    /// every live companion rather than owning one state.
    private let onChange: (Bool) -> Void
    private var timer: Timer?

    private(set) var isFullScreen = false

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        evaluate()
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.evaluate()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func evaluate() {
        let value = Self.frontmostAppIsFullScreen()
        guard value != isFullScreen else { return }
        isFullScreen = value
        onChange(value)
    }

    private static func frontmostAppIsFullScreen() -> Bool {
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return false }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef) != .success {
            guard AXUIElementCopyAttributeValue(axApp, kAXMainWindowAttribute as CFString, &windowRef) == .success
            else { return false }
        }
        guard let windowRef, CFGetTypeID(windowRef) == AXUIElementGetTypeID() else { return false }
        // swiftlint:disable:next force_cast
        let window = windowRef as! AXUIElement

        var fullScreenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullScreenRef) == .success,
              let isFullScreen = fullScreenRef as? Bool
        else { return false }
        return isFullScreen
    }
}
