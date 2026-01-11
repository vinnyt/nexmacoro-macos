import Foundation
import AppKit

/// Monitors frontmost application and switches profiles automatically
@MainActor
final class AppProfileSwitcher {
    private var observer: NSObjectProtocol?
    private var isEnabled = false
    private weak var deviceManager: DeviceManager?

    /// App bundle ID to profile ID mapping
    private(set) var appProfileMappings: [String: Int] = [:]

    /// Default profile when no mapping matches
    var defaultProfileId: Int = 1

    init(deviceManager: DeviceManager) {
        self.deviceManager = deviceManager
    }

    // MARK: - Start/Stop

    /// Start monitoring frontmost app changes
    func start() {
        guard !isEnabled else { return }

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            Task { @MainActor in
                self.handleAppActivation(notification)
            }
        }

        isEnabled = true
        print("AppProfileSwitcher: Started monitoring")

        // Check current frontmost app
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            switchProfileForApp(frontApp)
        }
    }

    /// Stop monitoring
    func stop() {
        if let observer = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
        isEnabled = false
        print("AppProfileSwitcher: Stopped monitoring")
    }

    // MARK: - Profile Mappings

    /// Set profile mapping for an app
    func setMapping(appBundleId: String, profileId: Int) {
        appProfileMappings[appBundleId] = profileId
        print("AppProfileSwitcher: Mapped \(appBundleId) -> Profile \(profileId)")
    }

    /// Remove profile mapping for an app
    func removeMapping(appBundleId: String) {
        appProfileMappings.removeValue(forKey: appBundleId)
    }

    /// Clear all mappings
    func clearMappings() {
        appProfileMappings.removeAll()
    }

    // MARK: - Private

    private func handleAppActivation(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        switchProfileForApp(app)
    }

    private func switchProfileForApp(_ app: NSRunningApplication) {
        guard let bundleId = app.bundleIdentifier else { return }

        let targetProfileId: Int
        if let mappedProfile = appProfileMappings[bundleId] {
            targetProfileId = mappedProfile
        } else {
            targetProfileId = defaultProfileId
        }

        // Only switch if different from current
        guard targetProfileId != deviceManager?.activeProfileId else { return }

        print("AppProfileSwitcher: App '\(app.localizedName ?? bundleId)' activated -> Profile \(targetProfileId)")

        deviceManager?.setActiveProfile(targetProfileId)
        deviceManager?.changeProfile(to: targetProfileId)
    }
}

// MARK: - Common App Bundle IDs

extension AppProfileSwitcher {
    /// Commonly used app bundle IDs for easy reference
    static let commonApps: [(name: String, bundleId: String)] = [
        ("Safari", "com.apple.Safari"),
        ("Chrome", "com.google.Chrome"),
        ("Firefox", "org.mozilla.firefox"),
        ("VS Code", "com.microsoft.VSCode"),
        ("Xcode", "com.apple.dt.Xcode"),
        ("Terminal", "com.apple.Terminal"),
        ("iTerm", "com.googlecode.iterm2"),
        ("Slack", "com.tinyspeck.slackmacgap"),
        ("Discord", "com.hnc.Discord"),
        ("Spotify", "com.spotify.client"),
        ("Music", "com.apple.Music"),
        ("Finder", "com.apple.finder"),
        ("Mail", "com.apple.mail"),
        ("Notes", "com.apple.Notes"),
        ("Pages", "com.apple.iWork.Pages"),
        ("Numbers", "com.apple.iWork.Numbers"),
        ("Keynote", "com.apple.iWork.Keynote"),
        ("Photoshop", "com.adobe.Photoshop"),
        ("Illustrator", "com.adobe.Illustrator"),
        ("Premiere Pro", "com.adobe.PremierePro"),
        ("Final Cut Pro", "com.apple.FinalCut"),
        ("Logic Pro", "com.apple.logic10"),
        ("GarageBand", "com.apple.garageband10"),
        ("Zoom", "us.zoom.xos"),
        ("Microsoft Word", "com.microsoft.Word"),
        ("Microsoft Excel", "com.microsoft.Excel"),
        ("Microsoft PowerPoint", "com.microsoft.Powerpoint"),
    ]

    /// Get bundle ID for a common app name
    static func bundleId(for appName: String) -> String? {
        commonApps.first { $0.name.lowercased() == appName.lowercased() }?.bundleId
    }
}
