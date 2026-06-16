import SwiftUI
import AppKit
import ServiceManagement

/// Lazily creates and shows a single, centered settings window on demand.
/// Using AppKit (rather than a SwiftUI `Window` scene) avoids the scene
/// auto-opening at launch for this menu-bar accessory app.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    let loginItem = LoginItemManager()
    private var window: NSWindow?

    func show() {
        loginItem.refresh()

        if window == nil {
            let hosting = NSHostingController(rootView: SettingsWindowView(loginItem: loginItem))
            let win = NSWindow(contentViewController: hosting)
            win.title = "CronBar Settings"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            window = win
        }

        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Manages the "launch at login" state via the modern ServiceManagement API
/// (SMAppService, macOS 13+). Only works from a proper .app bundle.
@MainActor
final class LoginItemManager: ObservableObject {
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published var lastError: String?

    var isEnabled: Bool { status == .enabled }
    var needsApproval: Bool { status == .requiresApproval }

    init() {
        refresh()
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// Standalone settings window (opened centered on screen).
struct SettingsWindowView: View {
    @ObservedObject var loginItem: LoginItemManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 11) {
                AppMark(size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text("CronBar")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Version \(appVersion)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Launch at login")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { loginItem.isEnabled },
                        set: { loginItem.setEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(Theme.accent)
                }

                if loginItem.needsApproval {
                    hint(
                        "Approval needed in System Settings › General › Login Items.",
                        action: ("Open", loginItem.openLoginItemsSettings)
                    )
                }
                if let err = loginItem.lastError {
                    hint(err, action: nil, isError: true)
                }
            }

            Spacer()

            Divider()

            HStack {
                Text("© 2026 Wei (Jack) Sun")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("MIT License")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(20)
        .frame(width: 380, height: 230)
        .onAppear { loginItem.refresh() }
    }

    private func hint(_ text: String, action: (String, () -> Void)?, isError: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(isError ? Theme.statusColor(.failed) : Color.secondary)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action.0, action: action.1)
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}
