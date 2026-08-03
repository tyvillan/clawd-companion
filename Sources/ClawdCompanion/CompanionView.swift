import SwiftUI

struct CompanionView: View {
    @ObservedObject var state: CompanionState
    /// Computed once at launch from the real Dock's measured tile size
    /// (see DockWalker.measuredTileSize) so Clawd scales with the user's
    /// actual Dock/display instead of a fixed constant.
    let pixelSize: CGFloat

    private var tickInterval: Double {
        switch state.displayState {
        case .active(.typing), .active(.working): return 0.15
        case .active(.thinking): return 0.5
        case .active(.inspecting): return 0.6
        case .active(.celebrating): return 0.15
        case .jumping: return 0.35
        default: return 0.6
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: tickInterval)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate / tickInterval)
            let toggle = tick % 2 == 0

            spriteCanvas(footOffset: footOffset(toggle: toggle))
                .offset(y: bounceOffset(toggle: toggle))
                .rotationEffect(.degrees(leanDegrees(toggle: toggle)))
                .scaleEffect(pulseScale(toggle: toggle))
        }
        .frame(
            width: CGFloat(MascotSprite.cols) * pixelSize,
            height: CGFloat(MascotSprite.rows) * pixelSize
        )
        .onChange(of: state.mood) { _, newMood in
            guard newMood == .celebrating else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if state.mood == .celebrating { state.mood = .idle }
            }
        }
    }

    private func spriteCanvas(footOffset: Int) -> some View {
        Canvas { gc, _ in
            let grid = MascotSprite.grid(footOffset: footOffset)
            for y in 0..<MascotSprite.rows {
                for x in 0..<MascotSprite.cols {
                    guard let color = grid[y][x] else { continue }
                    let rect = CGRect(
                        x: Double(x) * pixelSize, y: Double(y) * pixelSize,
                        width: pixelSize, height: pixelSize
                    )
                    gc.fill(Path(rect), with: .color(color))
                }
            }
        }
    }

    private func footOffset(toggle: Bool) -> Int {
        switch state.displayState {
        case .walking:
            return state.footToggle ? 1 : -1
        case .active(.typing), .active(.working):
            return toggle ? 1 : -1
        default:
            return 0
        }
    }

    private func bounceOffset(toggle: Bool) -> CGFloat {
        switch state.displayState {
        case .active(.celebrating), .jumping:
            return toggle ? -10 : 0
        default:
            return 0
        }
    }

    private func leanDegrees(toggle: Bool) -> Double {
        if case .active(.inspecting) = state.displayState {
            return toggle ? 8 : -8
        }
        return 0
    }

    private func pulseScale(toggle: Bool) -> CGFloat {
        if case .active(.thinking) = state.displayState {
            return toggle ? 1.08 : 1.0
        }
        return 1.0
    }
}
