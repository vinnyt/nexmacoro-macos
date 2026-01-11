import Foundation

/// Manages NexMacro device discovery, connection, and communication
@MainActor
@Observable
final class DeviceManager {
    // MARK: - Singleton

    /// Shared instance for app-wide access
    static let shared = DeviceManager()

    // MARK: - Properties

    /// Discovered devices
    private(set) var discoveredDevices: [DiscoveredDevice] = []

    /// Currently connected device
    private(set) var connectedDevice: NexDevice?

    /// Stats collector
    let statsCollector = StatsCollector()

    /// Serial port service
    private let serialService = SerialPortService()

    /// App-based profile switcher (initialized lazily)
    private var _appProfileSwitcher: AppProfileSwitcher?
    var appProfileSwitcher: AppProfileSwitcher {
        if _appProfileSwitcher == nil {
            _appProfileSwitcher = AppProfileSwitcher(deviceManager: self)
        }
        return _appProfileSwitcher!
    }

    /// Whether dynamic profile switching is enabled
    private(set) var dynamicProfileSwitchingEnabled = false

    /// Current profile configurations (5 profiles, 8 keys each)
    private(set) var profiles: [Profile] = (1...5).map { Profile(id: $0) }

    /// Whether profiles have been loaded from storage
    private var profilesLoaded = false

    /// Current active profile ID
    private(set) var activeProfileId: Int = 1

    /// Stats sending timer
    private var statsSendTimer: Timer?

    /// Stats send interval in seconds
    var statsSendInterval: TimeInterval = 3.0

    /// Whether stats are being sent to device
    private(set) var isSendingStats = false

    // MARK: - Device State

    /// Connection state for UI
    var connectionState: NexDevice.ConnectionState {
        connectedDevice?.connectionState ?? .disconnected
    }

    /// Whether a device is connected and ready
    var isReady: Bool {
        connectedDevice?.connectionState == .authenticated ||
        connectedDevice?.connectionState == .connected
    }

    // MARK: - Initialization

    init() {
        setupSerialCallbacks()
    }

