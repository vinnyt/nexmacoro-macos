import Foundation

/// Swift-friendly wrapper for PC statistics
@MainActor
@Observable
final class PcStats {
    // Board/Motherboard
    var boardTemp: Float = 0
    var boardFanRPM: Float = 0
    var uptimeSeconds: Int = 0

    // CPU
    var cpuTemp: Float = 0
    var cpuTempMax: Float = 100
    var cpuLoad: Float = 0
    var cpuPower: Float = 0
    var cpuTjMax: Int = 100

    // GPU
    var gpuTemp: Float = 0
    var gpuTempMax: Float = 100
    var gpuLoad: Float = 0
    var gpuPower: Float = 0
    var gpuFanRPM: Float = 0
    var gpuMemUsed: Float = 0
    var gpuMemTotal: Float = 0
    var gpuFreqMHz: Float = 0

    // Storage
    var storageTemp: Float = 0
    var storageRead: Float = 0
    var storageWrite: Float = 0
    var storagePercent: Float = 0

    // Memory
    var memoryUsedGB: Float = 0
    var memoryAvailGB: Float = 0
    var memoryPercent: Float = 0

    // Network
    var networkUpMbps: Float = 0
    var networkDownMbps: Float = 0

    // Timestamp
    var timestamp: Int64 = 0

    init() {}

    /// Formatted uptime string
    var uptimeFormatted: String {
        let hours = uptimeSeconds / 3600
        let minutes = (uptimeSeconds % 3600) / 60
        let seconds = uptimeSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    /// Summary for menu bar display
    var menuBarSummary: String {
        if cpuTemp > 0 {
            return String(format: "%.0f°C", cpuTemp)
        }
        return String(format: "%.0f%%", cpuLoad)
    }
}
