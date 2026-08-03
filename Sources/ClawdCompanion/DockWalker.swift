import AppKit
import ApplicationServices
import Combine

// Figures out where the Dock is and where its icons are, and drives the
// companion window walking between them. Degrades gracefully through three
// tiers rather than hard-failing: precise per-icon stops (needs
// Accessibility permission) -> evenly-spaced stops along the Dock's measured
// width (no extra permission) -> a fixed band near the screen bottom if the
// Dock's own geometry can't be read at all.
//
// Two independent things can make it move: idle wandering (random stop,
// only while displayState == .walking) and activity-driven targeting (a
// specific named icon, whenever CompanionState.targetApp names one and it's
// currently in the Dock) -- the latter pre-empts and suppresses the former.
final class DockWalker {
    private let state: CompanionState
    var onPositionChange: ((CGPoint) -> Void)?
    var onFootToggle: (() -> Void)?

    private(set) var position: CGPoint = .zero
    /// Average measured Dock icon size (points), used by the app to size
    /// itself relative to the real Dock instead of a hardcoded constant.
    private(set) var measuredTileSize: CGFloat = 64

    private var stops: [CGFloat] = []
    private var iconsByTitle: [String: IconGeometry] = [:]
    private var topY: CGFloat = 0
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    /// Nudges the window's bottom edge down into the Dock icon's own top
    /// padding -- the AX-reported icon frame extends above where the icon
    /// glyph visually starts, which otherwise reads as a floating gap.
    /// Calibrated visually against the real Dock, not derived from math.
    private static let verticalSeatOffset: CGFloat = 6

    init(state: CompanionState) {
        self.state = state
        state.$targetApp
            .removeDuplicates()
            .sink { [weak self] target in
                self?.handleTargetChange(target)
            }
            .store(in: &cancellables)
    }

    func requestAccessibilityIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Reads the Dock's real geometry (icon positions, measured tile size)
    /// without starting the wander timer -- call before sizing the window,
    /// since the companion's own size is derived from `measuredTileSize`.
    func primeGeometry() {
        refreshStops()
    }

    func start() {
        refreshStops()
        position = CGPoint(x: stops.first ?? 200, y: topY)
        onPositionChange?(position)
        scheduleNextMove()
    }

    private func refreshStops() {
        // Tier 1: precise, from the Dock's own icon geometry via Accessibility.
        // Note this deliberately does NOT use CGWindowListCopyWindowInfo's
        // bounds for the Dock -- on this OS that API reports the Dock's
        // window as covering the *entire screen* (a compositor/Stage
        // Manager artifact), not the visible icon bar, so it's useless for
        // positioning and would put the sprite at the top of the screen.
        if AXIsProcessTrusted(), let icons = Self.dockIconGeometry(), !icons.isEmpty {
            // AXPositionAttribute is in Quartz's global display space, whose
            // origin is always the *primary* display's top-left -- not
            // whichever screen currently has keyboard focus (NSScreen.main).
            // Using the wrong height here silently mis-places the window
            // whenever focus is on a secondary display.
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 900
            let quartzTop = icons.map(\.quartzY).min() ?? 0
            topY = primaryHeight - quartzTop - Self.verticalSeatOffset
            stops = icons.map(\.centerX)
            measuredTileSize = icons.map(\.size).reduce(0, +) / CGFloat(icons.count)
            iconsByTitle = [:]
            for icon in icons where icon.title != nil {
                iconsByTitle[icon.title!] = icon
            }
            return
        }

        // Tier 2: no Accessibility -- estimate from the Dock's own size
        // preference rather than the unreliable window bounds.
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let tileSize = Self.dockTileSize() ?? 64
        measuredTileSize = tileSize
        iconsByTitle = [:]
        topY = screen.minY + tileSize * 1.15 - Self.verticalSeatOffset
        let span = min(screen.width * 0.6, 900)
        stops = Array(stride(from: screen.midX - span / 2, to: screen.midX + span / 2, by: tileSize))
        if stops.isEmpty {
            // Tier 3: even preferences unavailable -- fixed band near the bottom.
            topY = screen.minY + 70
            stops = Array(stride(from: screen.minX + 40, to: screen.maxX - 40, by: 80))
        }
    }