    private func setupSerialCallbacks() {
        serialService.setResponseHandler { [weak self] response in
            Task { @MainActor [weak self] in
                self?.handleDeviceResponse(response)
            }
        }

        serialService.setConnectionHandler { [weak self] connected in
            Task { @MainActor [weak self] in
                if !connected {
                    self?.handleDisconnection()
                }
            }
        }

        // Observe port changes - auto-connect when new device is plugged in
        serialService.startObservingPorts { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.autoConnect()
            }
        } onRemove: { [weak self] port in
            Task { @MainActor [weak self] in
                if self?.connectedDevice?.portPath == port.path {
                    self?.handleDisconnection()
                }
                self?.scanForDevices()
            }
        }
    }

    // MARK: - Device Discovery

    /// Scan for available devices
    func scanForDevices() {
        discoveredDevices = serialService.findNexMacroDevices()
    }

    /// Auto-connect to the first available NexMacro device
    func autoConnect() async {
        // Don't auto-connect if already connected
        guard connectedDevice == nil else { return }

        scanForDevices()

        // Connect to first available device (stats auto-start on authentication)
        if let device = discoveredDevices.first {
            await connect(to: device)
        }
    }

    // MARK: - Connection

    /// Connect to a device
    func connect(to device: DiscoveredDevice) async {
        // Disconnect existing if any
        if connectedDevice != nil {
            disconnect()
        }

        let nexDevice = NexDevice(portPath: device.portPath, name: device.name)
        nexDevice.connectionState = .connecting
        connectedDevice = nexDevice

        do {
            try await serialService.connect(to: device.portPath)
            nexDevice.connectionState = .connected
            nexDevice.isConnected = true

            // Query device info
            await queryDeviceInfo()

        } catch {
            nexDevice.connectionState = .error(error.localizedDescription)
            nexDevice.isConnected = false
        }
    }

    /// Disconnect from current device
    func disconnect() {
        stopSendingStats()
        serialService.disconnect()
        connectedDevice?.connectionState = .disconnected
        connectedDevice?.isConnected = false
        connectedDevice = nil
    }

    // MARK: - Device Communication

    /// Query device type and version
    private func queryDeviceInfo() async {
        do {
            // Query device type first
            try serialService.sendCommand(.queryType)

            // Small delay between commands
            try await Task.sleep(nanoseconds: 100_000_000)

        } catch {
            print("Error querying device info: \(error)")
        }
    }

    /// Handle responses from the device
    private func handleDeviceResponse(_ response: String) {
        let parsed = NexProtocol.parseResponse(response)

        guard let device = connectedDevice,
              let responseType = parsed.type else {
            return
        }

        switch responseType {
        case .deviceType:
            device.deviceType = NexDevice.DeviceType(rawValue: parsed.content) ?? .unknown
            // Query version next
            Task {
                try? await Task.sleep(nanoseconds: 50_000_000)
                try? serialService.sendCommand(.queryVersion)
            }

        case .version:
            device.firmwareVersion = Int(parsed.content)
            // Check if we need to query device ID
            if device.deviceType != .type1 || (device.firmwareVersion ?? 0) >= 22 {
                Task {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    try? serialService.sendCommand(.queryId)
                }
            } else {
                // Old firmware, skip ID query
                device.connectionState = .connected
                // Auto-start sending stats for old firmware
                startSendingStats()
            }

        case .deviceId:
            device.deviceId = parsed.content
            // Authenticate if we have an ID
            Task {
                try? await Task.sleep(nanoseconds: 50_000_000)
                try? serialService.sendCommand(.authenticate)
            }

        case .authenticate:
            // Device sent authentication challenge
            if let deviceId = device.deviceId,
               let response = NexProtocol.generateAuthResponse(deviceId: deviceId, challenge: parsed.content) {
                Task {
                    try? serialService.sendCommand(.authenticate, param: response)
                }
            }
            device.connectionState = .authenticated
            device.isAuthenticated = true

            // Auto-start sending stats once authenticated
            startSendingStats()

        case .keyDown:
            // Key was pressed on device
            if let profileId = parsed.profileId,
               let keyId = parsed.keyId {
                handleKeyPress(profileId: profileId, keyId: keyId)
            }

        default:
            break
        }
    }

    /// Handle device disconnection
    private func handleDisconnection() {
        stopSendingStats()
        connectedDevice?.connectionState = .disconnected
        connectedDevice?.isConnected = false
        connectedDevice = nil
    }

    /// Handle key press from device
    private func handleKeyPress(profileId: Int, keyId: Int) {
        print("Key pressed: profile \(profileId), key \(keyId)")

        // Find the profile and key configuration
        guard let profile = profiles.first(where: { $0.id == profileId }),
              let keyConfig = profile.keys.first(where: { $0.id == keyId }) else {
            print("DeviceManager: No config found for profile \(profileId), key \(keyId)")
            return
        }

        // Execute all actions for this key
        guard !keyConfig.actions.isEmpty else {
            print("DeviceManager: No actions configured for key \(keyId)")
            return
        }

        Task {
            await ActionExecutor.shared.execute(keyConfig.actions)
        }
    }

    // MARK: - Profile Management

    /// Get current active profile
    var activeProfile: Profile? {
        profiles.first { $0.id == activeProfileId }
    }

    /// Load profiles from storage
    func loadConfigurations() async {
        guard !profilesLoaded else { return }

        do {
            let deviceId = connectedDevice?.deviceId
            profiles = try await ConfigurationStorage.shared.loadProfiles(deviceId: deviceId)
            let settings = try await ConfigurationStorage.shared.loadSettings()
            activeProfileId = settings.activeProfileId
            profilesLoaded = true
            print("DeviceManager: Loaded \(profiles.count) profiles")
        } catch {
            print("DeviceManager: Error loading configurations: \(error)")
            // Keep default profiles
        }
    }

    /// Save current profiles to storage
    func saveConfigurations() async {
        do {
            let deviceId = connectedDevice?.deviceId
            try await ConfigurationStorage.shared.saveProfiles(profiles, deviceId: deviceId)

            var settings = ConfigurationStorage.AppSettings()
            settings.activeProfileId = activeProfileId
            settings.lastConnectedDeviceId = deviceId
            try await ConfigurationStorage.shared.saveSettings(settings)

            print("DeviceManager: Saved configurations")
        } catch {
            print("DeviceManager: Error saving configurations: \(error)")
        }
    }

    /// Update key configuration for a profile
    func updateKeyConfig(profileId: Int, keyId: Int, config: KeyConfig) {
        guard let profileIndex = profiles.firstIndex(where: { $0.id == profileId }) else {
            return
        }
        profiles[profileIndex].setKey(keyId, config: config)

        // Auto-save after modification
        Task {
            await saveConfigurations()
        }
    }

    /// Set active profile
    func setActiveProfile(_ profileId: Int) {
        guard profileId >= 1, profileId <= 5 else { return }
        activeProfileId = profileId

        // Auto-save after modification
        Task {
            await saveConfigurations()
        }
    }

    // MARK: - Dynamic Profile Switching

    /// Enable automatic profile switching based on active app
    func enableDynamicProfileSwitching() {
        guard !dynamicProfileSwitchingEnabled else { return }
        appProfileSwitcher.start()
        dynamicProfileSwitchingEnabled = true
        print("DeviceManager: Dynamic profile switching enabled")
    }

    /// Disable automatic profile switching
    func disableDynamicProfileSwitching() {
        guard dynamicProfileSwitchingEnabled else { return }
        appProfileSwitcher.stop()
        dynamicProfileSwitchingEnabled = false
        print("DeviceManager: Dynamic profile switching disabled")
    }

    /// Toggle dynamic profile switching
    func toggleDynamicProfileSwitching() {
        if dynamicProfileSwitchingEnabled {
            disableDynamicProfileSwitching()
        } else {
            enableDynamicProfileSwitching()
        }
    }

    /// Set app-to-profile mapping
    func setAppProfileMapping(appBundleId: String, profileId: Int) {
        appProfileSwitcher.setMapping(appBundleId: appBundleId, profileId: profileId)
    }

    /// Remove app-to-profile mapping
    func removeAppProfileMapping(appBundleId: String) {
        appProfileSwitcher.removeMapping(appBundleId: appBundleId)
    }

    // MARK: - Stats Sending

    /// Start sending stats to the connected device
    func startSendingStats() {
        guard isReady, !isSendingStats else { return }

        isSendingStats = true

        // Start stats collection if not running
        if !statsCollector.isRunning {
            Task {
                await statsCollector.start()
            }
        }

        // Start sending timer
        statsSendTimer = Timer.scheduledTimer(withTimeInterval: statsSendInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.sendCurrentStats()
            }
        }

        // Send immediately
        Task {
            await sendCurrentStats()
        }
    }

    /// Stop sending stats
    func stopSendingStats() {
        statsSendTimer?.invalidate()
        statsSendTimer = nil
        isSendingStats = false
    }

    /// Send current stats to device
    private func sendCurrentStats() async {
        guard isReady else { return }

        do {
            let json = await statsCollector.getJSON()
            try serialService.sendStats(json: json)
        } catch {
            print("Error sending stats: \(error)")
        }
    }

    // MARK: - Device Commands

    /// Send reboot command to device
    func rebootDevice() {
        try? serialService.sendCommand(.reboot)
    }

    /// Send reset command to device
    func resetDevice() {
        try? serialService.sendCommand(.reset)
    }

    /// Change active profile
    func changeProfile(to profileId: Int) {
        try? serialService.sendCommand(.changeProfile, param: String(profileId))
    }

    // MARK: - RGB Control

    /// Current RGB color
    private(set) var rgbColor: (r: UInt8, g: UInt8, b: UInt8) = (255, 255, 255)

    /// Current RGB mode
    private(set) var rgbMode: RgbMode = .constantOn

    /// RGB lighting modes
    enum RgbMode: Int, CaseIterable {
        case off = 0
        case constantOn = 1
        case breath = 2
        case fastBreath = 3
        case dim = 4
        case flowing = 5
        case press = 6
        case rainbow = 7
        case slowBreath = 8

        var displayName: String {
            switch self {
            case .off: return "Off"
            case .constantOn: return "Static"
            case .breath: return "Breathing"
            case .fastBreath: return "Fast Breathing"
            case .dim: return "Dim"
            case .flowing: return "Flowing"
            case .press: return "Press React"
            case .rainbow: return "Rainbow"
            case .slowBreath: return "Slow Breathing"
            }
        }
    }

    /// Set RGB color on the device
    func setRgbColor(r: UInt8, g: UInt8, b: UInt8) {
        guard isReady else { return }
        do {
            try serialService.sendRgbColor(r: r, g: g, b: b)
            rgbColor = (r, g, b)
        } catch {
            print("DeviceManager: Error setting RGB color: \(error)")
        }
    }

    /// Set RGB mode on the device
    func setRgbMode(_ mode: RgbMode) {
        print("DeviceManager: setRgbMode called with \(mode), isReady=\(isReady)")
        guard isReady else {
            print("DeviceManager: Device not ready, skipping RGB mode change")
            return
        }
        do {
            print("DeviceManager: Sending RGB mode \(mode.rawValue) to device")
            try serialService.sendRgbMode(mode.rawValue)
            rgbMode = mode
            print("DeviceManager: RGB mode set successfully")
        } catch {
            print("DeviceManager: Error setting RGB mode: \(error)")
        }
    }
}
