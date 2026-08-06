import AppKit
import Combine
import SwiftUI

/// Owns everything machine-wide -- the menu bar item, settings, focus and
/// fullscreen watching -- and one SessionCompanion per live Claude Code
/// session. Anything session-scoped (mood, movement, the panel itself)
/// belongs to the companion, not here.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var registry: SessionRegistry!
    private var focusWatcher: FocusWatcher!
    private var fullScreenWatcher: FullScreenWatcher!
    private var statusItemController: StatusItemController!
    private var alerter: CompletionAlerter!

    private let settings = Settings.shared
    private var cancellables = Set<AnyCancellable>()

    /// Live companions keyed by session id, plus the slots they occupy.
    private var companions: [String: SessionCompanion] = [:]
    /// True once at least one session has existed, so an empty sessions
    /// directory at launch (the hook may not have written yet) doesn't read
    /// as "every session ended" and quit immediately.
    private var hasSeenASession = false

    private static let sessionsDirectory =
        ("~/.claude/creature/sessions" as NSString).expandingTildeInPath

    func applicationDidFinishLaunching(_ notification: Notification) {
        // .accessory keeps him out of the Dock and the app switcher; the
        // status bar item below is the app's only chrome.
        NSApp.setActivationPolicy(.accessory)

        alerter = CompletionAlerter(settings: settings)
        statusItemController = StatusItemController(settings: settings, alerter: alerter)
        statusItemController.install()
        statusItemController.attachContextMenu { [weak self] in
            self?.companions.values.map(\.panel) ?? []
        }

        focusWatcher = FocusWatcher { [weak self] focused in
            self?.companions.values.forEach { $0.state.isVSCodeFocused = focused }
        }
        fullScreenWatcher = FullScreenWatcher { [weak self] isFullScreen in
            guard let self else { return }
            self.companions.values.forEach {
                $0.state.isAnyAppFullScreen = isFullScreen
                $0.setFullScreenHidden(isFullScreen)
            }
        }

        settings.$scaleMultiplier
            .removeDuplicates()
            .dropFirst() // the launch value is already applied per companion
            .sink { [weak self] scale in
                self?.companions.values.forEach { $0.applyScale(scale) }
            }
            .store(in: &cancellables)

        registry = SessionRegistry(directory: Self.sessionsDirectory)
        registry.onChange = { [weak self] added, removed in
            self?.applySessionChanges(added: added, removed: removed)
        }
        registry.start()

        if CommandLine.arguments.contains("--settings") {
            statusItemController.presentSettings()
        }
    }

    private func applySessionChanges(added: [String], removed: [String]) {
        for id in removed {
            companions.removeValue(forKey: id)?.close()
        }
        for id in added where companions[id] == nil {
            hasSeenASession = true
            spawnCompanion(for: id)
        }
        // Re-pack slots so ending an earlier session closes the gap instead
        // of leaving a hole (and stranding its color unused).
        repackSlots()

        if hasSeenASession, companions.isEmpty {
            fadeOutAndQuit()
        }
    }

    private func spawnCompanion(for sessionID: String) {
        let companion = SessionCompanion(
            sessionID: sessionID,
            slotIndex: nextFreeSlot(),
            statePath: SessionRegistry.statePath(directory: Self.sessionsDirectory, sessionID: sessionID),
            settings: settings,
            alerter: alerter
        )
        // Seed the machine-wide state the watchers already know about --
        // a companion spawning mid-session would otherwise start out
        // assuming focused and not-fullscreen until the next change.
        companion.state.isVSCodeFocused = focusWatcher.isFocused
        companion.state.isAnyAppFullScreen = fullScreenWatcher.isFullScreen
        companion.setFullScreenHidden(fullScreenWatcher.isFullScreen)
        companion.onQuitRequested = { [weak self] in
            self?.handleQuitRequest(from: sessionID)
        }
        companions[sessionID] = companion
    }

    private func nextFreeSlot() -> Int {
        let taken = Set(companions.values.map(\.slotIndex))
        var slot = 0
        while taken.contains(slot) { slot += 1 }
        return slot
    }

    /// Assigns slots 0..n-1 in a stable order so the set of colors on screen
    /// is always a prefix of the palette. Sorted by session id (not by
    /// arrival) so the ordering is deterministic across relaunches.
    private func repackSlots() {
        for (index, id) in companions.keys.sorted().enumerated() {
            companions[id]?.reassign(slotIndex: index)
        }
    }

    /// A session's state file asked the app to quit outright (the legacy
    /// `"quit"` mood). Treat it as that one session ending; the app only
    /// exits once nothing is left.
    private func handleQuitRequest(from sessionID: String) {
        companions.removeValue(forKey: sessionID)?.close()
        repackSlots()
        if companions.isEmpty {
            fadeOutAndQuit()
        }
    }

    private func fadeOutAndQuit() {
        let panels = companions.values.map(\.panel)
        guard !panels.isEmpty else { NSApp.terminate(nil); return }
        NSAnimationContext.runAnimationGroup(
            { ctx in
                ctx.duration = 0.25
                panels.forEach { $0.animator().alphaValue = 0 }
            },
            completionHandler: {
                NSApp.terminate(nil)
            }
        )
    }
}
