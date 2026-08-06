import SwiftUI

struct CompanionView: View {
    @ObservedObject var state: CompanionState
    /// Computed once at launch from the real Dock's measured tile size
    /// (see DockWalker.measuredTileSize) so Clawd scales with the user's
    /// actual Dock/display instead of a fixed constant.
    let pixelSize: CGFloat
    /// This companion's body color -- the original orange for the first
    /// session, a tint from SessionPalette for each concurrent one.
    var bodyColor: Color = MascotSprite.bodyColor

    private static func spriteSize(pixelSize: CGFloat) -> CGSize {
        CGSize(width: CGFloat(MascotSprite.cols) * pixelSize, height: CGFloat(MascotSprite.rows) * pixelSize)
    }

    /// How far a jump/celebrate hop lifts the sprite, scaled to its own
    /// height rather than a fixed point value -- a flat offset that worked
    /// at one size clips badly once the sprite shrinks (exactly what
    /// happened here: a fixed -10pt hop against a ~14pt-tall sprite in a
    /// window sized to fit the sprite exactly).
    private static func bounceAmplitude(pixelSize: CGFloat) -> CGFloat {
        spriteSize(pixelSize: pixelSize).height * 0.9
    }

    /// How far the floating sleep Z's rise above the sprite before fading
    /// out -- kept alongside bounceAmplitude since both compete for the same
    /// headroom below.
    private static func sleepZRise(pixelSize: CGFloat) -> CGFloat {
        spriteSize(pixelSize: pixelSize).height * 1.1
    }

    /// Fixed (not pixelSize-scaled) starting nudge for the sleep Z overlay --
    /// a pixelSize-scaled nudge shrinks to almost nothing at the small end of
    /// the clamp range, which is exactly the case that clipped: this and the
    /// Z's own upward travel both have to fit inside the window's headroom,
    /// which is sized in absolute points, not pixelSize units.
    private static let sleepZStartOffset: CGFloat = 8

    /// Half-width, from the sprite's own horizontal center, that the held
    /// blueprint prop's frame extends to on its offset side -- used to size
    /// the window's width headroom so enlarging the prop can't clip against
    /// the window's own hard edge (there's zero built-in horizontal margin
    /// otherwise, the same class of bug the sleep Z's hit before).
    private static func blueprintHalfExtent(pixelSize: CGFloat) -> CGFloat {
        spriteSize(pixelSize: pixelSize).width * 0.34 + blueprintSize(pixelSize: pixelSize) / 2
    }

    /// The window/hosting-view size AppDelegate should actually allocate,
    /// padded above the sprite so a full-amplitude hop -- or a fully-risen
    /// sleep Z -- still has somewhere to render. AppKit windows clip hard to
    /// their own frame, so whichever animation needs more headroom has to be
    /// reflected in the real window size, not just the view's internal
    /// layout. Single source of truth for both. The sleep side adds a
    /// generous flat safety margin on top of the Z's own travel + start
    /// offset -- a tighter margin here previously still clipped the glyph
    /// (confirmed by live screenshot testing), since Text's reported frame
    /// includes font leading/metrics beyond just the visible glyph ink.
    /// Width, unlike height, has zero headroom by default (the sprite's
    /// frame IS the window's width) -- padded symmetrically so the sprite
    /// stays centered on its Dock anchor (see AppDelegate.moveWindow), with
    /// a 30% safety margin the same way the sleep side over-provisions.
    static func windowSize(pixelSize: CGFloat) -> CGSize {
        let sprite = spriteSize(pixelSize: pixelSize)
        let jumpHeadroom = bounceAmplitude(pixelSize: pixelSize) * 1.15
        let sleepHeadroom = sleepZRise(pixelSize: pixelSize) + sleepZStartOffset + 40
        let propHalfExtent = max(blueprintHalfExtent(pixelSize: pixelSize), hammerHalfExtent(pixelSize: pixelSize))
        let widthHeadroom = max(0, propHalfExtent * 2 - sprite.width) * 1.3
        return CGSize(
            width: sprite.width + widthHeadroom,
            height: sprite.height + max(jumpHeadroom, sleepHeadroom)
        )
    }

    private var spriteSize: CGSize { Self.spriteSize(pixelSize: pixelSize) }
    private var bounceAmplitude: CGFloat { Self.bounceAmplitude(pixelSize: pixelSize) }
    private var totalSize: CGSize { Self.windowSize(pixelSize: pixelSize) }

