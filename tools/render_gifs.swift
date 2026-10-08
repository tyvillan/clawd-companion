import AppKit
import SwiftUI

// Offscreen frame renderer for the README GIFs -- see render_gifs.sh.
// Each scene forces a CompanionState, then renders CompanionView at fixed
// instants (CompanionView.fixedDate) so frames are deterministic.

struct Scene {
    let name: String
    let frames: Int
    let step: Double? // nil = use the view's own tick interval
    let setup: (CompanionState) -> Void
}

let scenes: [Scene] = [
    Scene(name: "hammer", frames: 8, step: nil) { $0.mood = .working },
    Scene(name: "canvas", frames: 8, step: nil) { $0.mood = .creating },
    Scene(name: "agents", frames: 24, step: 0.1) { $0.mood = .delegating; $0.agentCount = 3 },
]

@main
struct Renderer {
    @MainActor
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        let outDir = args[0]
        let wanted = Set(args.dropFirst())
        let pixelSize: CGFloat = 8
        let base = Date(timeIntervalSinceReferenceDate: 1_000_000)

        for scene in scenes where wanted.isEmpty || wanted.contains(scene.name) {
            let state = CompanionState()
            scene.setup(state)
            var view = CompanionView(state: state, pixelSize: pixelSize)
            let step = scene.step ?? view.captureTickInterval
            let dir = "\(outDir)/\(scene.name)"
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            for i in 0..<scene.frames {
                view.fixedDate = base.addingTimeInterval(Double(i) * step)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 4
                renderer.isOpaque = false
                guard let img = renderer.nsImage, let tiff = img.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:])
                else { continue }
                try png.write(to: URL(fileURLWithPath: String(format: "%@/%02d.png", dir, i)))
            }
            print("\(scene.name): \(scene.frames) frames @ \(Int(step * 1000))ms")
        }
    }
}
