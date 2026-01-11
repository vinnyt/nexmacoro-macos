import SwiftUI
import AppKit

/// NexMacro - macOS Menu Bar App for Macro Keypad Configuration
@main
struct NexMacroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Start stats collection and device connection on app launch
        Task { @MainActor in
            // Load saved configurations
            await DeviceManager.shared.loadConfigurations()

            // Start stats collection and auto-connect
            await DeviceManager.shared.statsCollector.start()
            await DeviceManager.shared.autoConnect()
        }
    }

    var body: some Scene {
        // Menu bar app
        MenuBarExtra {
            MenuBarView()
                .environment(DeviceManager.shared)
        } label: {
            MenuBarLabel()
                .environment(DeviceManager.shared)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - App Delegate for Settings Window

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
    }

    func openSettings() {
        // Activate app first
        NSApp.activate(ignoringOtherApps: true)

        if let window = settingsWindow, window.isVisible {
            window.orderFrontRegardless()
            window.makeKey()
            return
        }

        let settingsView = SettingsView()
            .environment(DeviceManager.shared)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 550),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "NexMacro Settings"
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating  // Ensure it appears above other windows initially

        self.settingsWindow = window
        window.orderFrontRegardless()
        window.makeKey()

        // Reset level after a moment so it behaves normally
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            window.level = .normal
        }
    }
}

// MARK: - Menu Bar Label

struct MenuBarLabel: View {
    @Environment(DeviceManager.self) private var deviceManager

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .symbolRenderingMode(.hierarchical)

            Text(deviceManager.statsCollector.currentStats.menuBarSummary)
                .font(.system(.caption, design: .monospaced))
        }
    }

    private var iconName: String {
        switch deviceManager.connectionState {
        case .disconnected:
            return "keyboard.badge.ellipsis"
        case .connecting:
            return "keyboard.badge.ellipsis"
        case .connected, .authenticated:
            return "keyboard.fill"
        case .error:
            return "keyboard.badge.exclamationmark"
        }
    }
}

// MARK: - Menu Bar View

struct MenuBarView: View {
    @Environment(DeviceManager.self) private var deviceManager
    @State private var debugExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                headerSection

                Divider()
                    .padding(.vertical, 8)

                // Stats Section - Always show
                statsSection

                Divider()
                    .padding(.vertical, 8)

                // Debug Section - Always show
                debugSection

                Divider()
                    .padding(.vertical, 8)

