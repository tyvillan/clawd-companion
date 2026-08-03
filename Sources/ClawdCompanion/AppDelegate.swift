import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel!
    private var watcher: StateFileWatcher!
    private var dockWalker: DockWalker!
    private var focusWatcher: FocusWatcher!
    private var hoverWatcher: HoverWatcher!
    private var fullScreenWatcher: FullScreenWatcher!
    private let state = CompanionState()
    private var cancellables = Set<AnyCancellable>()

    private var windowSize = NSSize.zero
    /// True only for the few seconds a completion peek is actually playing
    /// -- guards the fullscreen-hide subscription from fighting the peek's
    /// own manual alpha/position control.
    private var isPeeking = false

    /// ~40% of a real Dock icon's size (shrunk down from an earlier, larger
    /// pass per explicit request), clamped in case tile-size detection fails
    /// entirely (Tier 3 fallback in DockWalker).
    private static func pixelSize(forMeasuredTileSize tileSize: CGFloat) -> CGFloat {
        let raw = (tileSize * 0.4) / CGFloat(MascotSprite.cols)
        return min(4, max(1.6, raw))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // no Dock icon, no menu bar item

        focusWatcher = FocusWatcher(state: state)
        fullScreenWatcher = FullScreenWatcher(state: state)

        let walker = DockWalker(state: state)
        walker.requestAccessibilityIfNeeded()
        walker.primeGeometry() // measures the real Dock before we size the window

        let pixelSize = Self.pixelSize(forMeasuredTileSize: walker.measuredTileSize)
        windowSize = CompanionView.windowSize(pixelSize: pixelSize)

        let newPanel = NSPanel(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = false
        // The real Dock draws at a window level above .floating -- with a
        // lower level, whenever the companion's rect overlaps the Dock's
        // own bar (even slightly, from a calibration nudge), the Dock
        // painted over roughly half the sprite. Sitting one level above the
        // Dock's own level guarantees Clawd always renders on top of it.
        newPanel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        // .canJoinAllSpaces is also what lets this window show up over a
        // *full-screen* app's dedicated Space -- exactly the behavior the
        // fullscreen-hide subscription below exists to suppress by default.
        newPanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        // Position is entirely DockWalker-driven -- don't let a stray drag
        // knock Clawd off the Dock.
        newPanel.isMovableByWindowBackground = false
        newPanel.isMovable = false

        let hosting = NSHostingView(rootView: CompanionView(state: state, pixelSize: pixelSize))
        hosting.frame = NSRect(origin: .zero, size: windowSize)
        newPanel.contentView = hosting
        newPanel.orderFrontRegardless()
        panel = newPanel
        hoverWatcher = HoverWatcher(state: state, panel: newPanel)

        walker.onPositionChange = { [weak self] point in
            self?.moveWindow(to: point)
        }
        walker.onFootToggle = { [weak self] in
            self?.state.footToggle.toggle()
        }
        dockWalker = walker
        walker.start()

        let statePath = ("~/.claude/creature/state.json" as NSString).expandingTildeInPath
        watcher = StateFileWatcher(path: statePath, state: state) { [weak self] in
            self?.fadeOutAndQuit()
        }

        state.$isAnyAppFullScreen
            .removeDuplicates()
            .sink { [weak self] isFullScreen in
                guard let self, !self.isPeeking else { return }
                self.panel.alphaValue = isFullScreen ? 0 : 1
            }
            .store(in: &cancellables)

        state.$mood
            .sink { [weak self] mood in
                guard let self, mood == .celebrating, self.state.isAnyAppFullScreen else { return }
                self.performCompletionPeek()
            }
            .store(in: &cancellables)
    }

    private func moveWindow(to anchor: CGPoint) {
        guard !isPeeking else { return } // the peek owns the window's position for its duration
        panel.setFrameOrigin(NSPoint(x: anchor.x - windowSize.width / 2, y: anchor.y))
    }

    /// Briefly shows Clawd rising from the bottom edge of the screen while a
    /// full-screen app is active, to signal a completed response/task, then
    /// sinks back out of view. The Dock (and Clawd's usual Dock-anchored
    /// position) isn't visible at all during fullscreen, so this is
    /// deliberately screen-edge-relative rather than Dock-relative.
    private func performCompletionPeek() {
        guard let panel, let screen = NSScreen.main, !isPeeking else { return }
        isPeeking = true

        let x = min(max(panel.frame.origin.x, screen.frame.minX), screen.frame.maxX - windowSize.width)
        let hiddenY = screen.frame.minY - windowSize.height - 4
        let peekY = screen.frame.minY + 12

        panel.setFrameOrigin(NSPoint(x: x, y: hiddenY))
        panel.alphaValue = 1

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrameOrigin(NSPoint(x: x, y: peekY))
        }, completionHandler: { [weak self] in
            guard let self else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.4
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    panel.animator().setFrameOrigin(NSPoint(x: x, y: hiddenY))
                }, completionHandler: {
                    self.isPeeking = false
                    panel.alphaValue = self.state.isAnyAppFullScreen ? 0 : 1
                    // Hand positioning back to DockWalker's own idea of
                    // where Clawd belongs, now that the peek is done.
                    self.moveWindow(to: self.dockWalker.position)
                })
            }
        })
    }

    private func fadeOutAndQuit() {
        guard let panel else { NSApp.terminate(nil); return }
        NSAnimationContext.runAnimationGroup(
            { ctx in
                ctx.duration = 0.25
                panel.animator().alphaValue = 0
            },
            completionHandler: {
                NSApp.terminate(nil)
            }
        )
    }
}
