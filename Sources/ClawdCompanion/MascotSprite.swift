import SwiftUI

// Flat, wide-bodied mascot with two side arm/ear nubs (mid-height, not top
// corners) and four thin legs, matching the reference "Claude Mascot" design
// (Nik Bear Brown, "The Claude Mascot — All 18 Signals"). Hand-authored as a
// character grid; facial expression (eye style) and gait (footOffset) are
// layered on separately at draw time so one grid covers every mood.
enum MascotSprite {
    static let cols = 13
    static let rows = 7
    /// Row index of the arm/ear nubs (the one full-width row between the
    /// narrower torso rows above and below it) -- shared with anything that
    /// needs to visually attach to Clawd's arm, like the held hammer's grip.
    static let armRow = 2

    enum Cell {
        case empty
        case body
        case eye
    }

    enum EyeStyle: Equatable {
        case open
        case closed
        case lookLeft
        case lookRight
    }

    static let bodyColor = Color(red: 0.88, green: 0.42, blue: 0.27)
    static let eyeColor = Color.black

    // '.' empty, 'B' body, 'K' eye (base positions; EyeStyle restyles 'K' at draw time)
    private static let base: [String] = [
        "..BBBBBBBBB..",
        "..BKBBBBBKB..",
        "BBBBBBBBBBBBB",
        "..BBBBBBBBB..",
        "..BBBBBBBBB..",
        "...B.B.B.B...",
        "...B.B.B.B...",
    ]

    /// Column indices of the four legs, left to right.
    private static let legColumns = [3, 5, 7, 9]
    private static let legRows = [5, 6]

    /// footOffset shifts legs in an alternating diagonal gait (odd/even legs
    /// move opposite directions) rather than sliding the whole row sideways,
    /// so a walk cycle reads as an actual stride rather than a shuffle.
    static func grid(footOffset: Int) -> [[Cell]] {
        var g = Array(repeating: Array<Cell>(repeating: .empty, count: cols), count: rows)
        for (y, row) in base.enumerated() where y < rows {
            for (x, char) in row.enumerated() where x < cols {
                switch char {
                case "B": g[y][x] = .body
                case "K": g[y][x] = .eye
                default: break
                }
            }
        }

        guard footOffset != 0 else { return g }
        for row in legRows {
            for x in 0..<cols { g[row][x] = .empty }
        }
        for (index, col) in legColumns.enumerated() {
            let direction = index % 2 == 0 ? 1 : -1
            let shifted = col + footOffset * direction
            guard shifted >= 0, shifted < cols else { continue }
            for row in legRows {
                g[row][shifted] = .body
            }
        }
        return g
    }
}