                // Actions
                actionsSection
            }
            .padding(12)
        }
        .frame(width: 320, height: debugExpanded ? 720 : 340)
    }

    // MARK: - Sections

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("NexMacro")
                    .font(.headline)

                Text(deviceManager.connectionState.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if deviceManager.isSendingStats {
                Image(systemName: "arrow.up.arrow.down.circle.fill")
                    .foregroundStyle(.green)
                    .help("Sending stats to device")
            }
        }
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("System Stats")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            StatsGridView(stats: deviceManager.statsCollector.currentStats)
        }
    }

    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Details")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        debugExpanded.toggle()
                    }
                } label: {
                    Image(systemName: debugExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }

            if debugExpanded {
                DebugView(
                    stats: deviceManager.statsCollector.currentStats,
                    device: deviceManager.connectedDevice,
                    discoveredCount: deviceManager.discoveredDevices.count,
                    isSending: deviceManager.isSendingStats
                )
            }
        }
    }

    private var actionsSection: some View {
        VStack(spacing: 8) {
            // Profile selector
            if deviceManager.isReady {
                HStack {
                    Text("Profile:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Profile", selection: Binding(
                        get: { deviceManager.activeProfileId },
                        set: { newId in
                            deviceManager.setActiveProfile(newId)
                            deviceManager.changeProfile(to: newId)
                        }
                    )) {
                        ForEach(1...5, id: \.self) { id in
                            Text("\(id)").tag(id)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            Toggle(isOn: Binding(
                get: { deviceManager.isSendingStats },
                set: { newValue in
                    if newValue {
                        deviceManager.startSendingStats()
                    } else {
                        deviceManager.stopSendingStats()
                    }
                }
            )) {
                Label("Send Stats to Device", systemImage: "chart.line.uptrend.xyaxis")
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(!deviceManager.isReady)

            HStack {
                Button("Settings...") {
                    AppDelegate.shared?.openSettings()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(.top, 4)
        }
    }
}

// MARK: - Debug View

struct DebugView: View {
    let stats: PcStats
    let device: NexDevice?
    let discoveredCount: Int
    let isSending: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Connection Info
            Group {
                DebugRow(label: "Ports Found", value: "\(discoveredCount)")
                if let device = device {
                    DebugRow(label: "Port", value: device.portPath)
                    DebugRow(label: "Device ID", value: device.deviceId ?? "—")
                    DebugRow(label: "Type", value: device.deviceType?.rawValue ?? "—")
                    DebugRow(label: "Firmware", value: device.firmwareVersion.map { "v\($0)" } ?? "—")
                    DebugRow(label: "Authenticated", value: device.isAuthenticated ? "Yes" : "No")
                } else {
                    DebugRow(label: "Port", value: "Not connected")
                }
                DebugRow(label: "Sending", value: isSending ? "Active" : "Stopped")
            }

            Divider()
                .padding(.vertical, 2)

            // Raw Stats
            Group {
                Text("Raw Values")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                DebugRow(label: "CPU Temp", value: String(format: "%.2f°C", stats.cpuTemp))
                DebugRow(label: "CPU Load", value: String(format: "%.2f%%", stats.cpuLoad))
                DebugRow(label: "CPU Power", value: String(format: "%.2fW", stats.cpuPower))

                DebugRow(label: "GPU Temp", value: String(format: "%.2f°C", stats.gpuTemp))
                DebugRow(label: "GPU Load", value: String(format: "%.2f%%", stats.gpuLoad))
                DebugRow(label: "GPU Power", value: String(format: "%.2fW", stats.gpuPower))
                DebugRow(label: "GPU Freq", value: String(format: "%.0f MHz", stats.gpuFreqMHz))

                DebugRow(label: "Board Temp", value: String(format: "%.2f°C", stats.boardTemp))
                DebugRow(label: "Fan RPM", value: String(format: "%.0f", stats.boardFanRPM))

                DebugRow(label: "Memory", value: String(format: "%.2f / %.2f GB", stats.memoryUsedGB, stats.memoryUsedGB + stats.memoryAvailGB))
                DebugRow(label: "Disk", value: String(format: "%.1f%%", stats.storagePercent))

                DebugRow(label: "Net Up", value: String(format: "%.3f Mb/s", stats.networkUpMbps))
                DebugRow(label: "Net Down", value: String(format: "%.3f Mb/s", stats.networkDownMbps))

                DebugRow(label: "Uptime", value: stats.uptimeFormatted)
                DebugRow(label: "Timestamp", value: "\(stats.timestamp)")
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
        .font(.system(.caption2, design: .monospaced))
    }
}

struct DebugRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .foregroundStyle(.primary)
            Spacer()
        }
    }
}

// MARK: - Stats Grid

struct StatsGridView: View {
    let stats: PcStats

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                StatCell(label: "CPU", value: String(format: "%.0f%%", stats.cpuLoad), icon: "cpu")
                StatCell(label: "Temp", value: String(format: "%.0f°C", stats.cpuTemp), icon: "thermometer.medium")
            }

            GridRow {
                StatCell(label: "GPU", value: String(format: "%.0f%%", stats.gpuLoad), icon: "gpu")
                StatCell(label: "Temp", value: String(format: "%.0f°C", stats.gpuTemp), icon: "thermometer.medium")
            }

            GridRow {
                StatCell(label: "Memory", value: String(format: "%.0f%%", stats.memoryPercent), icon: "memorychip")
                StatCell(label: "Disk", value: String(format: "%.0f%%", stats.storagePercent), icon: "internaldrive")
            }

            GridRow {
                StatCell(label: "Net ↑", value: String(format: "%.1f Mb/s", stats.networkUpMbps), icon: "arrow.up")
                StatCell(label: "Net ↓", value: String(format: "%.1f Mb/s", stats.networkDownMbps), icon: "arrow.down")
            }
        }
        .font(.system(.caption, design: .monospaced))
    }
}

