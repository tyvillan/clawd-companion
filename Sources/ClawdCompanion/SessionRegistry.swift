import Foundation

/// Watches the sessions directory and reports which Claude Code sessions
/// are currently live. Each session owns one `<session_id>.json` file
/// written by the hook; the file's existence *is* the session's lifetime,
/// and its contents are that session's mood/target/planning state.
///
/// This only reports the set of session IDs. Per-session content changes
/// are watched separately by each companion's own StateFileWatcher --
/// a directory-level kqueue fires on files being created or deleted, not on
/// writes *inside* an existing file, so one watcher can't cover both.
final class SessionRegistry {
    private let directory: String
    private var source: DispatchSourceFileSystemObject?
    private var safetyTimer: Timer?
    private var known: Set<String> = []

    /// Called on the main queue whenever the live set changes, with the ids
    /// that appeared and the ids that went away.
    var onChange: ((_ added: [String], _ removed: [String]) -> Void)?

    init(directory: String) {
        self.directory = directory
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    }

    func start() {
        startWatching()
        rescan()

        // Backstop for the kqueue above. Directory vnode events are
        // genuinely lossy -- several sessions ending at once was observed
        // landing as a single event that the handler could miss entirely,
        // leaving despawned companions on screen indefinitely. rescan() is
        // one directory listing and a set compare, and it early-outs when
        // nothing changed, so polling it cheaply guarantees convergence
        // instead of depending on every event arriving.
        let timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.rescan()
        }
        RunLoop.main.add(timer, forMode: .common)
        safetyTimer = timer
    }

    deinit {
        safetyTimer?.invalidate()
        source?.cancel()
    }

    static func statePath(directory: String, sessionID: String) -> String {
        (directory as NSString).appendingPathComponent("\(sessionID).json")
    }

    private func startWatching() {
        let fd = open(directory, O_EVTONLY)
        guard fd >= 0 else { return }
        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: DispatchQueue.main
        )
        newSource.setEventHandler { [weak self] in
            self?.rescan()
        }
        newSource.setCancelHandler { close(fd) }
        newSource.resume()
        source = newSource
    }

    private func rescan() {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        // Only .json files count. Older builds of the hook wrote
        // extension-less marker files here purely for refcounting; ignoring
        // anything without the extension keeps a leftover marker from
        // spawning a companion with no state to read.
        let live = Set(
            entries
                .filter { ($0 as NSString).pathExtension == "json" }
                .map { ($0 as NSString).deletingPathExtension }
        )
        guard live != known else { return }
        let added = live.subtracting(known)
        let removed = known.subtracting(live)
        known = live
        // Sorted so slot assignment is deterministic when several sessions
        // appear in the same rescan (e.g. at app launch).
        onChange?(added.sorted(), removed.sorted())
    }
}
