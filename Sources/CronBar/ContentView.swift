import SwiftUI

struct ContentView: View {
    @EnvironmentObject var manager: LaunchAgentManager
    @State private var autoRefreshTask: Task<Void, Never>?

    /// How often to re-poll launchd while the panel is visible.
    private let refreshInterval: UInt64 = 5_000_000_000  // 5s in nanoseconds

    private var running: [LaunchAgent] { manager.agents.filter(\.isRunning) }
    private var scheduled: [LaunchAgent] { manager.agents.filter { !$0.isRunning } }

    var body: some View {
        VStack(spacing: 0) {
            header

            if manager.agents.isEmpty {
                emptyState
            } else {
                VStack(spacing: 2) {
                    if !running.isEmpty {
                        SectionHeader(title: "Running", count: running.count)
                        ForEach(running) { agent in
                            AgentRow(agent: agent)
                        }
                    }
                    if !scheduled.isEmpty {
                        SectionHeader(title: "Scheduled", count: scheduled.count)
                        ForEach(scheduled) { agent in
                            AgentRow(agent: agent)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }

            if let err = manager.lastError {
                errorBanner(err)
            }

            footer
        }
        .frame(width: 360)
        .onAppear { startAutoRefresh() }
        .onDisappear { stopAutoRefresh() }
    }

    // MARK: Auto-refresh (only while the panel is open)

    private func startAutoRefresh() {
        manager.refresh()
        autoRefreshTask?.cancel()
        autoRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: refreshInterval)
                if Task.isCancelled { break }
                manager.refresh()
            }
        }
    }

    private func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            AppMark(size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("CronBar")
                    .font(.system(size: 14, weight: .semibold))
                Text("\(manager.agents.count) launch agent\(manager.agents.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            RefreshButton(isRefreshing: manager.isRefreshing) { manager.refresh() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: Empty / error / footer

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text("No launch agents")
                .font(.system(size: 13, weight: .medium))
            Text("~/Library/LaunchAgents")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.statusColor(.failed))
            Text(message)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.statusColor(.failed).opacity(0.10))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if manager.isRefreshing {
                ProgressView().controlSize(.small)
                Text("Refreshing…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "power")
                    Text("Quit")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.quaternary.opacity(0.4))
        .overlay(Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1), alignment: .top)
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
            Text("\(count)")
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.primary.opacity(0.08), in: Capsule())
            Spacer()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }
}

// MARK: - App mark (mini icon)

struct AppMark: View {
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let icon = IconAssets.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                // Fallback if bundled artwork is missing.
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(Theme.accentGradient)
                    .overlay(
                        Image(systemName: "clock.arrow.2.circlepath")
                            .font(.system(size: size * 0.52, weight: .semibold))
                            .foregroundStyle(.white)
                    )
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.accent.opacity(0.30), radius: size * 0.12, y: size * 0.05)
    }
}

// MARK: - Refresh button

struct RefreshButton: View {
    let isRefreshing: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hovering ? Theme.accent : .secondary)
                .frame(width: 26, height: 26)
                .background(
                    Circle().fill(hovering ? Theme.accent.opacity(0.12) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .disabled(isRefreshing)
        .onHover { hovering = $0 }
        .help("Refresh")
    }
}

// MARK: - Agent row

struct AgentRow: View {
    @EnvironmentObject var manager: LaunchAgentManager
    let agent: LaunchAgent
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 11) {
            statusDot

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(agent.shortName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    ForEach(agent.triggers, id: \.self) { trigger in
                        TriggerBadge(trigger: trigger)
                    }
                }
                HStack(spacing: 5) {
                    Text(agent.label)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .layoutPriority(1)
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text(agent.statusText)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }

            Spacer(minLength: 6)

            if hovering {
                actions
            } else if let nextRun = agent.nextRun {
                nextRunLabel(nextRun)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(hovering ? Theme.accent.opacity(0.10) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(agent.tooltip)
        .contextMenu {
            Button("Load") { manager.load(agent) }
                .disabled(agent.isLoaded || agent.plistPath == nil)
            Button("Unload") { manager.unload(agent) }
                .disabled(!agent.isLoaded)
            Button(agent.isRunning ? "Kill" : "Start") { manager.toggleRun(agent) }
            Divider()
            Button("Edit config…") { manager.editConfig(agent) }
                .disabled(agent.plistPath == nil)
            Button("Reveal plist in Finder") { manager.revealInFinder(agent) }
        }
    }

    private var statusDot: some View {
        let color = Theme.statusColor(agent.health)
        return Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .shadow(color: color.opacity(0.7), radius: 2.5)
    }

    // MARK: Next run

    private func nextRunLabel(_ nextRun: NextRun) -> some View {
        let soon = nextRun.date.timeIntervalSinceNow < 300
        return HStack(spacing: 3) {
            Image(systemName: "clock")
                .font(.system(size: 9))
            Text(Self.relativeText(nextRun))
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
        }
        .foregroundStyle(soon ? Theme.accent : Color.secondary)
        .help("Next run: \(Self.absoluteText(nextRun))")
    }

    /// e.g. "in 12m", "~in 1h 5m", "due".
    static func relativeText(_ nextRun: NextRun) -> String {
        let prefix = nextRun.approximate ? "~" : ""
        let secs = Int(nextRun.date.timeIntervalSinceNow)
        if secs <= 0 { return "\(prefix)due" }
        let str: String
        if secs < 60 {
            str = "\(secs)s"
        } else if secs < 3600 {
            str = "\(secs / 60)m"
        } else if secs < 86_400 {
            let h = secs / 3600, m = (secs % 3600) / 60
            str = m > 0 ? "\(h)h \(m)m" : "\(h)h"
        } else {
            let d = secs / 86_400, h = (secs % 86_400) / 3600
            str = h > 0 ? "\(d)d \(h)h" : "\(d)d"
        }
        return "\(prefix)in \(str)"
    }

    static func absoluteText(_ nextRun: NextRun) -> String {
        (nextRun.approximate ? "~" : "") + Self.absoluteFormatter.string(from: nextRun.date)
    }

    private static let absoluteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 2) {
            iconButton("tray.and.arrow.down", help: "Load", enabled: !agent.isLoaded && agent.plistPath != nil) {
                manager.load(agent)
            }
            iconButton("tray.and.arrow.up", help: "Unload", enabled: agent.isLoaded) {
                manager.unload(agent)
            }
            iconButton(
                agent.isRunning ? "stop.fill" : "play.fill",
                help: agent.isRunning ? "Kill process" : "Start",
                enabled: true
            ) {
                manager.toggleRun(agent)
            }
            iconButton("pencil", help: "Edit config", enabled: agent.plistPath != nil) {
                manager.editConfig(agent)
            }
        }
    }

    private func iconButton(_ name: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        HoverIconButton(systemName: name, help: help, enabled: enabled, action: action)
    }
}

// MARK: - Hover icon button

struct HoverIconButton: View {
    let systemName: String
    let help: String
    let enabled: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(enabled ? (hovering ? Theme.accent : Color.secondary) : Color.secondary.opacity(0.35))
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(hovering && enabled ? Theme.accent.opacity(0.14) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
        .help(help)
    }
}

// MARK: - Trigger badge

struct TriggerBadge: View {
    let trigger: TriggerKind

    var body: some View {
        Text(trigger.badge)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color { Theme.triggerColor(trigger) }
}
