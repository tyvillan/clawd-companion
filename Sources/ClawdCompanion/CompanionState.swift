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
    /// Flipped by DockWalker on every movement tick while walking, purely to
    /// drive the walk-cycle foot animation in CompanionView.
    @Published var footToggle: Bool = false
    /// True once idle has run long enough to nap instead of wander.
    @Published private(set) var isDrowsy: Bool = false

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
        return isDrowsy ? .sleeping : .walking
    }

    enum DisplayState: Equatable {
        case walking
        case jumping
        case sleeping
        case active(CompanionMood)
    }
}
