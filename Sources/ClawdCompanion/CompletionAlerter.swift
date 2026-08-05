import AppKit
import UserNotifications

/// Plays the optional audible/banner alerts when Claude finishes a
/// response. Both are off by default; notification authorization is
/// requested the first time the banner setting is switched on rather than
/// at launch, so an accessory app never prompts unprompted.
final class CompletionAlerter {
    private let settings: Settings
    /// Nil until the first authorization attempt -- distinguishes "never
    /// asked" from "asked and denied", so a denial isn't retried on every
    /// single completion.
    private var authorizationGranted: Bool?

    init(settings: Settings) {
        self.settings = settings
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

    /// Called when the banner toggle is switched on. Safe to call
    /// repeatedly; the system only shows its prompt once per install.
    func requestNotificationAuthorizationIfNeeded() {
        guard authorizationGranted == nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            DispatchQueue.main.async { self?.authorizationGranted = granted }
        }
    }

    private func postBanner() {
        // A denial is remembered (see authorizationGranted) so we don't
        // hand the system a request it will silently drop every time.
        guard authorizationGranted != false else { return }

        let content = UNMutableNotificationContent()
        content.title = "Claude Code"
        content.body = "Finished responding."
        // Sound is handled separately above so the two toggles stay
        // independent -- attaching one here would make the banner always
        // audible regardless of the sound setting.
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
