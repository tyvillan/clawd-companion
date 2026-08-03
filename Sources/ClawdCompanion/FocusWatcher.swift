import AppKit

// Tracks whether VS Code is the frontmost application, purely via public
// NSWorkspace notifications -- no special permission needed.
final class FocusWatcher {
    private static let vsCodeBundleIDs: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.vscodium",
    ]

    private let state: CompanionState
    private var observer: NSObjectProtocol?

    init(state: CompanionState) {
        self.state = state

        state.isVSCodeFocused = Self.isVSCode(NSWorkspace.shared.frontmostApplication)

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.state.isVSCodeFocused = Self.isVSCode(app)
        }
    }

    deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    private static func isVSCode(_ app: NSRunningApplication?) -> Bool {
        guard let bundleID = app?.bundleIdentifier else { return false }
        return vsCodeBundleIDs.contains(bundleID)
    }
}
