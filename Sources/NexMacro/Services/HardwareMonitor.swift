import Foundation
import CPcStats

/// Raw stats data structure (thread-safe, no MainActor)
struct RawPcStats: Sendable {
    var boardTemp: Float = 0
    var boardFanRPM: Float = 0
    var uptimeSeconds: Int = 0
    var cpuTemp: Float = 0
    var cpuTempMax: Float = 100
    var cpuLoad: Float = 0
    var cpuPower: Float = 0
    var cpuTjMax: Int = 100
    var gpuTemp: Float = 0
    var gpuTempMax: Float = 100
    var gpuLoad: Float = 0
    var gpuPower: Float = 0
    var gpuFanRPM: Float = 0
    var gpuMemUsed: Float = 0
    var gpuMemTotal: Float = 0
    var gpuFreqMHz: Float = 0
    var storageTemp: Float = 0
    var storageRead: Float = 0
    var storageWrite: Float = 0
    var storagePercent: Float = 0
    var memoryUsedGB: Float = 0
    var memoryAvailGB: Float = 0
    var memoryPercent: Float = 0
    var networkUpMbps: Float = 0
    var networkDownMbps: Float = 0
    var timestamp: Int64 = 0
}

/// Service for collecting hardware statistics using the native C library
actor HardwareMonitor {
    private var isInitialized = false
    private var tempsEnabled = false

    /// Shared instance
    static let shared = HardwareMonitor()

    private init() {}

    /// Initialize the hardware monitoring system
    func initialize() {
        guard !isInitialized else { return }
        pcstats_init()
        isInitialized = true
    }

    /// Enable or disable temperature reading
    func enableTemperatures(_ enable: Bool) {
        pcstats_enable_temps(enable ? 1 : 0)
        tempsEnabled = enable
    }

    /// Collect current hardware statistics as raw data
    func collectRawStats() -> RawPcStats {
        if !isInitialized {
            initialize()
        }

        var cStatus = CPcStats.PcStatus()
        collect_stats(&cStatus)

        var stats = RawPcStats()
        stats.boardTemp = cStatus.board.temp
        stats.boardFanRPM = cStatus.board.rpm
        stats.uptimeSeconds = Int(cStatus.board.tick)
        stats.cpuTemp = cStatus.cpu.temp
        stats.cpuTempMax = cStatus.cpu.tempMax
        stats.cpuLoad = cStatus.cpu.load
        stats.cpuPower = cStatus.cpu.consume
        stats.cpuTjMax = Int(cStatus.cpu.tjMax)
        stats.gpuTemp = cStatus.gpu.temp
        stats.gpuTempMax = cStatus.gpu.tempMax
        stats.gpuLoad = cStatus.gpu.load
        stats.gpuPower = cStatus.gpu.consume
        stats.gpuFanRPM = cStatus.gpu.rpm
        stats.gpuMemUsed = cStatus.gpu.memUsed
        stats.gpuMemTotal = cStatus.gpu.memTotal
        stats.gpuFreqMHz = cStatus.gpu.freq
        stats.storageTemp = cStatus.storage.temp
        stats.storageRead = cStatus.storage.read
        stats.storageWrite = cStatus.storage.write
        stats.storagePercent = cStatus.storage.percent
        stats.memoryUsedGB = cStatus.memory.used
        stats.memoryAvailGB = cStatus.memory.avail
        stats.memoryPercent = cStatus.memory.percent
        stats.networkUpMbps = cStatus.network.up
        stats.networkDownMbps = cStatus.network.down
        stats.timestamp = Int64(cStatus.time_stamp)

        return stats
    }

    /// Build JSON string for device transmission
    func buildJSON() -> String {
        if !isInitialized {
            initialize()
        }

        var cStatus = CPcStats.PcStatus()
        collect_stats(&cStatus)

        var buffer = [CChar](repeating: 0, count: 2048)
        let length = build_json(&cStatus, &buffer, buffer.count)

        if length > 0 {
            return String(cString: buffer)
        }
        return "{}"
    }

    /// Get CPU usage percentage
    func getCPUUsage() -> Float {
        return get_cpu_usage()
    }

    /// Get CPU temperature
    func getCPUTemperature() -> Float {
        return get_cpu_temperature()
    }

    /// Get GPU temperature
    func getGPUTemperature() -> Float {
        return get_gpu_temperature()
    }

    /// Get memory usage
    func getMemoryUsage() -> (used: Float, available: Float, percent: Float) {
        var mem = CPcStats.Memory()
        get_memory_usage(&mem)
        return (used: mem.used, available: mem.avail, percent: mem.percent)
    }

    /// Get network throughput in Mb/s
    func getNetworkThroughput() -> (up: Float, down: Float) {
        var net = CPcStats.Network()
        get_network_throughput(&net)
        return (up: net.up, down: net.down)
    }

    /// Get disk usage
    func getDiskUsage() -> (temp: Float, read: Float, write: Float, percent: Float) {
        var storage = CPcStats.Storage()
        get_disk_usage(&storage)
        return (temp: storage.temp, read: storage.read, write: storage.write, percent: storage.percent)
    }

    /// Get uptime in seconds
    func getUptimeSeconds() -> Int {
        return Int(get_uptime_seconds())
    }
}

