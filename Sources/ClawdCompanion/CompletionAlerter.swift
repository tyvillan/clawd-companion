import AppKit
import UserNotifications

/// Plays the optional audible/banner alerts when Claude finishes a
/// response. Both are off by default; notification authorization is
/// requested when the user opts in rather than at launch, so an accessory
/// app never prompts unprompted.
final class CompletionAlerter: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    private let settings: Settings

    /// The system's real authorization state: true = authorized, false =
    /// denied, nil = not yet determined. Read from the system rather than
    /// remembered locally -- a local flag starts nil on every launch, so a
    /// previously-denied user would be re-asked forever and a previously
    /// authorized one would look undetermined.
    @Published private(set) var notificationsAuthorized: Bool?

    init(settings: Settings) {
        self.settings = settings
        super.init()

        // Must be assigned before anything is posted. Without a delegate,
        // macOS decides on its own not to present a notification from an app
        // that is currently running -- it is still *delivered*, so the API
        // reports success and it silently piles up in Notification Centre
        // with no banner ever shown. That was the whole bug.
        UNUserNotificationCenter.current().delegate = self

        refreshAuthorization()
        // A setting that persisted from a previous launch has to re-register
        // here; previously authorization was only ever requested at the
        // moment the toggle flipped, so restarting the app with it already on
        // meant the app never registered at all.
        if settings.notificationsEnabled {
            requestNotificationAuthorizationIfNeeded()
        }
    }

    /// Tells macOS to actually show the banner even though this app is
    /// running. Sound is deliberately excluded: the sound toggle is separate,
    /// and letting the notification carry its own would make banners audible
    /// regardless of that setting.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    func fire() {
        if settings.soundEnabled {
            NSSound(named: settings.soundName)?.play()
        }
        if settings.notificationsEnabled {
            postBanner()
        }
    }

    /// Plays a one-off preview of the given sound, for the Settings
    /// window's preview button -- deliberately ignores soundEnabled so the
    /// user can audition a sound before switching alerts on.
    static func preview(sound name: String) {
        NSSound(named: name)?.play()
    }

    /// Called at launch when notifications are already on, and whenever the
    /// toggle is switched on. Safe to call repeatedly -- the system only
    /// shows its prompt once, and every call refreshes the cached state.
    func requestNotificationAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            DispatchQueue.main.async { self?.notificationsAuthorized = granted }
        }
    }

    func refreshAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let value: Bool?
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: value = true
            case .denied: value = false
            default: value = nil
            }
            DispatchQueue.main.async { self?.notificationsAuthorized = value }
        }
    }

    private func postBanner() {
        // Only a hard denial is worth skipping; "not yet determined" still
        // gets posted, since the request may simply not have come back yet.
        guard notificationsAuthorized != false else { return }

        let content = UNMutableNotificationContent()
        content.title = "Claude Code"
        content.body = "Finished responding."
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
