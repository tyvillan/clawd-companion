import AppKit
import Combine
import SwiftUI

/// User-tunable preferences, persisted in UserDefaults under the app's
/// bundle ID. A single shared instance is observed by both the settings
/// window and the live companion, so edits apply immediately rather than
/// on next launch -- see AppDelegate's subscriptions.
///
/// Each property writes through to UserDefaults in didSet rather than
/// relying on @AppStorage: the companion's non-SwiftUI machinery
/// (AppDelegate, DockWalker) reads these too, and @AppStorage only
/// republishes inside a SwiftUI view hierarchy.
final class Settings: ObservableObject {
    static let shared = Settings()

    /// Multiplies the Dock-derived sprite size. 1.0 is the measured default
    /// (~50% of a Dock tile); the range is deliberately narrow since going
    /// much bigger stops reading as "lives among the Dock icons."
    @Published var scaleMultiplier: Double {
        didSet { defaults.set(scaleMultiplier, forKey: Keys.scaleMultiplier) }
    }

    /// Whether Clawd peeks up from the screen's bottom edge to signal a
    /// finished response while another app is in fullscreen.
    @Published var peekEnabled: Bool {
        didSet { defaults.set(peekEnabled, forKey: Keys.peekEnabled) }
    }

    /// How long the peek stays up at its apex, in seconds (excludes the
    /// fixed rise/sink animation on either side).
    @Published var peekDuration: Double {
        didSet { defaults.set(peekDuration, forKey: Keys.peekDuration) }
    }

    @Published var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Keys.soundEnabled) }
    }

    /// Name of a built-in macOS system sound (see Settings.availableSounds).
    @Published var soundName: String {
        didSet { defaults.set(soundName, forKey: Keys.soundName) }
    }

    /// Post a Notification Center banner when a response completes.
    /// Authorization is requested lazily the first time this is switched on,
    /// not at launch -- an accessory app prompting for notifications before
    /// the user has asked for any is obnoxious.
    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled) }
    }

    /// Points-per-second Clawd covers while walking. Higher is snappier;
    /// DockWalker still clamps the resulting duration so very short and very
    /// long trips stay reasonable.
    @Published var walkSpeed: Double {
        didSet { defaults.set(walkSpeed, forKey: Keys.walkSpeed) }
    }

    /// Whether Clawd wanders between Dock icons on his own when idle. Off
    /// means he only moves for a real reason (walking to a target app or
    /// back home).
    @Published var idleWanderEnabled: Bool {
        didSet { defaults.set(idleWanderEnabled, forKey: Keys.idleWanderEnabled) }
    }

    /// Whether tool activity walks him to the related app's Dock icon
    /// (Finder/Terminal/browser). Off keeps him wherever he already is and
    /// plays the mood animation in place.
    @Published var walkToTargetEnabled: Bool {
        didSet { defaults.set(walkToTargetEnabled, forKey: Keys.walkToTargetEnabled) }
    }

    /// Whether he walks back to the VS Code icon when VS Code regains focus.
    @Published var walkHomeEnabled: Bool {
        didSet { defaults.set(walkHomeEnabled, forKey: Keys.walkHomeEnabled) }
    }

    static let scaleRange: ClosedRange<Double> = 0.6...2.0
    static let peekDurationRange: ClosedRange<Double> = 0.4...5.0
    static let walkSpeedRange: ClosedRange<Double> = 40...220

    /// System sounds that exist on a stock macOS install and are short
    /// enough to work as a completion chime.
    static let availableSounds = ["Glass", "Ping", "Pop", "Blow", "Bottle", "Funk", "Hero", "Submarine", "Tink"]

    private enum Keys {
        static let scaleMultiplier = "scaleMultiplier"
        static let peekEnabled = "peekEnabled"
        static let peekDuration = "peekDuration"
        static let soundEnabled = "soundEnabled"
        static let soundName = "soundName"
        static let notificationsEnabled = "notificationsEnabled"
        static let walkSpeed = "walkSpeed"
        static let idleWanderEnabled = "idleWanderEnabled"
        static let walkToTargetEnabled = "walkToTargetEnabled"
        static let walkHomeEnabled = "walkHomeEnabled"
    }

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // register(defaults:) supplies the shipping defaults for keys the
        // user has never touched, so `object(forKey:) == nil` checks aren't
        // needed per-property and a missing key can't read back as 0/false.
        defaults.register(defaults: [
            Keys.scaleMultiplier: 1.0,
            Keys.peekEnabled: true,
            Keys.peekDuration: 1.4,
            Keys.soundEnabled: false,
            Keys.soundName: "Glass",
            Keys.notificationsEnabled: false,
            Keys.walkSpeed: 90.0,
            Keys.idleWanderEnabled: true,
            Keys.walkToTargetEnabled: true,
            Keys.walkHomeEnabled: true,
        ])

        scaleMultiplier = defaults.double(forKey: Keys.scaleMultiplier)
        peekEnabled = defaults.bool(forKey: Keys.peekEnabled)
        peekDuration = defaults.double(forKey: Keys.peekDuration)
        soundEnabled = defaults.bool(forKey: Keys.soundEnabled)
        soundName = defaults.string(forKey: Keys.soundName) ?? "Glass"
        notificationsEnabled = defaults.bool(forKey: Keys.notificationsEnabled)
        walkSpeed = defaults.double(forKey: Keys.walkSpeed)
        idleWanderEnabled = defaults.bool(forKey: Keys.idleWanderEnabled)
        walkToTargetEnabled = defaults.bool(forKey: Keys.walkToTargetEnabled)
        walkHomeEnabled = defaults.bool(forKey: Keys.walkHomeEnabled)
    }

    func resetToDefaults() {
        scaleMultiplier = 1.0
        peekEnabled = true
        peekDuration = 1.4
        soundEnabled = false
        soundName = "Glass"
        notificationsEnabled = false
        walkSpeed = 90
        idleWanderEnabled = true
        walkToTargetEnabled = true
        walkHomeEnabled = true
    }
}
