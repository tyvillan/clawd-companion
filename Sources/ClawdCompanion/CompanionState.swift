import Combine
import Foundation

enum CompanionMood: String, Codable {
    case idle, thinking, typing, inspecting, working, celebrating, waving, quit
}

/// Which dock app the current Claude Code activity relates to, driving
/// where DockWalker should walk Clawd to (independent of mood/animation).
enum TargetApp: String, Codable {
    case finder, terminal, browser
}

final class CompanionState: ObservableObject {
    @Published var mood: CompanionMood = .idle {
        didSet {
            guard mood != oldValue else { return }
            if mood == .idle {
                idleSince = Date()
            } else {
                idleSince = nil
                isDrowsy = false
            }
        }
    }
    @Published var isVSCodeFocused: Bool = true
    @Published var targetApp: TargetApp?
    /// True only while DockWalker is actively mid-stride toward a named
    /// target (not idle wander) -- CompanionView uses this to pick up the
    /// pace regardless of which mood is currently animating in place.
    @Published var isTargetWalking: Bool = false
    /// True only while DockWalker is walking home to the VS Code icon after
    /// a refocus -- distinct from isTargetWalking since it isn't tied to
    /// TargetApp/tool activity at all.
    @Published var isHeadingHome: Bool = false
    /// True only while DockWalker is mid-stride on an idle wander (not a
    /// named target or home walk). isDrowsy is purely time-based and can
    /// flip true mid-stride -- this keeps displayState reporting .walking
    /// until he actually arrives, so he doesn't start playing the sleep
    /// animation while still sliding across the Dock.
    @Published var isWandering: Bool = false
    /// Flipped by DockWalker on every movement tick while walking, purely to
    /// drive the walk-cycle foot animation in CompanionView.
    @Published var footToggle: Bool = false
    /// True once idle has run long enough to nap instead of wander.
    @Published private(set) var isDrowsy: Bool = false
    /// Set by AppDelegate's mouse-position poll (see HoverWatcher) -- SwiftUI's
    /// own .onHover relies on a tracking area that only activates while our
    /// app is the active/frontmost app, which an LSUIElement accessory app
    /// never is, so it silently never fires here.
    @Published var isHovering: Bool = false
    /// True whenever any app (other than us) is in real macOS fullscreen --
    /// see FullScreenWatcher. AppDelegate uses this to hide the whole window.
    @Published var isAnyAppFullScreen: Bool = false

    private static let drowsyThreshold: TimeInterval = 45
    private var idleSince: Date? = Date()
    private var drowsyTimer: Timer?

    init() {
        let timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.evaluateDrowsy()
        }
        RunLoop.main.add(timer, forMode: .common)
        drowsyTimer = timer
    }

    private func evaluateDrowsy() {
        guard mood == .idle, let since = idleSince else { return }
        isDrowsy = Date().timeIntervalSince(since) > Self.drowsyThreshold
    }

    /// Called once DockWalker's home-walk (triggered by a VS Code refocus)
    /// arrives. Backdates idleSince rather than setting isDrowsy directly, so
    /// the ordinary timer-driven evaluation keeps agreeing with it on every
    /// subsequent tick instead of the two fighting each other.
    func markHomeArrival() {
        idleSince = Date().addingTimeInterval(-Self.drowsyThreshold - 1)
        evaluateDrowsy()
    }

    /// What should actually be displayed/animated right now. Walking only
    /// happens when nothing else is going on AND VS Code has focus; if
    /// that's not true but there's also no real Claude activity, jump for
    /// attention instead. Long uninterrupted idling naps in place rather
    /// than wandering. Any real activity (non-idle mood) always wins,
    /// regardless of focus -- the jump nag is specifically about idle
    /// neglect, not about interrupting active work.
    var displayState: DisplayState {
        guard mood == .idle else { return .active(mood) }
        if !isVSCodeFocused { return .jumping }
        // Any of the three ways he can be mid-transit (idle wander, walking
        // home after a refocus, walking to a named target) has to keep
        // reporting .walking regardless of isDrowsy -- otherwise the sleep
        // animation (closed eyes, floating Z's, breathing bob) can start
        // while he's still visibly sliding across the Dock toward wherever
        // he was headed.
        if isWandering || isHeadingHome || isTargetWalking { return .walking }
        return isDrowsy ? .sleeping : .walking
    }

    enum DisplayState: Equatable {
        case walking
        case jumping
        case sleeping
        case active(CompanionMood)
    }
}
