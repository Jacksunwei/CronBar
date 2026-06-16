import Foundation
import AppKit

/// Scans the user's LaunchAgents directory and merges it with `launchctl list`
/// and `print-disabled` output to build a unified view of agent status
/// (disabled agents are hidden). Exposes load/unload and start/kill actions
/// backed by `launchctl`.
@MainActor
final class LaunchAgentManager: ObservableObject {
    @Published private(set) var agents: [LaunchAgent] = []
    @Published private(set) var isRefreshing = false
    @Published var lastError: String?

    /// ~/Library/LaunchAgents
    private let agentsDirectory: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }()

    private var uid: uid_t { getuid() }
    private var guiDomain: String { "gui/\(uid)" }

    /// Tracks the launchd `runs` counter per label across refreshes so we can
    /// detect when an interval job actually fired and anchor next-run estimates
    /// on that observed time.
    private var runObservations: [String: (runs: Int, lastRunAt: Date?)] = [:]

    // MARK: - Refresh

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            let raws = await Self.loadAgents(directory: agentsDirectory)
            self.agents = self.buildAgents(from: raws)
            self.lastError = nil
            self.isRefreshing = false
        }
    }

    /// Raw, time-independent data gathered off the main actor.
    private struct RawAgent {
        let label: String
        let plistPath: String
        let pid: Int?
        let lastExitStatus: Int?
        let isLoaded: Bool
        let triggers: [TriggerKind]
        let interval: Int?
        let calendarEntries: [[String: Int]]
        let runsCount: Int?
        let logMtime: Date?
    }

    /// Combines raw data with the per-label run history to compute next-run
    /// times and sort by soonest upcoming run. Runs on the main actor because it
    /// reads/writes `runObservations`.
    private func buildAgents(from raws: [RawAgent]) -> [LaunchAgent] {
        let now = Date()
        var result: [LaunchAgent] = []

        for raw in raws {
            // Update run history: if the runs counter advanced, the job fired.
            if let runs = raw.runsCount {
                let prev = runObservations[raw.label]
                var lastRunAt = prev?.lastRunAt
                if let prev, runs > prev.runs {
                    lastRunAt = now
                }
                runObservations[raw.label] = (runs, lastRunAt)
            }

            let nextRun = Self.computeNextRun(
                interval: raw.interval,
                calendarEntries: raw.calendarEntries,
                observedLastRun: runObservations[raw.label]?.lastRunAt,
                logMtime: raw.logMtime,
                now: now
            )

            result.append(LaunchAgent(
                label: raw.label,
                plistPath: raw.plistPath,
                pid: raw.pid,
                lastExitStatus: raw.lastExitStatus,
                isLoaded: raw.isLoaded,
                isEnabled: true,
                triggers: raw.triggers,
                nextRun: nextRun
            ))
        }

        // Sort by soonest next run; agents with no next run go last (by label).
        result.sort { a, b in
            switch (a.nextRun, b.nextRun) {
            case let (x?, y?): return x.date < y.date
            case (_?, nil):    return true
            case (nil, _?):    return false
            case (nil, nil):
                return a.label.localizedCaseInsensitiveCompare(b.label) == .orderedAscending
            }
        }
        return result
    }

    /// Computes the next launch time. Exact for StartCalendarInterval; for
    /// StartInterval, projects forward from the most reliable anchor available
    /// (an observed run, else the log file's mtime) and marks it approximate.
    private nonisolated static func computeNextRun(
        interval: Int?,
        calendarEntries: [[String: Int]],
        observedLastRun: Date?,
        logMtime: Date?,
        now: Date
    ) -> NextRun? {
        // Exact: calendar schedule.
        if !calendarEntries.isEmpty {
            var soonest: Date?
            for entry in calendarEntries {
                if let d = nextCalendarDate(entry: entry, after: now) {
                    if soonest == nil || d < soonest! { soonest = d }
                }
            }
            if let d = soonest { return NextRun(date: d, approximate: false) }
        }

        // Approximate: periodic interval, projected from a known run.
        if let interval, interval > 0, let anchor = observedLastRun ?? logMtime {
            var next = anchor.addingTimeInterval(Double(interval))
            if next <= now {
                let missed = (now.timeIntervalSince(next) / Double(interval)).rounded(.down) + 1
                next = next.addingTimeInterval(missed * Double(interval))
            }
            return NextRun(date: next, approximate: true)
        }

        return nil
    }

    private nonisolated static func nextCalendarDate(entry: [String: Int], after date: Date) -> Date? {
        var comps = DateComponents()
        if let m = entry["Minute"]  { comps.minute = m }
        if let h = entry["Hour"]    { comps.hour = h }
        if let d = entry["Day"]     { comps.day = d }
        if let mo = entry["Month"]  { comps.month = mo }
        if let wd = entry["Weekday"] {
            // launchd: 0 or 7 = Sunday, 1 = Monday … Apple: 1 = Sunday … 7 = Saturday.
            comps.weekday = (wd % 7) + 1
        }
        guard comps.minute != nil || comps.hour != nil || comps.day != nil
                || comps.month != nil || comps.weekday != nil else { return nil }
        return Calendar.current.nextDate(after: date, matching: comps, matchingPolicy: .nextTime)
    }

    private nonisolated static func loadAgents(directory: URL) async -> [RawAgent] {
        let uid = getuid()
        let fm = FileManager.default

        // 1. Runtime info from `launchctl list` -> [label: (pid, status)].
        let runtime = parseLaunchctlList(Self.runProcess(
            launchPath: "/bin/launchctl",
            arguments: ["list"]
        ).stdout)

        // 2. Disabled set from `launchctl print-disabled gui/<uid>`.
        let disabled = parsePrintDisabled(Self.runProcess(
            launchPath: "/bin/launchctl",
            arguments: ["print-disabled", "gui/\(uid)"]
        ).stdout)

        // 3. Discover plists and build raw entries (skipping disabled ones).
        var raws: [RawAgent] = []
        guard let entries = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for url in entries where url.pathExtension == "plist" {
            let parsed = parsePlist(at: url)
            let label = parsed.label ?? url.deletingPathExtension().lastPathComponent
            if disabled.contains(label) { continue }

            let info = runtime[label]
            let isLoaded = info != nil

            // Most recent log mtime (fallback anchor for interval jobs).
            var logMtime: Date?
            for p in parsed.logPaths {
                if let attrs = try? fm.attributesOfItem(atPath: p),
                   let m = attrs[.modificationDate] as? Date {
                    if logMtime == nil || m > logMtime! { logMtime = m }
                }
            }

            // `runs` counter (only needed for loaded interval jobs).
            var runsCount: Int?
            if isLoaded, parsed.interval != nil {
                let out = Self.runProcess(
                    launchPath: "/bin/launchctl",
                    arguments: ["print", "gui/\(uid)/\(label)"]
                ).stdout
                runsCount = parseRunsCount(out)
            }

            raws.append(RawAgent(
                label: label,
                plistPath: url.path,
                pid: info?.pid,
                lastExitStatus: info?.status,
                isLoaded: isLoaded,
                triggers: parsed.triggers,
                interval: parsed.interval,
                calendarEntries: parsed.calendarEntries,
                runsCount: runsCount,
                logMtime: logMtime
            ))
        }

        return raws
    }

    // MARK: - Plist parsing

    private struct ParsedPlist {
        var label: String?
        var triggers: [TriggerKind] = []
        var interval: Int?
        var calendarEntries: [[String: Int]] = []
        var logPaths: [String] = []
    }

    private nonisolated static func parsePlist(at url: URL) -> ParsedPlist {
        guard let data = try? Data(contentsOf: url),
              let obj = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
              ) as? [String: Any]
        else { return ParsedPlist() }

        var parsed = ParsedPlist()
        parsed.label = obj["Label"] as? String

        var triggers: [TriggerKind] = []

        if let interval = obj["StartInterval"] as? Int {
            parsed.interval = interval
            triggers.append(.interval(interval))
        }
        if let cal = obj["StartCalendarInterval"] {
            parsed.calendarEntries = normalizeCalendar(cal)
            triggers.append(.calendar)
        }
        // KeepAlive counts when true or specified as a dictionary of conditions.
        if let ka = obj["KeepAlive"] {
            if (ka as? Bool) == true || ka is [String: Any] {
                triggers.append(.keepAlive)
            }
        }
        if obj["WatchPaths"] != nil {
            triggers.append(.watchPaths)
        }
        if obj["QueueDirectories"] != nil {
            triggers.append(.queueDirectories)
        }
        if obj["Sockets"] != nil {
            triggers.append(.sockets)
        }
        if obj["MachServices"] != nil {
            triggers.append(.machServices)
        }
        if (obj["StartOnMount"] as? Bool) == true {
            triggers.append(.onMount)
        }
        if (obj["RunAtLoad"] as? Bool) == true {
            triggers.append(.runAtLoad)
        }

        triggers.sort { $0.order < $1.order }
        parsed.triggers = triggers

        for key in ["StandardOutPath", "StandardErrorPath"] {
            if let p = obj[key] as? String { parsed.logPaths.append(p) }
        }

        return parsed
    }

    /// StartCalendarInterval may be a single dict or an array of dicts.
    private nonisolated static func normalizeCalendar(_ value: Any) -> [[String: Int]] {
        func ints(_ dict: [String: Any]) -> [String: Int] {
            var out: [String: Int] = [:]
            for (k, v) in dict {
                if let i = v as? Int { out[k] = i }
            }
            return out
        }
        if let dict = value as? [String: Any] {
            return [ints(dict)]
        }
        if let arr = value as? [[String: Any]] {
            return arr.map(ints)
        }
        return []
    }

    /// Extracts the `runs = N` value from `launchctl print` output.
    private nonisolated static func parseRunsCount(_ output: String) -> Int? {
        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("runs = ") {
                return Int(line.dropFirst("runs = ".count).trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }

    /// Parses the tab-separated output of `launchctl list`.
    /// Format:
    ///   PID\tStatus\tLabel
    ///   1234\t0\tcom.example.foo
    ///   -\t0\tcom.example.bar
    private nonisolated static func parseLaunchctlList(_ output: String) -> [String: (pid: Int?, status: Int?)] {
        var result: [String: (pid: Int?, status: Int?)] = [:]
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
        for (index, line) in lines.enumerated() {
            if index == 0 { continue } // header
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard cols.count >= 3 else { continue }
            let pid = Int(cols[0])
            let status = Int(cols[1])
            let label = String(cols[2])
            result[label] = (pid, status)
        }
        return result
    }

    /// Parses `launchctl print-disabled gui/<uid>` and returns the set of
    /// labels marked disabled.
    /// Format:
    ///   disabled services = {
    ///       "com.example.foo" => enabled
    ///       "com.example.bar" => disabled
    ///   }
    private nonisolated static func parsePrintDisabled(_ output: String) -> Set<String> {
        var disabled: Set<String> = []
        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.contains("=>"),
                  let firstQuote = line.firstIndex(of: "\""),
                  let secondQuote = line[line.index(after: firstQuote)...].firstIndex(of: "\"")
            else { continue }
            let label = String(line[line.index(after: firstQuote)..<secondQuote])
            let value = line[secondQuote...].lowercased()
            // Treat "=> disabled" (modern) or "=> true" (legacy) as disabled.
            if value.contains("disabled") || value.contains("true") {
                disabled.insert(label)
            }
        }
        return disabled
    }

    // MARK: - Actions

    /// Load (bootstrap) the agent from its plist so launchd tracks it.
    func load(_ agent: LaunchAgent) {
        guard let path = agent.plistPath else {
            lastError = "No plist path for \(agent.label)"
            return
        }
        runActions([["bootstrap", guiDomain, path]], label: agent.label)
    }

    /// Unload (bootout) the agent so launchd stops tracking it.
    func unload(_ agent: LaunchAgent) {
        let target = "\(guiDomain)/\(agent.label)"
        if agent.isLoaded {
            runActions([["bootout", target]], label: agent.label)
        } else if let path = agent.plistPath {
            runActions([["bootout", guiDomain, path]], label: agent.label)
        }
    }

    /// Toggle the running process: start it if stopped, kill it if running.
    func toggleRun(_ agent: LaunchAgent) {
        let target = "\(guiDomain)/\(agent.label)"
        if agent.isRunning {
            runActions([["kill", "TERM", target]], label: agent.label)
        } else {
            // Bootstrap first if it isn't loaded, then kickstart.
            var args: [[String]] = []
            if !agent.isLoaded, let path = agent.plistPath {
                args.append(["bootstrap", guiDomain, path])
            }
            args.append(["kickstart", "-k", target])
            runActions(args, label: agent.label)
        }
    }

    /// Runs a sequence of launchctl invocations, stopping on the first failure.
    private func runActions(_ argumentSets: [[String]], label: String) {
        Task {
            var failure: String?
            for arguments in argumentSets {
                let res = await Task.detached {
                    Self.runProcess(launchPath: "/bin/launchctl", arguments: arguments)
                }.value
                if res.exitCode != 0 {
                    let msg = res.stderr.isEmpty ? res.stdout : res.stderr
                    failure = "\(label): launchctl \(arguments.joined(separator: " ")) failed (\(res.exitCode)) \(msg.trimmingCharacters(in: .whitespacesAndNewlines))"
                    break
                }
            }
            self.lastError = failure
            // Give launchd a moment, then refresh.
            try? await Task.sleep(nanoseconds: 300_000_000)
            self.refresh()
        }
    }

    // MARK: - Process helper

    struct ProcessResult {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }

    nonisolated static func runProcess(launchPath: String, arguments: [String]) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return ProcessResult(stdout: "", stderr: error.localizedDescription, exitCode: -1)
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return ProcessResult(
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
    }

    // MARK: - Reveal in Finder

    func revealInFinder(_ agent: LaunchAgent) {
        guard let path = agent.plistPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// Open the agent's plist in the default editor for that file type.
    func editConfig(_ agent: LaunchAgent) {
        guard let path = agent.plistPath else {
            lastError = "No plist path for \(agent.label)"
            return
        }
        let url = URL(fileURLWithPath: path)
        if !NSWorkspace.shared.open(url) {
            lastError = "Could not open \(path)"
        }
    }
}
