import Foundation
import ServiceManagement

/// Launch at login, via `SMAppService`.
///
/// The modern API registers the app itself — no helper bundle, no LaunchAgent
/// plist to install and keep in step with where the app actually lives. macOS
/// resolves the registration to the bundle that made it, so moving the app does
/// not leave a stale entry pointing at nothing.
enum LoginItem {
    /// Whether the first-launch default has been applied. Without this, turning
    /// the setting off would be undone on the next launch — the user could
    /// never actually switch it off.
    private static let configuredKey = "klipt_loginItemConfigured"

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// True when the user (or a policy) has denied it in System Settings. The
    /// app cannot override that, and a toggle that silently fails is worse than
    /// one that explains itself.
    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                // register() throws rather than no-ops when already registered.
                guard SMAppService.mainApp.status != .enabled else { return true }
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("Klipt login item: could not set to \(enabled) — \(error.localizedDescription)")
            return false
        }
    }

    /// Turn it on once, the first time Klipt runs. A clipboard manager that is
    /// not running does nothing at all, so starting at login is the useful
    /// default — but only as a default. After this the user's choice stands.
    static func applyDefaultOnFirstLaunch() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: configuredKey) else { return }
        defaults.set(true, forKey: configuredKey)
        // Registering a debug build would add whatever path it was run from as
        // a login item, which is not something a test should leave behind.
        guard Bundle.main.bundlePath.hasPrefix("/Applications/") else {
            NSLog("Klipt login item: not in /Applications, leaving the default alone")
            return
        }
        if setEnabled(true) {
            NSLog("Klipt login item: enabled by default on first launch")
        }
    }
}

/// `Klipt.app/Contents/MacOS/Klipt --login-status`
///
/// Read-only. Registration state lives in the system's background task
/// database, not anywhere inspectable from a shell, so this is the only way to
/// see what macOS thinks without changing it.
enum LoginItemStatus {
    static func print() {
        let status = SMAppService.mainApp.status
        let label: String
        switch status {
        case .notRegistered: label = "not registered"
        case .enabled: label = "enabled"
        case .requiresApproval: label = "requires approval in System Settings"
        case .notFound: label = "not found"
        @unknown default: label = "unknown (\(status.rawValue))"
        }
        Swift.print("login item: \(label)")
        Swift.print("  bundle: \(Bundle.main.bundlePath)")
        Swift.print("  would self-enable on first launch: "
                    + (Bundle.main.bundlePath.hasPrefix("/Applications/") ? "yes" : "no, not in /Applications"))
    }
}
