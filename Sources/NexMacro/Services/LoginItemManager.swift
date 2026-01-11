import Foundation
import ServiceManagement

/// Manages launch at login functionality using SMAppService (macOS 13+)
@MainActor
final class LoginItemManager {
    static let shared = LoginItemManager()

    private init() {}

    /// Whether the app is set to launch at login
    var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            // Fallback for older macOS - check using legacy API
            return isEnabledLegacy
        }
    }

    /// Enable launch at login
    func enable() {
        if #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.register()
                print("LoginItemManager: Enabled launch at login")
            } catch {
                print("LoginItemManager: Failed to enable launch at login: \(error)")
            }
        } else {
            enableLegacy()
        }
    }

    /// Disable launch at login
    func disable() {
        if #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.unregister()
                print("LoginItemManager: Disabled launch at login")
            } catch {
                print("LoginItemManager: Failed to disable launch at login: \(error)")
            }
        } else {
            disableLegacy()
        }
    }

    /// Toggle launch at login
    func toggle() {
        if isEnabled {
            disable()
        } else {
            enable()
        }
    }

    // MARK: - Legacy Support (macOS 12 and earlier)

    private var isEnabledLegacy: Bool {
        // Use LSSharedFileList for older macOS versions
        // This is a simplified check - full implementation would query the login items list
        return UserDefaults.standard.bool(forKey: "launchAtLoginEnabled")
    }

    private func enableLegacy() {
        // For older macOS, we'd use LSSharedFileList APIs
        // This is simplified - marking in UserDefaults as a placeholder
        UserDefaults.standard.set(true, forKey: "launchAtLoginEnabled")
        print("LoginItemManager: Legacy enable (placeholder)")
    }

    private func disableLegacy() {
        UserDefaults.standard.set(false, forKey: "launchAtLoginEnabled")
        print("LoginItemManager: Legacy disable (placeholder)")
    }
}
