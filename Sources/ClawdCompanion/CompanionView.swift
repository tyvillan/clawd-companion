import SwiftUI

struct CompanionView: View {
    @ObservedObject var state: CompanionState
    /// Computed once at launch from the real Dock's measured tile size
    /// (see DockWalker.measuredTileSize) so Clawd scales with the user's
    /// actual Dock/display instead of a fixed constant.
    let pixelSize: CGFloat

    private var tickInterval: Double {
        // A named-target walk always paces the legs regardless of which
        // mood is animating in place -- it reads as "hustling over there."
        if state.isTargetWalking { return 0.12 }
        switch state.displayState {
        case .active(.typing), .active(.working): return 0.15
        case .active(.thinking): return 0.5
        case .active(.inspecting): return 0.4
        case .active(.celebrating): return 0.15
        case .active(.waving): return 0.3
        case .jumping: return 0.35
        case .sleeping: return 1.2
        default: return 0.6
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: tickInterval)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate / tickInterval)
            let toggle = tick % 2 == 0

            spriteCanvas(footOffset: footOffset(toggle: toggle), eyeStyle: eyeStyle(tick: tick, toggle: toggle))
                .offset(y: bounceOffset(toggle: toggle))
                .rotationEffect(.degrees(leanDegrees(toggle: toggle)))
                .scaleEffect(pulseScale(toggle: toggle))
        }
        .frame(
            width: CGFloat(MascotSprite.cols) * pixelSize,
            height: CGFloat(MascotSprite.rows) * pixelSize
        )
        .onChange(of: state.mood) { _, newMood in
            let revertDelay: Double
            switch newMood {
            case .celebrating: revertDelay = 1.5
            case .waving: revertDelay = 1.8
            default: return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + revertDelay) {
                if state.mood == newMood { state.mood = .idle }
            }
        }
    }

    private func spriteCanvas(footOffset: Int, eyeStyle: MascotSprite.EyeStyle) -> some View {
        Canvas { gc, _ in
            let grid = MascotSprite.grid(footOffset: footOffset)
            for y in 0..<MascotSprite.rows {
                for x in 0..<MascotSprite.cols {
                    let rect = CGRect(
                        x: Double(x) * pixelSize, y: Double(y) * pixelSize,
                        width: pixelSize, height: pixelSize
                    )
                    switch grid[y][x] {
                    case .empty:
                        continue
                    case .body:
                        gc.fill(Path(rect), with: .color(MascotSprite.bodyColor))
                    case .eye:
                        drawEye(gc, in: rect, style: eyeStyle)
                    }
                }
            }
        }
    }

    private func drawEye(_ gc: GraphicsContext, in rect: CGRect, style: MascotSprite.EyeStyle) {
        switch style {
        case .open:
            gc.fill(Path(rect), with: .color(MascotSprite.eyeColor))
        case .closed:
            let bar = CGRect(
                x: rect.minX, y: rect.midY - rect.height * 0.12,
                width: rect.width, height: rect.height * 0.24
            )
            gc.fill(Path(bar), with: .color(MascotSprite.eyeColor))
        case .lookLeft, .lookRight:
            let inset = rect.width * 0.35
            let pupilX = style == .lookLeft ? rect.minX : rect.minX + inset
            let pupil = CGRect(
                x: pupilX, y: rect.minY + rect.height * 0.15,
                width: rect.width - inset, height: rect.height * 0.7
            )
            gc.fill(Path(pupil), with: .color(MascotSprite.eyeColor))
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

    private func eyeStyle(tick: Int, toggle: Bool) -> MascotSprite.EyeStyle {
        switch state.displayState {
        case .sleeping:
            return .closed
        case .active(.inspecting):
            return toggle ? .lookLeft : .lookRight
        case .walking:
            // A brief idle blink every so often -- otherwise a static stare.
            return tick % 9 == 0 ? .closed : .open
        default:
            return .open
        }
    }

    private func bounceOffset(toggle: Bool) -> CGFloat {
        switch state.displayState {
        case .active(.celebrating), .jumping:
            return toggle ? -10 : 0
        case .sleeping:
            return toggle ? -1.5 : 0
        default:
            return 0
        }
    }

    private func leanDegrees(toggle: Bool) -> Double {
        switch state.displayState {
        case .active(.waving):
            return toggle ? 10 : -10
        case .active(.inspecting):
            return toggle ? 4 : -4
        default:
            return 0
        }
    }

    private func pulseScale(toggle: Bool) -> CGFloat {
        switch state.displayState {
        case .active(.thinking):
            return toggle ? 1.08 : 1.0
        case .active(.celebrating):
            return toggle ? 1.1 : 1.0
        default:
            return 1.0
        }
    }
}
