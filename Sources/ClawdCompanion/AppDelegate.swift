import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel!
    private var watcher: StateFileWatcher!
    private var dockWalker: DockWalker!
    private var focusWatcher: FocusWatcher!
    private let state = CompanionState()

    private var windowSize = NSSize.zero

    /// 60-75% of a real Dock icon's size, clamped in case tile-size
    /// detection fails entirely (Tier 3 fallback in DockWalker).
    private static func pixelSize(forMeasuredTileSize tileSize: CGFloat) -> CGFloat {
        let raw = (tileSize * 0.68) / CGFloat(MascotSprite.cols)
        return min(6, max(2.5, raw))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // no Dock icon, no menu bar item

        focusWatcher = FocusWatcher(state: state)

        let walker = DockWalker(state: state)
        walker.requestAccessibilityIfNeeded()
        walker.primeGeometry() // measures the real Dock before we size the window

        let pixelSize = Self.pixelSize(forMeasuredTileSize: walker.measuredTileSize)
        windowSize = NSSize(
            width: CGFloat(MascotSprite.cols) * pixelSize,
            height: CGFloat(MascotSprite.rows) * pixelSize
        )

        let newPanel = NSPanel(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = false
        newPanel.level = .floating
        newPanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        newPanel.isMovableByWindowBackground = true

        let hosting = NSHostingView(rootView: CompanionView(state: state, pixelSize: pixelSize))
        hosting.frame = NSRect(origin: .zero, size: windowSize)
        newPanel.contentView = hosting
        newPanel.orderFrontRegardless()
        panel = newPanel

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
    }

    private func moveWindow(to anchor: CGPoint) {
        panel.setFrameOrigin(NSPoint(x: anchor.x - windowSize.width / 2, y: anchor.y))
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