struct StatCell: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .frame(width: 16)
                .foregroundStyle(.secondary)

            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 45, alignment: .leading)

            Text(value)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(DeviceManager.self) private var deviceManager

    var body: some View {
        TabView {
            KeyConfigurationView()
                .environment(deviceManager)
                .tabItem {
                    Label("Keys", systemImage: "keyboard")
                }

            RGBControlView()
                .environment(deviceManager)
                .tabItem {
                    Label("RGB", systemImage: "lightbulb.fill")
                }

            GeneralSettingsView()
                .environment(deviceManager)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            DeviceInfoView()
                .environment(deviceManager)
                .tabItem {
                    Label("Device", systemImage: "cpu")
                }
        }
        .frame(width: 500, height: 550)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @Environment(DeviceManager.self) private var deviceManager
    @AppStorage("statsSendInterval") private var statsSendInterval: Double = 3.0
    @AppStorage("showTempInMenuBar") private var showTempInMenuBar = true
    @State private var showingAppMappings = false
    @State private var launchAtLogin = LoginItemManager.shared.isEnabled

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        if newValue {
                            LoginItemManager.shared.enable()
                        } else {
                            LoginItemManager.shared.disable()
                        }
                    }
            }

            Section("Stats") {
                Slider(value: $statsSendInterval, in: 1...10, step: 1) {
                    Text("Update Interval: \(Int(statsSendInterval))s")
                }

                Toggle("Show temperature in menu bar", isOn: $showTempInMenuBar)
            }

            Section("Dynamic Profiles") {
                Toggle("Auto-switch profiles by app", isOn: Binding(
                    get: { deviceManager.dynamicProfileSwitchingEnabled },
                    set: { newValue in
                        if newValue {
                            deviceManager.enableDynamicProfileSwitching()
                        } else {
                            deviceManager.disableDynamicProfileSwitching()
                        }
                    }
                ))

                if deviceManager.dynamicProfileSwitchingEnabled {
                    Button("Configure App Mappings...") {
                        showingAppMappings = true
                    }

                    Text("Current mappings: \(deviceManager.appProfileSwitcher.appProfileMappings.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("About") {
                LabeledContent("Version", value: "1.0.0")
                Link("GitHub", destination: URL(string: "https://github.com")!)
            }
        }
        .formStyle(.grouped)
        .padding()
        .sheet(isPresented: $showingAppMappings) {
            AppMappingsSheet()
                .environment(deviceManager)
        }
    }
}

// MARK: - App Mappings Sheet

struct AppMappingsSheet: View {
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedApp: String = ""
    @State private var selectedProfile: Int = 1

    var body: some View {
        VStack(spacing: 16) {
            Text("App Profile Mappings")
                .font(.headline)

            // Current mappings
            if !deviceManager.appProfileSwitcher.appProfileMappings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Mappings")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(Array(deviceManager.appProfileSwitcher.appProfileMappings), id: \.key) { bundleId, profileId in
                        HStack {
                            Text(appName(for: bundleId))
                                .lineLimit(1)
                            Spacer()
                            Text("Profile \(profileId)")
                                .foregroundStyle(.secondary)
                            Button {
                                deviceManager.removeAppProfileMapping(appBundleId: bundleId)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

                Divider()
            }

            // Add new mapping
            VStack(alignment: .leading, spacing: 8) {
                Text("Add Mapping")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("App", selection: $selectedApp) {
                    Text("Select App...").tag("")
                    ForEach(AppProfileSwitcher.commonApps, id: \.bundleId) { app in
                        Text(app.name).tag(app.bundleId)
                    }
                }
                .pickerStyle(.menu)

                Picker("Profile", selection: $selectedProfile) {
                    ForEach(1...5, id: \.self) { id in
                        Text("Profile \(id)").tag(id)
                    }
                }
                .pickerStyle(.segmented)

                Button("Add Mapping") {
                    guard !selectedApp.isEmpty else { return }
                    deviceManager.setAppProfileMapping(appBundleId: selectedApp, profileId: selectedProfile)
                    selectedApp = ""
                }
                .disabled(selectedApp.isEmpty)
            }

            Spacer()

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(width: 400, height: 450)
    }

    private func appName(for bundleId: String) -> String {
        AppProfileSwitcher.commonApps.first { $0.bundleId == bundleId }?.name ?? bundleId
    }
}

// MARK: - Device Info View

struct DeviceInfoView: View {
    @Environment(DeviceManager.self) private var deviceManager

    var body: some View {
        Form {
            Section("Connection") {
                if let device = deviceManager.connectedDevice {
                    LabeledContent("Name", value: device.name)
                    LabeledContent("Port", value: device.portPath)
                    LabeledContent("Status", value: device.connectionState.description)

                    if let id = device.deviceId {
                        LabeledContent("Device ID", value: id)
                    }
                    if let version = device.firmwareVersion {
                        LabeledContent("Firmware", value: "v\(version)")
                    }
                    if let type = device.deviceType {
                        LabeledContent("Type", value: type.displayName)
                    }
                } else {
                    Text("No device connected")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Actions") {
                Button("Reconnect") {
                    Task {
                        await deviceManager.autoConnect()
                    }
                }
                .disabled(deviceManager.connectedDevice != nil)

                Button("Disconnect") {
                    deviceManager.disconnect()
                }
                .disabled(deviceManager.connectedDevice == nil)
            }

            Section("Configuration") {
                Button("Reset to Defaults") {
                    Task {
                        try? await ConfigurationStorage.shared.deleteAllConfigurations()
                        await deviceManager.loadConfigurations()
                    }
                }
                .foregroundStyle(.red)

                Text("Config path: ~/Library/Application Support/NexMacro/")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview("Menu Bar") {
    MenuBarView()
        .environment(DeviceManager())
}
