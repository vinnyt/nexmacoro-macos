import Foundation

/// Handles persistence of key configurations and app settings
/// Stores JSON files in ~/Library/Application Support/NexMacro/
actor ConfigurationStorage {
    static let shared = ConfigurationStorage()

    /// Base directory for all NexMacro configurations
    private var baseDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("NexMacro", isDirectory: true)
    }

    /// Directory for device-specific configurations
    private func deviceDirectory(deviceId: String?) -> URL {
        let deviceFolder = deviceId ?? "default"
        return baseDirectory.appendingPathComponent("devices/\(deviceFolder)", isDirectory: true)
    }

    private init() {
        // Ensure base directory exists on initialization
        Task {
            try? await ensureDirectoryExists(at: baseDirectory)
        }
    }

    // MARK: - Profile Management

    /// Save all profiles for a device
    func saveProfiles(_ profiles: [Profile], deviceId: String?) async throws {
        let directory = deviceDirectory(deviceId: deviceId)
        try await ensureDirectoryExists(at: directory)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        // Save all profiles in a single file
        let profilesFile = directory.appendingPathComponent("profiles.json")
        let data = try encoder.encode(profiles)
        try data.write(to: profilesFile, options: .atomic)

        print("ConfigurationStorage: Saved \(profiles.count) profiles to \(profilesFile.path)")
    }

    /// Load all profiles for a device
    func loadProfiles(deviceId: String?) async throws -> [Profile] {
        let directory = deviceDirectory(deviceId: deviceId)
        let profilesFile = directory.appendingPathComponent("profiles.json")

        guard FileManager.default.fileExists(atPath: profilesFile.path) else {
            print("ConfigurationStorage: No profiles file found, using defaults")
            return createDefaultProfiles()
        }

        let data = try Data(contentsOf: profilesFile)
        let decoder = JSONDecoder()
        let profiles = try decoder.decode([Profile].self, from: data)

        print("ConfigurationStorage: Loaded \(profiles.count) profiles from \(profilesFile.path)")
        return profiles
    }

    /// Save a single profile
    func saveProfile(_ profile: Profile, deviceId: String?) async throws {
        var profiles = try await loadProfiles(deviceId: deviceId)

        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }

        try await saveProfiles(profiles, deviceId: deviceId)
    }

    // MARK: - App Settings

    /// App-wide settings structure
    struct AppSettings: Codable {
        var activeProfileId: Int = 1
        var statsSendInterval: Double = 3.0
        var autoConnectEnabled: Bool = true
        var lastConnectedDeviceId: String?
    }

    /// Save app settings
    func saveSettings(_ settings: AppSettings) async throws {
        try await ensureDirectoryExists(at: baseDirectory)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let settingsFile = baseDirectory.appendingPathComponent("settings.json")
        let data = try encoder.encode(settings)
        try data.write(to: settingsFile, options: .atomic)

        print("ConfigurationStorage: Saved settings to \(settingsFile.path)")
    }

    /// Load app settings
    func loadSettings() async throws -> AppSettings {
        let settingsFile = baseDirectory.appendingPathComponent("settings.json")

        guard FileManager.default.fileExists(atPath: settingsFile.path) else {
            print("ConfigurationStorage: No settings file found, using defaults")
            return AppSettings()
        }

        let data = try Data(contentsOf: settingsFile)
        let decoder = JSONDecoder()
        let settings = try decoder.decode(AppSettings.self, from: data)

        print("ConfigurationStorage: Loaded settings from \(settingsFile.path)")
        return settings
    }

    // MARK: - Default Profiles

    /// Create default profiles with sample configurations
    private func createDefaultProfiles() -> [Profile] {
        var profiles = (1...5).map { Profile(id: $0) }

        // Profile 1: Default productivity shortcuts
        profiles[0].name = "Default"
        profiles[0].keys[0] = KeyConfig(id: 0, alias: "Spotlight", actions: [.shortcut(modifiers: .command, key: "SPACE")])
        profiles[0].keys[1] = KeyConfig(id: 1, alias: "Play/Pause", actions: [.media(.playPause)])
        profiles[0].keys[2] = KeyConfig(id: 2, alias: "Vol Up", actions: [.media(.volumeUp)])
        profiles[0].keys[3] = KeyConfig(id: 3, alias: "Vol Down", actions: [.media(.volumeDown)])
        profiles[0].keys[4] = KeyConfig(id: 4, alias: "Copy", actions: [.shortcut(modifiers: .command, key: "C")])
        profiles[0].keys[5] = KeyConfig(id: 5, alias: "Paste", actions: [.shortcut(modifiers: .command, key: "V")])
        profiles[0].keys[6] = KeyConfig(id: 6, alias: "Undo", actions: [.shortcut(modifiers: .command, key: "Z")])
        profiles[0].keys[7] = KeyConfig(id: 7, alias: "Calculator", actions: [.control(.calculator)])

        // Profile 2: Media Control
        profiles[1].name = "Media"
        profiles[1].keys[0] = KeyConfig(id: 0, alias: "Prev Track", actions: [.media(.prevTrack)])
        profiles[1].keys[1] = KeyConfig(id: 1, alias: "Play/Pause", actions: [.media(.playPause)])
        profiles[1].keys[2] = KeyConfig(id: 2, alias: "Next Track", actions: [.media(.nextTrack)])
        profiles[1].keys[3] = KeyConfig(id: 3, alias: "Mute", actions: [.media(.mute)])
        profiles[1].keys[4] = KeyConfig(id: 4, alias: "Vol Down", actions: [.media(.volumeDown)])
        profiles[1].keys[5] = KeyConfig(id: 5, alias: "Vol Up", actions: [.media(.volumeUp)])

        // Profile 3: Browser shortcuts
        profiles[2].name = "Browser"
        profiles[2].keys[0] = KeyConfig(id: 0, alias: "New Tab", actions: [.shortcut(modifiers: .command, key: "T")])
        profiles[2].keys[1] = KeyConfig(id: 1, alias: "Close Tab", actions: [.shortcut(modifiers: .command, key: "W")])
        profiles[2].keys[2] = KeyConfig(id: 2, alias: "Refresh", actions: [.shortcut(modifiers: .command, key: "R")])
        profiles[2].keys[3] = KeyConfig(id: 3, alias: "Back", actions: [.control(.back)])
        profiles[2].keys[4] = KeyConfig(id: 4, alias: "Forward", actions: [.control(.forward)])
        profiles[2].keys[5] = KeyConfig(id: 5, alias: "Search", actions: [.shortcut(modifiers: .command, key: "L")])

        // Profile 4 & 5: Empty for user customization
        profiles[3].name = "Custom 1"
        profiles[4].name = "Custom 2"

        return profiles
    }

    // MARK: - Helpers

    private func ensureDirectoryExists(at url: URL) async throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            print("ConfigurationStorage: Created directory at \(url.path)")
        }
    }

    /// Get the path to the configuration directory (for debugging)
    func getConfigurationPath() -> String {
        baseDirectory.path
    }

    /// Delete all configurations (for reset functionality)
    func deleteAllConfigurations() async throws {
        if FileManager.default.fileExists(atPath: baseDirectory.path) {
            try FileManager.default.removeItem(at: baseDirectory)
            print("ConfigurationStorage: Deleted all configurations")
        }
    }

    /// Export all configurations to a single file
    func exportConfigurations(to url: URL, deviceId: String?) async throws {
        struct ExportData: Codable {
            var profiles: [Profile]
            var settings: AppSettings
            var exportDate: Date
            var version: String
        }

        let profiles = try await loadProfiles(deviceId: deviceId)
        let settings = try await loadSettings()

        let exportData = ExportData(
            profiles: profiles,
            settings: settings,
            exportDate: Date(),
            version: "1.0"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(exportData)
        try data.write(to: url, options: .atomic)

        print("ConfigurationStorage: Exported configurations to \(url.path)")
    }

    /// Import configurations from a file
    func importConfigurations(from url: URL, deviceId: String?) async throws {
        struct ExportData: Codable {
            var profiles: [Profile]
            var settings: AppSettings
            var exportDate: Date
            var version: String
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let importData = try decoder.decode(ExportData.self, from: data)

        try await saveProfiles(importData.profiles, deviceId: deviceId)
        try await saveSettings(importData.settings)

        print("ConfigurationStorage: Imported configurations from \(url.path)")
    }
}
