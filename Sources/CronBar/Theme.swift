import SwiftUI

/// Centralized design tokens for CronBar: an indigo/violet accent that adapts
/// to light and dark mode, plus semantic colors for status and triggers.
enum Theme {
    // MARK: Accent

    static let accent = Color(red: 0.45, green: 0.38, blue: 0.93)        // ~#7361ED

    static let accentGradient = LinearGradient(
        colors: [
            Color(red: 0.53, green: 0.45, blue: 0.97),   // ~#8773F7
            Color(red: 0.36, green: 0.30, blue: 0.88),   // ~#5C4DE0
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: Status

    static func statusColor(_ health: LaunchAgent.Health) -> Color {
        switch health {
        case .running:    return Color(red: 0.27, green: 0.78, blue: 0.46)   // green
        case .loadedIdle: return Color(red: 0.55, green: 0.56, blue: 0.62)   // gray
        case .failed:     return Color(red: 0.96, green: 0.35, blue: 0.40)   // red
        case .unloaded:   return Color(red: 0.98, green: 0.66, blue: 0.24)   // amber
        }
    }

    // MARK: Triggers

    static func triggerColor(_ trigger: TriggerKind) -> Color {
        switch trigger {
        case .interval, .calendar:           return accent                                  // scheduled
        case .keepAlive:                     return Color(red: 0.27, green: 0.78, blue: 0.46) // service
        case .watchPaths, .queueDirectories: return Color(red: 0.66, green: 0.45, blue: 0.95) // filesystem
        case .sockets, .machServices:        return Color(red: 0.98, green: 0.66, blue: 0.24) // on-demand
        case .onMount:                       return Color(red: 0.20, green: 0.70, blue: 0.75) // device
        case .runAtLoad:                     return Color(red: 0.55, green: 0.56, blue: 0.62) // startup
        }
    }
}
