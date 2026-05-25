import Foundation

/// The three log streams dnscrypt-proxy can produce. The proxy writes them to separate files specified in `dnscrypt-proxy.toml`:
///   • `.server` - top-level  `log_file = "..."`             (startup, errors, resolver health)
///   • `.query`  - `[query_log]` section, `file = "..."`     (every resolved query, if enabled)
///   • `.nx`     - `[nx_log]`    section, `file = "..."`     (NXDOMAIN / blocked names, if enabled)
enum LogSource: String, CaseIterable, Identifiable {
    case server, query, nx

    var id: String { rawValue }

    var label: String {
        switch self {
        case .server: return "Server"
        case .query:  return "Queries"
        case .nx:     return "NXDOMAIN"
        }
    }

    /// Shown as the first line of an otherwise empty stream when the corresponding section isn't enabled in the live config.
    var notConfiguredMessage: String {
        switch self {
        case .server:
            return "Server log not yet created - it appears as soon as the proxy starts."
        case .query:
            return "Query logging isn't enabled. Add a [query_log] section with " +
                   "`file = '…'` to dnscrypt-proxy.toml and restart the proxy."
        case .nx:
            return "NXDOMAIN logging isn't enabled. Add an [nx_log] section with " +
                   "`file = '…'` to dnscrypt-proxy.toml and restart the proxy."
        }
    }
}

/// File-tail log reader. Watches one of the three dnscrypt-proxy log files
/// (server / query / NXDOMAIN) with DispatchSource.makeFileSystemObjectSource
/// and streams new lines to a callback on the main queue.
///
/// TOML is re-parsed on every call to `logPath(for:)` so that edits the user makes in the Config tab take effect immediately.
/// #important note from testing: don't perform caching here!!!
final class LogService {
    private let brew = BrewService()
    private var source: DispatchSourceFileSystemObject?
    private var fileHandle: FileHandle?
    private var position: UInt64 = 0
    private var buffer = ""
    private var onLine: ((String) -> Void)?
    private var currentSource: LogSource = .server

    /// Kept for back-compat with views that just want a "where are logs coming from?" label. Routes to the server log path.
    var currentLogPath: String { logPath(for: .server) ?? brew.defaultLogPath }
    var currentQueryPath: String { logPath(for: .query) ?? brew.defaultQueryLogPath }
    var currentNXPath: String { logPath(for: .nx) ?? brew.defaultNXLogPath }
    
    /// Returns the on-disk path for `source`, parsed from the user's `dnscrypt-proxy.toml`. The server log falls back to the brew-suggested
    /// default location when `log_file = "..."` isn't set; query and nx + return nil when their tables aren't present in the config.
    func logPath(for source: LogSource) -> String? {
        let configText = (try? String(contentsOfFile: brew.configPath,
                                      encoding: .utf8)) ?? ""
        switch source {
        case .server:
            return topLevelValue(key: "log_file", in: configText) ?? brew.defaultLogPath
        case .query:
            return tableValue(table: "query_log", key: "file", in: configText)
        case .nx:
            return tableValue(table: "nx_log",    key: "file", in: configText)
        }
    }

    /// Starts (or restarts) tailing the chosen log source. Any previous
    /// stream is cleanly torn down first. Callbacks are dispatched to the main queue.
    func start(source: LogSource = .server,
               onLine: @escaping (String) -> Void) {
        stop()
        self.onLine = onLine
        self.currentSource = source

        guard let path = logPath(for: source) else {
            // No file to tail - surface a single explanatory line so the
            // empty Logs view isn't just "nothing happening, am I broken? :(".
            DispatchQueue.main.async { onLine("[" + source.label + "] " + source.notConfiguredMessage) }
            return
        }

        let fm = FileManager.default
        if !fm.fileExists(atPath: path) {
            // Create empty so the FileHandle open succeeds and we have
            // something to watch for the first write. Keep an eye on this as its been flakey depending on env.
            fm.createFile(atPath: path, contents: nil)
        }

        guard let fh = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else {
            DispatchQueue.main.async { onLine("[" + source.label + "] unable to open \(path)") }
            return
        }
        self.fileHandle = fh

        // Seek near the end so to show only fresh lines, plus a bit of tail.
        let size = (try? fh.seekToEnd()) ?? 0
        let tailSize: UInt64 = 16_384
        let startPos = size > tailSize ? size - tailSize : 0
        try? fh.seek(toOffset: startPos)
        self.position = startPos
        readAvailable()

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fh.fileDescriptor,
            eventMask: [.write, .extend, .rename, .delete],
            queue: DispatchQueue.global(qos: .utility)
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let ev = src.data
            if ev.contains(.rename) || ev.contains(.delete) {
                // Log rotated — reattach on the next poll tick.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.start(source: self.currentSource,
                               onLine: self.onLine ?? { _ in })
                }
                return
            }
            self.readAvailable()
        }
        src.resume()
        self.source = src
    }

    func stop() {
        source?.cancel()
        source = nil
        try? fileHandle?.close()
        fileHandle = nil
        buffer = ""
    }

    private func readAvailable() {
        guard let fh = fileHandle else { return }
        let data = fh.availableData
        guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
        buffer += chunk
        while let nl = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<nl])
            buffer.removeSubrange(...nl)
            DispatchQueue.main.async { [weak self] in
                self?.onLine?(line)
            }
        }
    }

    // MARK: - TOML helpers
    //
    // A small regex-based extractor is perfectly adequate for now and avoids pulling in a full TOML parser.

    /// Finds a top-level `key = "value"` line (before any `[section]`).
    private func topLevelValue(key: String, in text: String) -> String? {
        let prologue: String
        if let firstSec = text.range(of: #"(?m)^\s*\["#, options: .regularExpression) {
            prologue = String(text[..<firstSec.lowerBound])
        } else {
            prologue = text
        }
        return firstQuotedMatch(key: key, in: prologue)
    }

    /// Finds `key = "value"` inside the body of `[table]` (between the
    /// `[table]` header and the next `[section]` header / end of file).
    private func tableValue(table: String, key: String, in text: String) -> String? {
        let headerPattern = #"(?m)^[ \t]*\["# + NSRegularExpression.escapedPattern(for: table) + #"\][ \t]*$"#
        guard let secRange = text.range(of: headerPattern, options: .regularExpression) else {
            return nil
        }
        let afterHeader = text[secRange.upperBound...]
        let body: Substring
        if let next = afterHeader.range(of: #"(?m)^[ \t]*\["#, options: .regularExpression) {
            body = afterHeader[..<next.lowerBound]
        } else {
            body = afterHeader
        }
        return firstQuotedMatch(key: key, in: String(body))
    }

    /// Looks for `^\s*key\s*=\s*'value'` or `^\s*key\s*=\s*"value"` and
    /// returns `value`. Comment lines (starting with `#`) are skipped by the leading-whitespace anchor.
    private func firstQuotedMatch(key: String, in text: String) -> String? {
        let escKey = NSRegularExpression.escapedPattern(for: key)
        let pattern = #"(?m)^[ \t]*"# + escKey + #"[ \t]*=[ \t]*(['"])([^'"]+)\1"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 3 else {
            return nil
        }
        return ns.substring(with: m.range(at: 2))
    }
}
