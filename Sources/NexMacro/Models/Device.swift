import Foundation

/// Represents a connected NexMacro device
@MainActor
@Observable
final class NexDevice: Identifiable {
    let id: UUID
    var portPath: String
    var name: String
    var deviceId: String?
    var deviceType: DeviceType?
    var firmwareVersion: Int?
    var isConnected: Bool
    var isAuthenticated: Bool

    /// Device types based on decompiled nexmacro code
    enum DeviceType: String, Sendable {
        case type1 = "1"  // Original
        case type2 = "2"  // Alternative
        case unknown

        var displayName: String {
            switch self {
            case .type1: return "NexMacro Standard"
            case .type2: return "NexMacro Pro"
            case .unknown: return "Unknown Device"
            }
        }
    }

    /// Connection state for UI
    enum ConnectionState: Sendable, Equatable {
        case disconnected
        case connecting
        case connected
        case authenticated
        case error(String)

        var description: String {
            switch self {
            case .disconnected: return "Disconnected"
            case .connecting: return "Connecting..."
            case .connected: return "Connected"
            case .authenticated: return "Ready"
            case .error(let msg): return "Error: \(msg)"
            }
        }

        var isConnected: Bool {
            switch self {
            case .connected, .authenticated: return true
            default: return false
            }
        }
    }

    var connectionState: ConnectionState = .disconnected

    init(portPath: String, name: String? = nil) {
        self.id = UUID()
        self.portPath = portPath
        self.name = name ?? portPath.components(separatedBy: "/").last ?? "Unknown"
        self.isConnected = false
        self.isAuthenticated = false
    }

}

/// NexMacro device USB identifiers (not MainActor isolated)
enum NexMacroUSB {
    /// VID: 0x303A (Espressif)
    static let vendorId: Int = 0x303A
    /// PID: 0x0012
    static let productId: Int = 0x0012
}

/// Device discovery result
struct DiscoveredDevice: Identifiable, Sendable {
    let id: String  // Port path
    let portPath: String
    let vendorId: Int?
    let productId: Int?
    let name: String

    var isNexMacro: Bool {
        vendorId == NexMacroUSB.vendorId && productId == NexMacroUSB.productId
    }
}