    private var tickInterval: Double {
        // A named-target walk, or walking home after a VS Code refocus,
        // always paces the legs regardless of which mood is animating in
        // place -- it reads as "hustling over there."
        if state.isTargetWalking || state.isHeadingHome { return 0.12 }
        switch state.displayState {
        case .active(.typing): return 0.15
        // Slower than typing -- reads as a swing-and-strike beat rather
        // than a fast keyboard clatter.
        case .active(.working): return 0.3
        case .active(.thinking): return 0.5
        case .active(.inspecting): return 0.4
        case .active(.celebrating): return 0.15
        case .active(.waving): return 0.3
        // Fast enough to read as an urgent flash rather than a fade.
        case .active(.needsAttention): return 0.1
        case .jumping: return 0.35
        // Faster than the other in-place moods despite sleeping being the
        // "calmest" one -- the floating Z's and breathing motion need a
        // smooth-ish cadence, not the coarse 1.2s toggle rate that was fine
        // back when sleeping had no continuous motion to animate.
        case .sleeping: return 0.1
        default: return 0.6
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: tickInterval)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate / tickInterval)
            let toggle = tick % 2 == 0

            ZStack {
                spriteCanvas(
                    footOffset: footOffset(toggle: toggle),
                    eyeStyle: eyeStyle(tick: tick, toggle: toggle),
                    bodyColor: displayColor(toggle: toggle)
                )
                    .offset(y: bounceOffset(toggle: toggle, date: context.date))
                    .rotationEffect(.degrees(leanDegrees(toggle: toggle)))
                    .scaleEffect(pulseScale(toggle: toggle))

                if state.displayState == .sleeping {
                    sleepZOverlay(date: context.date)
                }

                if state.displayState == .active(.working) {
                    hammerOverlay(toggle: toggle)
                }

                if state.isPlanning {
                    blueprintOverlay()
                }
            }
        }
        .frame(width: spriteSize.width, height: spriteSize.height)
        // Expands the layout to the padded total size, keeping the
        // (unshifted-frame) sprite anchored to the bottom -- a bounce/jump
        // offset then moves the rendered pixels up into the headroom above
        // instead of past the window's own hard edge.
        .frame(width: totalSize.width, height: totalSize.height, alignment: .bottom)
        .opacity(state.isHovering ? 0.2 : 1.0)
        // Keyed on moodEventID, not mood itself -- a second identical
        // needsAttention (or celebrating/waving) occurrence arriving while
        // the first's revert timer is still pending must restart the flash
        // for its own full duration, not be silently ignored because
        // SwiftUI's onChange dedupes on the mood *value*, which didn't
        // change.
        .onChange(of: state.moodEventID) { _, eventID in
            let newMood = state.mood
            let revertDelay: Double
            switch newMood {
            case .celebrating: revertDelay = 1.5
            case .waving: revertDelay = 1.8
            // Just the flash's own duration -- if DockWalker also started a
            // walk home for this, isHeadingHome keeps displayState reporting
            // .walking (see CompanionState.displayState) well after mood
            // reverts here, so the walk itself finishes on its own schedule.
            case .needsAttention: revertDelay = 2.2
            default: return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + revertDelay) {
                // Only the timer belonging to the latest event actually
                // reverts -- a stale timer left over from an event that got
                // superseded by a fresh occurrence of the same mood must not
                // cut the newer one's display short.
                if state.moodEventID == eventID, state.mood == newMood {
                    state.mood = .idle
                }
            }
        }
    }

    private func spriteCanvas(footOffset: Int, eyeStyle: MascotSprite.EyeStyle, bodyColor: Color) -> some View {
        Canvas { gc, _ in
            let grid = MascotSprite.grid(footOffset: footOffset)
            // Body cells are accumulated into one Path and filled in a
            // single call rather than per-cell: filling each cell's rect
            // separately gives every one its own antialiasing pass, which
            // shows up as faint hairline seams between adjacent same-color
            // cells (visible as "pixel outlines"). One fill over the
            // unioned region has no internal edges to antialias.
            var bodyPath = Path()
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
                        bodyPath.addRect(rect)
                    case .eye:
                        drawEye(gc, in: rect, style: eyeStyle, bodyColor: bodyColor)
                    }
                }
            }
            gc.fill(bodyPath, with: .color(bodyColor))
        }
    }

    /// White on alternating ticks while a prompt needs attention, so the
    /// flash reads as an urgent alert rather than a color change -- every
    /// other use of bodyColor (sleep Z's, the hammer's grip mark) stays on
    /// the session's real tint, since those moods can't co-occur with this
    /// one.
    private func displayColor(toggle: Bool) -> Color {
        guard state.displayState == .active(.needsAttention) else { return bodyColor }
        return toggle ? .white : bodyColor
    }

    private static let sleepZCount = 3
    private static let sleepZCycle: Double = 2.4

    /// Position/opacity for one of the floating "Z"s in the sleep overlay,
    /// staggered by index so they rise on a continuous loop rather than all
    /// popping at once. Driven by wall-clock time (not the coarse
    /// tick/toggle used elsewhere) so the float reads as smooth motion.
    /// Deliberately no scale-up-while-rising flourish: a small scale factor
    /// stacked with the fade made the glyph fade into near-invisibility for
    /// most of the cycle (confirmed by live screenshot testing) -- a
    /// fixed-size glyph that just rises and fades reads far more reliably.
    private func sleepZPhase(date: Date, index: Int) -> (dy: CGFloat, dx: CGFloat, opacity: Double) {
        let t = date.timeIntervalSinceReferenceDate
        let phase = ((t / Self.sleepZCycle) + Double(index) / Double(Self.sleepZCount))
            .truncatingRemainder(dividingBy: 1)
        let dy = -CGFloat(phase) * Self.sleepZRise(pixelSize: pixelSize)
        // A fixed per-index lane (not just phase-driven drift) keeps the 3
        // staggered Z's from rising along nearly the same path -- with only
        // drift-based spacing they overlapped into an illegible tangle
        // (confirmed by live screenshot testing), since each one stays
        // visible for most of the whole cycle, not just its own third.
        // Centered on 0 (not all-positive): the overlay anchors to the
        // sprite's top-trailing corner with zero margin to its right, so an
        // all-rightward lane drove every Z straight off the window's own
        // right edge -- a real, confirmed regression, not just a subtler
        // version of the overlap problem.
        let lane = (CGFloat(index) - CGFloat(Self.sleepZCount - 1) / 2) * 9
        let dx = lane + CGFloat(phase) * 4
        let fadeIn = 0.15
        let opacity = phase < fadeIn ? phase / fadeIn : 1 - (phase - fadeIn) / (1 - fadeIn)
        return (dy, dx, max(0, opacity))
    }

    private func sleepZOverlay(date: Date) -> some View {
        // Centered (.top), not .topTrailing: the trailing edge sits exactly
        // at the window's own right edge with zero horizontal margin, so any
        // rightward lane/drift went straight off the window and got clipped
        // to a bare vertical sliver -- confirmed by a live screenshot report.
        // Centering gives each lane room on both sides within the sprite's
        // own width, which is comfortably wider than a Z glyph plus jitter.
        ZStack(alignment: .top) {
            ForEach(0..<Self.sleepZCount, id: \.self) { index in
                let p = sleepZPhase(date: date, index: index)
                Text("Z")
                    // A 9pt floor rendered as a fuzzy, illegible dot rather
                    // than a readable letter once opacity/antialiasing were
                    // applied (confirmed by live screenshot testing) -- this
                    // needs to read clearly as "Z", not just be present.
                    .font(.system(size: max(15, pixelSize * 4), weight: .bold, design: .rounded))
                    .foregroundStyle(bodyColor)
                    .opacity(p.opacity)
                    .offset(x: p.dx, y: p.dy)
            }
        }
        .frame(width: spriteSize.width, height: spriteSize.height, alignment: .top)
        .offset(y: -Self.sleepZStartOffset)
    }

    private static let hammerHandleColor = Color(red: 0.55, green: 0.36, blue: 0.2)
    private static let hammerHeadColor = Color(red: 0.58, green: 0.58, blue: 0.62)
    private static let hammerHeadWidth: CGFloat = 2.2
    private static let hammerHeadHeight: CGFloat = 1.1
    private static let hammerHandleHeight: CGFloat = 2.6
    /// Both extremes stay on the positive (clockwise) side of vertical --
    /// the whole swing arcs up-and-out then down on the outboard side,
    /// rather than the raised pose tipping back over his own body/face the
    /// way a negative angle did.
    private static let hammerRaisedDegrees = 75.0
    private static let hammerStruckDegrees = 15.0
    /// Fraction of the sprite's width the grip point sits out from center --
    /// lines up with the arm/ear nub's own tip (which spans the sprite's
    /// full width), so the hand reads as attached to the arm rather than
    /// floating past it.
    private static let hammerGripFraction: CGFloat = 0.46

    /// Half-width, from the sprite's own horizontal center, that the
    /// hammer's raised pose reaches on its offset side -- same purpose as
    /// blueprintHalfExtent, sized from the wider (raised) angle since that's
    /// the pose that reaches furthest out.
    private static func hammerHalfExtent(pixelSize: CGFloat) -> CGFloat {
        let totalHeight = pixelSize * (hammerHeadHeight + hammerHandleHeight)
        let angle = hammerRaisedDegrees * .pi / 180
        let reach = totalHeight * sin(angle) + (pixelSize * hammerHeadWidth / 2) * cos(angle)
        return spriteSize(pixelSize: pixelSize).width * hammerGripFraction + reach
    }

    /// Vertical nudge that lands the grip circle's center on the arm row's
    /// own center, rather than the sprite's raw vertical midpoint. hammerOverlay
    /// is laid out by the outer ZStack's default center alignment, then
    /// bottom-anchors its own content within its (handleHeight+headHeight)-tall
    /// box -- so before any offset, the grip circle's center sits at the
    /// sprite's vertical center minus half the *difference* between the
    /// sprite's height and the overlay's own height, plus half the circle's
    /// own height. The previous flat `-spriteHeight * 0.08` nudge undershot
    /// this by roughly two pixelSize units, which read as a hand-sized circle
    /// floating below Clawd's arm instead of gripping it (confirmed by
    /// measuring the grid's arm row against the overlay's un-offset position).
    private static func hammerVerticalOffset(pixelSize: CGFloat) -> CGFloat {
        let spriteHeight = spriteSize(pixelSize: pixelSize).height
        let overlayHeight = pixelSize * (hammerHandleHeight + hammerHeadHeight)
        let gripHeight = pixelSize * 1.3
        let unoffsetGripCenterFromBottom = (spriteHeight - overlayHeight) / 2 + gripHeight / 2
        let armRowCenterFromBottom = spriteHeight - (CGFloat(MascotSprite.armRow) + 0.5) * pixelSize
        return unoffsetGripCenterFromBottom - armRowCenterFromBottom
    }

    /// A held hammer, swinging on the tick/toggle beat -- shown in place of
    /// the alternating-leg gait for .active(.working), since a planted
    /// swinging stance reads as "building something" more than a walk cycle
    /// would. Built from plain rects sized to pixelSize (not new grid art)
    /// so it reads as the same blocky pixel-art language as the sprite.
    private func hammerOverlay(toggle: Bool) -> some View {
        let handleHeight = pixelSize * Self.hammerHandleHeight
        let headHeight = pixelSize * Self.hammerHeadHeight

        return ZStack(alignment: .bottom) {
            // A fixed grip mark at the pivot, in the sprite's own body color
            // -- stays put while the hammer swings around it, so it reads as
            // his hand holding the handle rather than the hammer floating
            // disconnected next to him.
            Circle()
                .fill(bodyColor)
                .frame(width: pixelSize * 1.3, height: pixelSize * 1.3)

            VStack(spacing: 0) {
                Rectangle()
                    .fill(Self.hammerHeadColor)
                    .frame(width: pixelSize * Self.hammerHeadWidth, height: headHeight)
                Rectangle()
                    .fill(Self.hammerHandleColor)
                    .frame(width: pixelSize * 0.5, height: handleHeight)
            }
            .rotationEffect(.degrees(toggle ? Self.hammerStruckDegrees : Self.hammerRaisedDegrees), anchor: .bottom)
        }
        .frame(height: handleHeight + headHeight, alignment: .bottom)
        .offset(x: spriteSize.width * Self.hammerGripFraction, y: Self.hammerVerticalOffset(pixelSize: pixelSize))
    }

    // Swapped from the initial paper-white/line-blue to match a real
    // architectural blueprint's look: blue sheet, white linework.
    private static let blueprintPaperColor = Color(red: 0.3, green: 0.42, blue: 0.72)
    private static let blueprintLineColor = Color(red: 0.93, green: 0.94, blue: 0.97)

    /// The held blueprint's overall (square) frame size -- shared with
    /// windowSize's headroom calculation so the two can never drift out of
    /// sync with each other.
    private static func blueprintSize(pixelSize: CGFloat) -> CGFloat {
        pixelSize * 5.5
    }

    /// A held blueprint/spec sheet, shown for as long as Claude Code is in
    /// plan mode (state.isPlanning) -- layered on top of whatever else is
    /// animating, since plan mode spans many tool calls and moods rather
    /// than being a mood of its own.
    private func blueprintOverlay() -> some View {
        let size = Self.blueprintSize(pixelSize: pixelSize)
        return VStack(spacing: pixelSize * 0.55) {
            ForEach(0..<3, id: \.self) { _ in
                Rectangle()
                    .fill(Self.blueprintLineColor)
                    .frame(width: pixelSize * 3.4, height: pixelSize * 0.45)
            }
        }
        .padding(pixelSize * 0.75)
        .background(Self.blueprintPaperColor)
        .frame(width: size, height: size)
        .offset(x: spriteSize.width * 0.34, y: spriteSize.height * 0.12)
    }

    private func drawEye(_ gc: GraphicsContext, in rect: CGRect, style: MascotSprite.EyeStyle, bodyColor: Color) {
        switch style {
        case .open:
            gc.fill(Path(rect), with: .color(MascotSprite.eyeColor))
        case .closed:
            // Paint the rest of the cell as body color first -- otherwise
            // the thin eyelid bar leaves the cell's top/bottom untouched
            // (transparent), which reads as a faint gap rather than a
            // visibly shut eye.
            gc.fill(Path(rect), with: .color(bodyColor))
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
        if state.isHeadingHome || state.displayState == .walking {
            return state.footToggle ? 1 : -1
        }
        switch state.displayState {
        case .active(.typing):
            return toggle ? 1 : -1
        default:
            // .active(.working) stays planted -- the hammer swing (see
            // hammerOverlay) carries the motion instead of a leg gait.
            return 0
        }
    }

    private func eyeStyle(tick: Int, toggle: Bool) -> MascotSprite.EyeStyle {
        // Alert (occasionally blinking) while actually in transit, even if
        // the underlying mood/displayState would otherwise say "asleep" --
        // e.g. walking home already-drowsy after a long unfocused stretch.
        if state.isTargetWalking || state.isHeadingHome {
            return tick % 9 == 0 ? .closed : .open
        }
        switch state.displayState {
        case .sleeping:
            return .closed
        case .active(.inspecting):
            return toggle ? .lookLeft : .lookRight
        case .walking where state.isWandering:
            // Actually mid-stride -- a brief blink every so often, otherwise
            // a static stare into the direction of travel.
            return tick % 9 == 0 ? .closed : .open
        case .walking:
            // Standing still between wanders -- glance side to side on a
            // slow cycle so idling reads as "looking around" rather than
            // either a static stare or a stalled walk cycle.
            switch tick % 18 {
            case 0, 1: return .lookLeft
            case 2, 3: return .lookRight
            case 9: return .closed
            default: return .open
            }
        default:
            return .open
        }
    }

    private func bounceOffset(toggle: Bool, date: Date) -> CGFloat {
        switch state.displayState {
        case .active(.celebrating), .jumping:
            return toggle ? -bounceAmplitude : 0
        case .active(.working):
            // A small downward dip synced to the hammer's strike beat --
            // reads as the impact, not a hop.
            return toggle ? bounceAmplitude * 0.08 : 0
        case .sleeping:
            // A continuous sine wave rather than the toggle used elsewhere --
            // sleeping now ticks at 0.1s (to animate the floating Z's
            // smoothly), and a binary toggle at that rate would flicker
            // instead of read as a gentle breathing motion.
            let t = date.timeIntervalSinceReferenceDate
            return CGFloat(sin(t * .pi / 1.4)) * 1.5
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
        // A harder pulse than celebrating's -- paired with the white flash,
        // this needs to read as an alert, not a happy bounce.
        case .active(.needsAttention):
            return toggle ? 1.18 : 1.0
        default:
            return 1.0
        }
    }
}
