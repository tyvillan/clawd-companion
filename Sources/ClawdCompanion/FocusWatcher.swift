import AppKit

// Tracks whether VS Code is the frontmost application, purely via public
// NSWorkspace notifications -- no special permission needed.
final class FocusWatcher {
    private static let vsCodeBundleIDs: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.vscodium",
    ]

    /// Focus is machine-wide, not per-session, so this broadcasts to every
    /// live companion rather than owning one state.
    private let onChange: (Bool) -> Void
    private var observer: NSObjectProtocol?

    private(set) var isFocused: Bool

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        isFocused = Self.isVSCode(NSWorkspace.shared.frontmostApplication)
        onChange(isFocused)

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self.isFocused = Self.isVSCode(app)
            self.onChange(self.isFocused)
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