// MARK: - Stats Collection Timer

/// Manages periodic stats collection
@MainActor
@Observable
final class StatsCollector {
    private(set) var currentStats: PcStats
    private var timer: Timer?
    private let monitor = HardwareMonitor.shared
    var updateInterval: TimeInterval = 3.0

    var isRunning: Bool {
        timer != nil
    }

    init() {
        self.currentStats = PcStats()
    }

    /// Start collecting stats at the specified interval
    func start() async {
        await monitor.initialize()
        await monitor.enableTemperatures(true)

        // Initial collection
        await updateStats()

        // Start timer on main thread
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.updateStats()
            }
        }
    }

    /// Stop collecting stats
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Update stats once
    private func updateStats() async {
        let raw = await monitor.collectRawStats()

        // Update observable stats on main actor
        currentStats.boardTemp = raw.boardTemp
        currentStats.boardFanRPM = raw.boardFanRPM
        currentStats.uptimeSeconds = raw.uptimeSeconds
        currentStats.cpuTemp = raw.cpuTemp
        currentStats.cpuTempMax = raw.cpuTempMax
        currentStats.cpuLoad = raw.cpuLoad
        currentStats.cpuPower = raw.cpuPower
        currentStats.cpuTjMax = raw.cpuTjMax
        currentStats.gpuTemp = raw.gpuTemp
        currentStats.gpuTempMax = raw.gpuTempMax
        currentStats.gpuLoad = raw.gpuLoad
        currentStats.gpuPower = raw.gpuPower
        currentStats.gpuFanRPM = raw.gpuFanRPM
        currentStats.gpuMemUsed = raw.gpuMemUsed
        currentStats.gpuMemTotal = raw.gpuMemTotal
        currentStats.gpuFreqMHz = raw.gpuFreqMHz
        currentStats.storageTemp = raw.storageTemp
        currentStats.storageRead = raw.storageRead
        currentStats.storageWrite = raw.storageWrite
        currentStats.storagePercent = raw.storagePercent
        currentStats.memoryUsedGB = raw.memoryUsedGB
        currentStats.memoryAvailGB = raw.memoryAvailGB
        currentStats.memoryPercent = raw.memoryPercent
        currentStats.networkUpMbps = raw.networkUpMbps
        currentStats.networkDownMbps = raw.networkDownMbps
        currentStats.timestamp = raw.timestamp
    }

    /// Get JSON for current stats
    func getJSON() async -> String {
        await monitor.buildJSON()
    }
}
