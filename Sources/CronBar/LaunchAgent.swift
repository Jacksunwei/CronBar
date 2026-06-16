import Foundation

/// A launchd trigger mechanism declared in a plist. An agent may have several
/// (e.g. RunAtLoad + StartInterval).
enum TriggerKind: Hashable {
    case interval(Int)      // StartInterval (seconds)
    case calendar           // StartCalendarInterval
    case runAtLoad          // RunAtLoad
    case keepAlive          // KeepAlive
    case watchPaths         // WatchPaths
    case queueDirectories   // QueueDirectories
    case sockets            // Sockets (on-demand network)
    case machServices       // MachServices (on-demand XPC)
    case onMount            // StartOnMount

    /// Short text shown in the badge.
    var badge: String {
        switch self {
        case .interval(let s):    return "every \(Self.humanize(s))"
        case .calendar:           return "calendar"
        case .runAtLoad:          return "at load"
        case .keepAlive:          return "keep-alive"
        case .watchPaths:         return "watch path"
        case .queueDirectories:   return "queue dir"
        case .sockets:            return "on-demand (socket)"
        case .machServices:       return "on-demand (xpc)"
        case .onMount:            return "on mount"
        }
    }

    /// Stable sort/priority so badges render in a consistent order.
    var order: Int {
        switch self {
        case .interval:         return 0
        case .calendar:         return 1
        case .keepAlive:        return 2
        case .watchPaths:       return 3
        case .queueDirectories: return 4
        case .sockets:          return 5
        case .machServices:     return 6
        case .onMount:          return 7
        case .runAtLoad:        return 8
        }
    }

    private static func humanize(_ seconds: Int) -> String {
        if seconds % 86_400 == 0 { return "\(seconds / 86_400)d" }
        if seconds % 3_600 == 0  { return "\(seconds / 3_600)h" }
        if seconds % 60 == 0     { return "\(seconds / 60)m" }
        return "\(seconds)s"
    }
}

/// An estimated/known time the agent will next be launched.
struct NextRun: Hashable {
    let date: Date
    /// True when derived from a heuristic (StartInterval) rather than an exact
    /// schedule (StartCalendarInterval).
    let approximate: Bool
}

/// Represents a single user LaunchAgent discovered in ~/Library/LaunchAgents,
/// enriched with runtime info from `launchctl list` and `print-disabled`.
struct LaunchAgent: Identifiable, Hashable {
    /// The launchd label, e.g. "com.example.myagent". Used as the stable id.
    let label: String
    /// Path to the .plist file on disk (nil if known only from launchctl).
    let plistPath: String?
    /// Running process id, if the service currently has a running process.
    let pid: Int?
    /// Last exit status / status code reported by launchctl (nil if unknown).
    let lastExitStatus: Int?
    /// Whether launchd currently knows about this label (bootstrapped/loaded).
    let isLoaded: Bool
    /// Whether the service is enabled in launchd's persistent database.
    let isEnabled: Bool
    /// Trigger mechanisms declared in the plist, in display order.
    let triggers: [TriggerKind]
    /// Estimated/known next launch time, if one can be derived.
    let nextRun: NextRun?

    var id: String { label }

    /// A shortened, human-friendlier name: the reverse-DNS label with its
    /// `tld.org.` prefix dropped (e.g. "com.jacksun.githubtrack" -> "githubtrack",
    /// "com.google.GoogleUpdater.wake" -> "GoogleUpdater.wake"). Falls back to the
    /// full label for labels with two or fewer components.
    var shortName: String {
        let parts = label.split(separator: ".")
        guard parts.count > 2 else { return label }
        return parts.dropFirst(2).joined(separator: ".")
    }

    /// True when there is a live process for this agent.
    var isRunning: Bool { pid != nil }

    enum Health {
        case running        // has a live PID
        case loadedIdle     // loaded but not running, clean last exit
        case failed         // loaded, last exit code non-zero
        case unloaded       // plist on disk but not loaded
    }

    var health: Health {
        if isRunning { return .running }
        if !isLoaded { return .unloaded }
        if let s = lastExitStatus, s != 0 { return .failed }
        return .loadedIdle
    }

    /// Human-friendly status text shown in the UI.
    var statusText: String {
        switch health {
        case .running:
            return "Running (pid \(pid ?? 0))"
        case .loadedIdle:
            return "Loaded (idle)"
        case .failed:
            return "Failed (exit \(lastExitStatus ?? -1))"
        case .unloaded:
            return "Not loaded"
        }
    }

    /// Multi-line detail string shown as a tooltip on hover.
    var tooltip: String {
        var lines: [String] = []
        lines.append(label)
        lines.append("Status: \(statusText)")
        lines.append("Loaded: \(isLoaded ? "yes" : "no")")
        if !triggers.isEmpty {
            lines.append("Triggers: \(triggers.map(\.badge).joined(separator: ", "))")
        }
        if let nextRun {
            let abs = Self.tooltipDateFormatter.string(from: nextRun.date)
            lines.append("Next run: \(nextRun.approximate ? "~" : "")\(abs)")
        }
        if let pid {
            lines.append("PID: \(pid)")
        }
        if let lastExitStatus {
            lines.append("Last exit code: \(lastExitStatus)")
        }
        lines.append("Plist: \(plistPath ?? "—")")
        return lines.joined(separator: "\n")
    }

    private static let tooltipDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
