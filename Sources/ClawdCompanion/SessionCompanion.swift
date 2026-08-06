import AppKit
import Combine
import SwiftUI

/// One Claude Code session's on-screen companion: its own state, its own
/// Dock walker, and its own borderless panel. Everything here is scoped to
/// a single session -- a tool call in one session only ever moves and
/// animates that session's companion, because each reads a different
/// `<session_id>.json`.
///
/// Shared, machine-wide concerns (VS Code focus, fullscreen, settings, the
/// menu bar item) deliberately live in AppDelegate and are broadcast in,
/// rather than being re-derived per session.
final class SessionCompanion {
    let sessionID: String
    let state = CompanionState()
    /// Position among the concurrent companions: 0 is the original orange
    /// one sitting exactly where a lone companion would.
    private(set) var slotIndex: Int

    let panel: NSPanel

    private let settings: Settings
    private let alerter: CompletionAlerter
    private let hosting: NSHostingView<CompanionView>
    private let walker: DockWalker
    private var hoverWatcher: HoverWatcher!
    private var watcher: StateFileWatcher!
    private var cancellables = Set<AnyCancellable>()

    private var windowSize: NSSize
    private var pixelSize: CGFloat
    private var isPeeking = false

    /// Invoked when this session's state file reports it should go away.
    var onQuitRequested: (() -> Void)?

    init(sessionID: String, slotIndex: Int, statePath: String, settings: Settings, alerter: CompletionAlerter) {
        self.sessionID = sessionID
        self.slotIndex = slotIndex
        self.settings = settings
        self.alerter = alerter

        let walker = DockWalker(state: state, settings: settings)
        walker.requestAccessibilityIfNeeded()
        walker.primeGeometry() // measures the real Dock before we size the window
        self.walker = walker

        pixelSize = Self.pixelSize(forMeasuredTileSize: walker.measuredTileSize, scale: settings.scaleMultiplier)
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
        // fullscreen-hide handling below exists to suppress by default.
        newPanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        // Position is entirely DockWalker-driven -- don't let a stray drag
        // knock Clawd off the Dock.
        newPanel.isMovableByWindowBackground = false
        newPanel.isMovable = false

        let view = CompanionView(state: state, pixelSize: pixelSize, bodyColor: SessionPalette.color(forSlot: slotIndex))
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: windowSize)
        newPanel.contentView = hostingView
        newPanel.orderFrontRegardless()
        panel = newPanel
        hosting = hostingView

        hoverWatcher = HoverWatcher(state: state, panel: newPanel)

        walker.onPositionChange = { [weak self] point in
            self?.moveWindow(to: point)
        }
        walker.onFootToggle = { [weak self] in
            self?.state.footToggle.toggle()
        }
        walker.start()

        watcher = StateFileWatcher(path: statePath, state: state) { [weak self] in
            self?.onQuitRequested?()
        }

        state.$mood
            .removeDuplicates()
            .sink { [weak self] mood in
                guard let self else { return }
                switch mood {
                case .celebrating:
                    self.alerter.fireCompletion()
                    guard self.settings.peekEnabled, self.state.isAnyAppFullScreen else { return }
                    self.performCompletionPeek()
                case .needsAttention:
                    self.alerter.fireNeedsAttention()
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

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

    func applyScale(_ scale: Double) {
        pixelSize = Self.pixelSize(forMeasuredTileSize: walker.measuredTileSize, scale: scale)
        windowSize = CompanionView.windowSize(pixelSize: pixelSize)
        hosting.rootView = CompanionView(
            state: state,
            pixelSize: pixelSize,
            bodyColor: SessionPalette.color(forSlot: slotIndex)
        )
        hosting.frame = NSRect(origin: .zero, size: windowSize)
        panel.setContentSize(windowSize)
        // Re-anchor immediately: moveWindow centers on the Dock position
        // using windowSize, so a resize without this leaves him visibly
        // off-center until his next walk.
        moveWindow(to: walker.position)
    }

    /// Re-packs this companion into a different slot -- used when an earlier
    /// session ends and later ones shuffle down to close the gap.
    func reassign(slotIndex newIndex: Int) {
        guard newIndex != slotIndex else { return }
        slotIndex = newIndex
        hosting.rootView = CompanionView(
            state: state,
            pixelSize: pixelSize,
            bodyColor: SessionPalette.color(forSlot: newIndex)
        )
        moveWindow(to: walker.position)
    }

    func setFullScreenHidden(_ hidden: Bool) {
        guard !isPeeking else { return } // the peek owns alpha for its duration
        panel.alphaValue = hidden ? 0 : 1
    }

    func close() {
        cancellables.removeAll()
        walker.stop()
        hoverWatcher.stop()
        watcher.stop()
        panel.orderOut(nil)
        panel.close()
    }

    private func moveWindow(to anchor: CGPoint) {
        guard !isPeeking else { return } // the peek owns the window's position for its duration
        let slot = SessionPalette.slotOffset(forSlot: slotIndex, spriteWidth: windowSize.width)
        panel.setFrameOrigin(NSPoint(x: anchor.x - windowSize.width / 2 + slot, y: anchor.y))
    }

    /// Briefly shows Clawd rising from the bottom edge of the screen while a
    /// full-screen app is active, to signal a completed response/task, then
    /// sinks back out of view. The Dock (and Clawd's usual Dock-anchored
    /// position) isn't visible at all during fullscreen, so this is
    /// deliberately screen-edge-relative rather than Dock-relative.
    private func performCompletionPeek() {
        guard let screen = NSScreen.main, !isPeeking else { return }
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
                    self.panel.animator().setFrameOrigin(NSPoint(x: x, y: hiddenY))
                }, completionHandler: {
                    self.isPeeking = false
                    self.panel.alphaValue = self.state.isAnyAppFullScreen ? 0 : 1
                    // Hand positioning back to DockWalker's own idea of
                    // where Clawd belongs, now that the peek is done.
                    self.moveWindow(to: self.walker.position)
                })
            }
        })
    }
}
