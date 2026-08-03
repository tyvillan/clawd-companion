import Combine
import Foundation

enum CompanionMood: String, Codable {
    case idle, thinking, typing, inspecting, working, celebrating, quit
}

/// Which dock app the current Claude Code activity relates to, driving
/// where DockWalker should walk Clawd to (independent of mood/animation).
enum TargetApp: String, Codable {
    case finder, terminal, browser
}

final class CompanionState: ObservableObject {
    @Published var mood: CompanionMood = .idle
    @Published var isVSCodeFocused: Bool = true
    @Published var targetApp: TargetApp?
    /// Flipped by DockWalker on every movement tick while walking, purely to
    /// drive the walk-cycle foot animation in CompanionView.
    @Published var footToggle: Bool = false

    /// What should actually be displayed/animated right now. Walking only
    /// happens when nothing else is going on AND VS Code has focus; if
    /// that's not true but there's also no real Claude activity, jump for
    /// attention instead. Any real activity (non-idle mood) always wins,
    /// regardless of focus -- the jump nag is specifically about idle
    /// neglect, not about interrupting active work.
    var displayState: DisplayState {
        guard mood == .idle else { return .active(mood) }
        return isVSCodeFocused ? .walking : .jumping
    }

    enum DisplayState: Equatable {
        case walking
        case jumping
        case active(CompanionMood)
    }
}
