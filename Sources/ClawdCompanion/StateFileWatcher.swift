import Foundation

// Watches a single small JSON state file for changes and updates
// CompanionState accordingly. Event-driven via kqueue (DispatchSource), not
// polling, so idle CPU cost is effectively zero between writes.
final class StateFileWatcher {
    private let path: String
    private let state: CompanionState
    private let onQuit: () -> Void
    private var source: DispatchSourceFileSystemObject?

    init(path: String, state: CompanionState, onQuit: @escaping () -> Void) {
        self.path = path
        self.state = state
        self.onQuit = onQuit

        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: Data("{\"state\":\"idle\",\"target\":\"\"}".utf8))
        }

        startWatching()
        readCurrentState()
    }

    private func startWatching() {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend],
            queue: DispatchQueue.main
        )
        newSource.setEventHandler { [weak self, weak newSource] in
            self?.readCurrentState()
            // Atomic writes (write-to-temp + rename) replace the inode we're
            // watching, so only reopen when the file was actually
            // renamed/deleted out from under us -- not on every plain write.
            if let flags = newSource?.data, flags.contains(.delete) || flags.contains(.rename) {
                self?.rewatch()
            }
        }
        // Capture this source's own fd by value so a stale reference from a
        // later rewatch() can never close the wrong descriptor.
        newSource.setCancelHandler {
            close(fd)
        }
        newSource.resume()
        source = newSource
    }

    private func rewatch() {
        source?.cancel()
        startWatching()
    }

    private func readCurrentState() {
        guard let data = FileManager.default.contents(atPath: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = obj["state"] as? String,
              let mood = CompanionMood(rawValue: raw)
        else { return }

        let rawTarget = obj["target"] as? String
        let target = rawTarget.flatMap { TargetApp(rawValue: $0) }
        let planning = obj["planning"] as? Bool ?? false

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if mood == .quit {
                self.onQuit()
            } else {
                self.state.mood = mood
                self.state.targetApp = target
                self.state.isPlanning = planning
            }
        }
    }
}
