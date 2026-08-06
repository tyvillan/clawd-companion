import SwiftUI

/// Colors used to tell concurrent Claude Code sessions apart on the Dock.
///
/// Slot 0 is always the original orange, so a single-session setup looks
/// exactly like it always has and the "first" session stays recognizable;
/// only additional concurrent sessions get a tint. Slots are recycled when
/// a session ends, so closing the blue one and opening another gives the
/// new session blue again rather than marching down the list forever.
enum SessionPalette {
    static let primary = MascotSprite.bodyColor

    /// Deliberately muted rather than fully saturated -- these sit against
    /// the Dock's own bright icons, and saturated variants read as UI
    /// elements rather than as the same character in a different color.
    static let variants: [Color] = [
        Color(red: 0.29, green: 0.53, blue: 0.82), // blue
        Color(red: 0.34, green: 0.64, blue: 0.42), // green
        Color(red: 0.56, green: 0.43, blue: 0.78), // purple
        Color(red: 0.85, green: 0.63, blue: 0.24), // amber
        Color(red: 0.78, green: 0.40, blue: 0.60), // magenta
        Color(red: 0.28, green: 0.63, blue: 0.66), // teal
    ]

    static func color(forSlot slot: Int) -> Color {
        guard slot > 0 else { return primary }
        return variants[(slot - 1) % variants.count]
    }

    /// Horizontal gap between adjacent companions, so concurrent sessions
    /// stand shoulder to shoulder instead of stacking on the same Dock icon
    /// whenever they converge on the same target.
    static func slotOffset(forSlot slot: Int, spriteWidth: CGFloat) -> CGFloat {
        // Slot 0 gets no offset at all -- a lone session sits exactly where
        // it did before multi-session existed.
        CGFloat(slot) * (spriteWidth * 0.85 + 4)
    }
}
