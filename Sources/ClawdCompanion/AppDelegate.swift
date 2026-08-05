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
    private var statusItemController: StatusItemController!
    private var alerter: CompletionAlerter!
    private var hosting: NSHostingView<CompanionView>!
    private let state = CompanionState()
    private let settings = Settings.shared
    private var cancellables = Set<AnyCancellable>()

    private var windowSize = NSSize.zero
    /// True only for the few seconds a completion peek is actually playing
    /// -- guards the fullscreen-hide subscription from fighting the peek's
    /// own manual alpha/position control.
    private var isPeeking = false

    /// ~50% of a real Dock icon's size (nudged up from 40% per request --
    /// still comfortably smaller than the icons themselves), clamped in case
    /// tile-size detection fails entirely (Tier 3 fallback in DockWalker),
    /// then scaled by the user's size preference. The clamp is applied
    /// before the multiplier so the setting can still take him deliberately
    /// larger than the Dock-derived default.
    private static func pixelSize(forMeasuredTileSize tileSize: CGFloat, scale: Double) -> CGFloat {
        let raw = (tileSize * 0.5) / CGFloat(MascotSprite.cols)
        return min(5, max(2, raw)) * scale
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // .accessory keeps him out of the Dock and the app switcher; the
        // status bar item below is the app's only chrome.
        NSApp.setActivationPolicy(.accessory)

        alerter = CompletionAlerter(settings: settings)
        statusItemController = StatusItemController(settings: settings, alerter: alerter)
        statusItemController.install()

        focusWatcher = FocusWatcher(state: state)
        fullScreenWatcher = FullScreenWatcher(state: state)

        let walker = DockWalker(state: state)
        walker.requestAccessibilityIfNeeded()
        walker.primeGeometry() // measures the real Dock before we size the window

        let pixelSize = Self.pixelSize(
            forMeasuredTileSize: walker.measuredTileSize,
            scale: settings.scaleMultiplier
        )
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

        let hostingView = NSHostingView(rootView: CompanionView(state: state, pixelSize: pixelSize))
        hostingView.frame = NSRect(origin: .zero, size: windowSize)
        newPanel.contentView = hostingView
        newPanel.orderFrontRegardless()
        panel = newPanel
        hosting = hostingView
        hoverWatcher = HoverWatcher(state: state, panel: newPanel)
        statusItemController.attachContextMenu(to: newPanel)

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
            .removeDuplicates()
            .sink { [weak self] mood in
                guard let self, mood == .celebrating else { return }
                self.alerter.fire()
                guard self.settings.peekEnabled, self.state.isAnyAppFullScreen else { return }
                self.performCompletionPeek()
            }
            .store(in: &cancellables)

        // Resizing has to rebuild the sprite view and the panel frame
        // together -- CompanionView takes pixelSize as a stored constant and
        // AppKit clips to the window's own frame, so changing one without
        // the other either does nothing visible or crops him.
        settings.$scaleMultiplier
            .removeDuplicates()
            .dropFirst() // the launch value is already applied above
            .sink { [weak self] scale in
                self?.applyScale(scale)
            }
            .store(in: &cancellables)

        // `open -a ClawdCompanion --args --settings` (or running the binary
        // with the flag) opens Settings directly -- the way in when the menu
        // bar has no room left for the status item.
        if CommandLine.arguments.contains("--settings") {
            statusItemController.presentSettings()
        }
    }

    private func applyScale(_ scale: Double) {
        guard let panel, let hosting, let dockWalker else { return }
        let pixelSize = Self.pixelSize(forMeasuredTileSize: dockWalker.measuredTileSize, scale: scale)
        windowSize = CompanionView.windowSize(pixelSize: pixelSize)
        hosting.rootView = CompanionView(state: state, pixelSize: pixelSize)
        hosting.frame = NSRect(origin: .zero, size: windowSize)
        panel.setContentSize(windowSize)
        // Re-anchor immediately: moveWindow centers on the Dock position
        // using windowSize, so a resize without this leaves him visibly
        // off-center until his next walk.
        moveWindow(to: dockWalker.position)
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
            DispatchQueue.main.asyncAfter(deadline: .now() + self.settings.peekDuration) {
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
