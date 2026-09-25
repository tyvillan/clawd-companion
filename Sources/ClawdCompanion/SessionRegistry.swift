import Darwin
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

    /// How long a session file with no readable "pid" is still given the
    /// benefit of the doubt before being pruned -- see partitionByLiveness.
    private static let missingPIDGracePeriod: TimeInterval = 30

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
        let onDisk = Set(
            entries
                .filter { ($0 as NSString).pathExtension == "json" }
                .map { ($0 as NSString).deletingPathExtension }
        )
        let (alive, orphaned) = Self.partitionByLiveness(onDisk, directory: directory)
        for id in orphaned {
            // Mirrors what the hook's own SessionEnd cleanup does -- without
            // this the same dead file would just get rediscovered as
            // "alive" (no pid to check) forever, since nothing else is ever
            // going to remove it once its owning process is gone.
            try? FileManager.default.removeItem(atPath: Self.statePath(directory: directory, sessionID: id))
        }
        guard alive != known else { return }
        let added = alive.subtracting(known)
        let removed = known.subtracting(alive)
        known = alive
        // Sorted so slot assignment is deterministic when several sessions
        // appear in the same rescan (e.g. at app launch).
        onChange?(added.sorted(), removed.sorted())
    }

    /// Splits session ids into ones whose recorded owning process (the
    /// hook's "pid" field -- the actual long-lived `claude` CLI process for
    /// that session, confirmed via its own process ancestry, not some
    /// intermediate shell) is still running vs. confirmed dead. A crash,
    /// force-quit, or `kill -9` never fires SessionEnd, so the marker file
    /// -- and its phantom companion -- would otherwise sit there
    /// indefinitely; the file's mere existence was the *only* signal this
    /// used to trust.
    ///
    /// A file with no readable "pid" (an older hook version, or a read
    /// racing the hook's own write-then-rename) is left in `alive` for the
    /// first `missingPIDGracePeriod` seconds after its own last write, so a
    /// transient read hiccup can't despawn someone's actual live companion.
    /// Past that grace period it's treated as orphaned instead of trusted
    /// forever -- the write-then-rename race this tolerates resolves within
    /// milliseconds, so a file still unreadable/pid-less well after that is
    /// a genuinely stale marker (observed: a pre-pid-field hook version's
    /// leftover file, still "alive" four days later with nothing able to
    /// prune it) rather than one caught mid-write.
    ///
    /// `kill(pid, 0)` succeeding is *not* by itself proof the original
    /// session is still alive -- macOS recycles pid numbers, so a marker
    /// file surviving long enough (observed: four days) can have its
    /// recorded pid reassigned to a completely unrelated later process,
    /// which makes the liveness probe come back "alive" forever and leaves
    /// a duplicate/phantom companion on screen indefinitely (the bug this
    /// guards against). So a pid that answers to signal 0 gets one more
    /// check: `processName(pid:)` reads that pid's actual `comm` name via
    /// `sysctl(KERN_PROC_PID)` and confirms it still looks like a `claude`
    /// process. A pid that exists but is now some other program is exactly
    /// the recycled-pid case, so it's treated the same as a confirmed-dead
    /// pid rather than trusted.
    private static func partitionByLiveness(
        _ ids: Set<String>, directory: String
    ) -> (alive: Set<String>, orphaned: Set<String>) {
        var alive = Set<String>()
        var orphaned = Set<String>()
        for id in ids {
            let path = statePath(directory: directory, sessionID: id)
            guard let data = FileManager.default.contents(atPath: path),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pid = obj["pid"] as? Int, pid > 0
            else {
                let attrs = try? FileManager.default.attributesOfItem(atPath: path)
                let mtime = attrs?[.modificationDate] as? Date
                let age = mtime.map { Date().timeIntervalSince($0) } ?? 0
                if age > missingPIDGracePeriod {
                    orphaned.insert(id)
                } else {
                    alive.insert(id)
                }
                continue
            }
            let signalOK = kill(pid_t(pid), 0) == 0 || errno != ESRCH
            if signalOK, let name = processName(pid: pid_t(pid)), !name.lowercased().contains("claude") {
                orphaned.insert(id)
            } else if signalOK {
                alive.insert(id)
            } else {
                orphaned.insert(id)
            }
        }
        return (alive, orphaned)
    }

    /// Looks up a running process's short name (`kinfo_proc.kp_proc.p_comm`,
    /// the same "comm" name `ps -o comm=` reports) via `sysctl(3)`, without
    /// spawning `ps` per session on every 2s rescan. Returns `nil` if the
    /// pid doesn't resolve to a live process (already covered by the
    /// `kill(pid, 0)` check above, but sysctl can independently come back
    /// empty right as a process exits) or the sysctl call itself fails --
    /// callers treat `nil` the same as "couldn't confirm," not as "confirmed
    /// not claude," so a transient lookup hiccup can't despawn a real
    /// session either.
    private static func processName(pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        let result = withUnsafeMutablePointer(to: &info) { ptr -> Int32 in
            sysctl(&mib, u_int(mib.count), ptr, &size, nil, 0)
        }
        guard result == 0, size > 0 else { return nil }
        let comm = withUnsafeBytes(of: info.kp_proc.p_comm) { raw -> String in
            let bytes = raw.bindMemory(to: UInt8.self)
            let nulIndex = bytes.firstIndex(of: 0) ?? bytes.count
            return String(decoding: bytes[..<nulIndex], as: UTF8.self)
        }
        return comm.isEmpty ? nil : comm
    }
}