    private func scheduleNextMove() {
        timer?.invalidate()
        let pause = Double.random(in: 4...8)
        timer = Timer.scheduledTimer(withTimeInterval: pause, repeats: false) { [weak self] _ in
            self?.attemptMove()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func attemptMove() {
        // A named target always takes priority; idle wandering only runs
        // once nothing in particular is going on.
        guard state.targetApp == nil, state.displayState == .walking, !stops.isEmpty else {
            scheduleNextMove()
            return
        }
        let target = stops.randomElement() ?? position.x
        animate(to: target, targetDirected: false)
    }

    /// Called whenever CompanionState.targetApp changes (not on every mood
    /// update -- Combine's removeDuplicates means repeated same-target tool
    /// calls, e.g. several Reads in a row, don't re-trigger a walk).
    private func handleTargetChange(_ target: TargetApp?) {
        guard let target, let stopX = resolveStop(for: target) else {
            state.isTargetWalking = false
            return
        }
        state.isTargetWalking = true
        animate(to: stopX, targetDirected: true)
    }

    private func resolveStop(for target: TargetApp) -> CGFloat? {
        switch target {
        case .finder:
            return iconsByTitle["Finder"]?.centerX
        case .terminal:
            return iconsByTitle["Terminal"]?.centerX
        case .browser:
            let runningBrowserNames = Set(
                NSWorkspace.shared.runningApplications.compactMap(\.localizedName)
            )
            let preferred = ["Google Chrome", "Safari"].first { runningBrowserNames.contains($0) } ?? "Google Chrome"
            return iconsByTitle[preferred]?.centerX
                ?? iconsByTitle["Google Chrome"]?.centerX
                ?? iconsByTitle["Safari"]?.centerX
        }
    }

    private func animate(to targetX: CGFloat, targetDirected: Bool) {
        let startX = position.x
        let distance = targetX - startX
        guard abs(distance) > 1 else {
            if targetDirected { state.isTargetWalking = false }
            scheduleNextMove()
            return
        }
        let duration = min(2.5, max(0.6, abs(distance) / 90.0))
        let startTime = Date()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] tick in
            guard let self else { tick.invalidate(); return }
            // Idle-wander steps abort if walking stops being appropriate
            // (e.g. focus/mood changed mid-stride); target-directed steps
            // only abort if the target itself was cleared, since they're
            // meant to play out alongside whatever mood animation is active.
            let stillValid = targetDirected ? (self.state.targetApp != nil) : (self.state.displayState == .walking)
            guard stillValid else {
                tick.invalidate()
                if targetDirected { self.state.isTargetWalking = false }
                self.scheduleNextMove()
                return
            }
            let elapsed = Date().timeIntervalSince(startTime)
            let t = min(1.0, elapsed / duration)
            let eased = t * (2 - t)
            self.position = CGPoint(x: startX + distance * eased, y: self.topY)
            self.onPositionChange?(self.position)
            self.onFootToggle?()
            if t >= 1.0 {
                tick.invalidate()
                if targetDirected { self.state.isTargetWalking = false }
                self.scheduleNextMove()
            }
        }
    }

    // MARK: - Dock introspection

    private struct IconGeometry {
        let centerX: CGFloat
        /// Top edge in Quartz (top-left-origin, Y-down) coordinates -- the
        /// same space AXPositionAttribute reports in.
        let quartzY: CGFloat
        /// Roughly-square tile size (points), averaged from width/height.
        let size: CGFloat
        /// The icon's AXTitle (app display name), used to match a specific
        /// app for activity-driven targeting. Some Dock items (spacers,
        /// the Trash) may not expose one.
        let title: String?
    }

    private static func dockIconGeometry() -> [IconGeometry]? {
        guard let dockApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.dock" })
        else { return nil }

        let axApp = AXUIElementCreateApplication(dockApp.processIdentifier)
        var listRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXChildrenAttribute as CFString, &listRef) == .success,
              let topChildren = listRef as? [AXUIElement],
              let iconList = topChildren.first
        else { return nil }

        var iconsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(iconList, kAXChildrenAttribute as CFString, &iconsRef) == .success,
              let icons = iconsRef as? [AXUIElement]
        else { return nil }

        var geometry: [IconGeometry] = []
        for icon in icons {
            var posRef: CFTypeRef?
            var sizeRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(icon, kAXPositionAttribute as CFString, &posRef) == .success,
                  AXUIElementCopyAttributeValue(icon, kAXSizeAttribute as CFString, &sizeRef) == .success,
                  let posValue = posRef, let sizeValue = sizeRef,
                  CFGetTypeID(posValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID()
            else { continue }

            var point = CGPoint.zero
            var size = CGSize.zero
            // swiftlint:disable:next force_cast
            AXValueGetValue(posValue as! AXValue, .cgPoint, &point)
            // swiftlint:disable:next force_cast
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)

            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(icon, kAXTitleAttribute as CFString, &titleRef)
            let title = titleRef as? String

            geometry.append(IconGeometry(
                centerX: point.x + size.width / 2,
                quartzY: point.y,
                size: (size.width + size.height) / 2,
                title: title
            ))
        }
        return geometry
    }

    private static func dockTileSize() -> CGFloat? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["read", "com.apple.dock", "tilesize"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let value = Double(text)
        else { return nil }
        return CGFloat(value)
    }
}
