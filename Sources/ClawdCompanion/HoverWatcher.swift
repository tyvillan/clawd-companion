import AppKit

// Polls the global mouse position against the companion window's frame.
// SwiftUI's built-in .onHover relies on an NSTrackingArea that's only active
// while our app is the frontmost/active app -- an LSUIElement accessory app
// (see AppDelegate) never becomes that, so it silently never fires here.
// NSEvent.mouseLocation works regardless of which app is active, same as
// FocusWatcher's approach to focus tracking, so a lightweight poll is the
// reliable alternative.
final class HoverWatcher {
    private let state: CompanionState
    private weak var panel: NSPanel?
    private var timer: Timer?

    init(state: CompanionState, panel: NSPanel) {
        self.state = state
        self.panel = panel
        let t = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// The run loop retains the timer independently of this object, so a
    /// released HoverWatcher would otherwise keep polling forever (harmless
    /// but permanent). Companions are created and destroyed per session
    /// now, so that leak would accumulate.
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        stop()
    }

    private func poll() {
        guard let panel else { return }
        let hovering = panel.frame.contains(NSEvent.mouseLocation)
        if hovering != state.isHovering {
            state.isHovering = hovering
        }
    }
}
