import SwiftUI

// Flat, minimal mascot: a rounded body, two square eyes, two ear nubs, two
// foot nubs. Hand-authored as a character grid (classic pixel-art sprite
// authoring) rather than procedural shape math, since this silhouette is
// blocky/rectangular rather than organic like the old crab was.
//
// Expressive variety (walking wobble, pulse, lean, bounce) is layered on at
// draw time in CompanionView as transforms, rather than baked into many
// separate grid variants -- this grid only needs one parameter: which foot
// is forward.
enum MascotSprite {
    static let cols = 12
    static let rows = 12

    private static let bodyColor = Color(red: 0.88, green: 0.42, blue: 0.27)
    private static let eyeColor = Color.black

    // '.' transparent, 'B' body/ear/foot fill, 'K' eye
    private static let base: [String] = [
        "..BB....BB..",
        ".BBBBBBBBBB.",
        "BBBBBBBBBBBB",
        "BBBBBBBBBBBB",
        "BBBKKBBKKBBB",
        "BBBKKBBKKBBB",
        "BBBBBBBBBBBB",
        "BBBBBBBBBBBB",
        "BBBBBBBBBBBB",
        "BBBBBBBBBBBB",
        ".BBBBBBBBBB.",
        "..BB....BB..",
    ]

    /// footOffset shifts the two foot columns left/right by up to 1 to give
    /// a walking/vibrating wobble; 0 is the neutral standing pose.
    static func grid(footOffset: Int) -> [[Color?]] {
        var g = Array(repeating: Array<Color?>(repeating: nil, count: cols), count: rows)

        for (y, row) in base.enumerated() where y < rows {
            for (x, char) in row.enumerated() where x < cols {
                switch char {
                case "B": g[y][x] = bodyColor
                case "K": g[y][x] = eyeColor
                default: break
                }
            }
        }

        // Redraw just the foot row with a horizontal offset applied.
        guard footOffset != 0 else { return g }
        let footRow = rows - 1
        for x in 0..<cols { g[footRow][x] = nil }
        let footRowTemplate = base[footRow]
        for (x, char) in footRowTemplate.enumerated() where char == "B" {
            let shifted = x + footOffset
            guard shifted >= 0, shifted < cols else { continue }
            g[footRow][shifted] = bodyColor
        }
        return g
    }
}
