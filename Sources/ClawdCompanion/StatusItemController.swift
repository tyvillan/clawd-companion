import AppKit
import SwiftUI

/// The menu bar presence: a small mascot glyph with a menu for opening
/// Settings and quitting. This is the app's only clickable UI affordance --
/// Clawd himself deliberately ignores mouse input (see HoverWatcher) so he
/// never intercepts a Dock click.
final class StatusItemController {
    private let settings: Settings
    private let alerter: CompletionAlerter
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    /// Resolved lazily on each click rather than captured once -- companions
    /// come and go with sessions, so a stored panel list would go stale.
    private var panelProvider: () -> [NSPanel] = { [] }
    private var eventMonitors: [Any] = []

    init(settings: Settings, alerter: CompletionAlerter) {
        self.settings = settings
        self.alerter = alerter
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.menuBarGlyph()
        item.button?.toolTip = "Clawd Companion"
        item.menu = buildMenu()
        // Persists the slot the user drags it to, across relaunches and
        // rebuilds. Without this, a menu bar manager (Hidden Bar, Bartender,
        // Ice) re-files it into the hidden section every launch, where it's
        // parked far off-screen at a large negative X and looks like it was
        // never created at all.
        item.autosaveName = "ClawdCompanionStatusItem"
        statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings\u{2026}", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Clawd", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    /// Adds right-click-on-Clawd as a second way to reach the menu. A packed
    /// menu bar (or a notched display) can leave a new status item with
    /// nowhere to draw, which would otherwise make Settings unreachable.
    ///
    /// Deliberately implemented with event *monitors* rather than by giving
    /// the panel a real contextMenu: monitors observe without changing how
    /// the panel handles mouse events at all, so this can't regress
    /// click-through to the Dock icons underneath him.
    func attachContextMenu(panels: @escaping () -> [NSPanel]) {
        panelProvider = panels
        // Local covers the case where the click is delivered to us; global
        // covers it being delivered to whatever is underneath. Only one of
        // the two fires for any given click.
        let local = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] event in
            self?.showContextMenuIfOverClawd() == true ? nil : event
        }
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] _ in
            _ = self?.showContextMenuIfOverClawd()
        }
        eventMonitors = [local, global].compactMap { $0 }
    }

    /// Returns true if the click was over any live companion and the menu
    /// was shown.
    @discardableResult
    private func showContextMenuIfOverClawd() -> Bool {
        let location = NSEvent.mouseLocation
        let hit = panelProvider().contains { $0.alphaValue > 0 && $0.frame.contains(location) }
        guard hit else { return false }
        buildMenu().popUp(positioning: nil, at: location, in: nil)
        return true
    }

    /// Draws the mascot's silhouette from the same grid the sprite uses, as
    /// a *template* image so macOS tints it correctly for light/dark menu
    /// bars automatically. Rendered from the grid rather than shipping a
    /// separate PNG so it can't drift from MascotSprite.
    private static func menuBarGlyph() -> NSImage {
        let cols = CGFloat(MascotSprite.cols)
        let rows = CGFloat(MascotSprite.rows)
        // Menu bar icons top out around 18pt tall; the grid is only 7 rows,
        // so this lands at 14pt tall and 26pt wide -- legible without
        // crowding the bar. (1.4 was tried first and read as a smudge.)
        let pixel: CGFloat = 2.0
        let size = NSSize(width: cols * pixel, height: rows * pixel)

        let image = NSImage(size: size, flipped: false) { _ in
            let grid = MascotSprite.grid(footOffset: 0)
            NSColor.black.setFill()
            for y in 0..<MascotSprite.rows {
                for x in 0..<MascotSprite.cols {
                    guard grid[y][x] != .empty else { continue }
                    // The grid's row 0 is the top; NSImage's coordinate
                    // space here is bottom-up, so flip the row index.
                    let rect = NSRect(
                        x: CGFloat(x) * pixel,
                        y: (rows - 1 - CGFloat(y)) * pixel,
                        width: pixel,
                        height: pixel
                    )
                    rect.fill()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Opens Settings without going through the menu -- used by the
    /// `--settings` launch flag, which is the escape hatch if the menu bar
    /// is too full for the status item to get a slot.
    func presentSettings() {
        openSettings()
    }

    @objc private func openSettings() {
        if let window = settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        // Re-read the system's notification state each time Settings opens --
        // the user may have changed it in System Settings since last time.
        alerter.refreshAuthorization()
        let view = SettingsView(settings: settings, alerter: alerter)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 680),
            // Resizable so the whole form is reachable on a short display;
            // the Form scrolls internally when the window is smaller than
            // its content.
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentMinSize = NSSize(width: 420, height: 320)
        window.title = "Clawd Companion Settings"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false // reuse the same window on reopen
        // This is an .accessory app, so it isn't normally allowed to take
        // focus -- activate explicitly or the window opens behind whatever
        // the user was working in and the sliders don't respond to clicks.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        settingsWindow = window
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
