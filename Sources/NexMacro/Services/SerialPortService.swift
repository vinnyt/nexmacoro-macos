import Foundation
import ORSSerial

/// Service for serial port communication with NexMacro devices
final class SerialPortService: NSObject, @unchecked Sendable {
    private var port: ORSSerialPort?
    private let portManager = ORSSerialPortManager.shared()

    private var responseBuffer = Data()
    private var onResponse: ((String) -> Void)?
    private var onConnectionChange: ((Bool) -> Void)?

    /// Current connection state
    private(set) var isConnected = false

    /// Available serial ports
    var availablePorts: [ORSSerialPort] {
        portManager.availablePorts
    }

    override init() {
        super.init()
    }

    /// Connect to a serial port
    func connect(to portPath: String) async throws {
        guard let serialPort = ORSSerialPort(path: portPath) else {
            throw SerialError.portNotFound
        }

        port = serialPort
        port?.baudRate = NSNumber(value: NexProtocol.baudRate)
        port?.numberOfDataBits = UInt(NexProtocol.dataBits)
        port?.numberOfStopBits = UInt(NexProtocol.stopBits)
        port?.parity = .none
        port?.delegate = self

        port?.open()

        // Wait a moment for connection
        try await Task.sleep(nanoseconds: 100_000_000)  // 100ms

        if port?.isOpen == true {
            isConnected = true
            onConnectionChange?(true)
        } else {
            throw SerialError.connectionFailed
        }
    }

    /// Disconnect from current port
    func disconnect() {
        port?.close()
        port = nil
        isConnected = false
        onConnectionChange?(false)
    }

    /// Send data to the device
    func send(_ data: Data) throws {
        guard let port = port, port.isOpen else {
            throw SerialError.notConnected
        }

        if !port.send(data) {
            throw SerialError.sendFailed
        }
    }

    /// Send a string to the device
    func send(_ string: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw SerialError.invalidData
        }
        try send(data)
    }

    /// Send PC stats JSON to the device
    func sendStats(json: String) throws {
        let packet = NexProtocol.buildStatsPacket(json: json)
        try send(packet)
    }

    /// Send a command to the device
    func sendCommand(_ command: NexProtocol.Command) throws {
        let data = NexProtocol.buildCommand(command)
        try send(data)
    }

    /// Send a command with parameter
    func sendCommand(_ command: NexProtocol.Command, param: String) throws {
        let data = NexProtocol.buildCommand(command, param: param)
        try send(data)
    }

    /// Send RGB color command (R, G, B values 0-255)
    /// Format from web configurator: ebf012196F3100 (header + 0 + command + color + brightness)
    func sendRgbColor(r: UInt8, g: UInt8, b: UInt8, brightness: Int = 100) throws {
        // Format: "ebf0" + "1" + "RRGGBB" + brightness (e.g., "100")
        let colorHex = String(format: "%02X%02X%02X", r, g, b)
        let command = "ebf01\(colorHex)\(brightness)"
        guard let data = command.data(using: .utf8) else {
            throw SerialError.invalidData
        }
        try send(data)
    }

    /// Send RGB mode command (mode index 0-8)
    func sendRgbMode(_ mode: Int) throws {
        // Format: "ebf0" + "j" + mode (based on web configurator pattern)
        let command = "ebf0j\(mode)"
        print("SerialPortService: Sending RGB mode command: \(command)")
        guard let data = command.data(using: .utf8) else {
            throw SerialError.invalidData
        }
        try send(data)
        print("SerialPortService: RGB mode command sent successfully")
    }

    /// Set response handler
    func setResponseHandler(_ handler: @escaping (String) -> Void) {
        onResponse = handler
    }

    /// Set connection change handler
    func setConnectionHandler(_ handler: @escaping (Bool) -> Void) {
        onConnectionChange = handler
    }

    /// Find NexMacro devices by scanning available ports
    func findNexMacroDevices() -> [DiscoveredDevice] {
        var devices: [DiscoveredDevice] = []

        for port in availablePorts {
            let path = port.path
            let name = port.name

            // Skip non-USB serial ports (Bluetooth, debug-console, etc.)
            let isUSBSerial = path.contains("usbserial") ||
                              path.contains("usbmodem") ||
                              path.contains("wchusbserial")  // CH340 chips

            guard isUSBSerial else { continue }

            let device = DiscoveredDevice(
                id: path,
                portPath: path,
                vendorId: NexMacroUSB.vendorId,
                productId: NexMacroUSB.productId,
                name: name
            )
            devices.append(device)
        }

        return devices
    }

    // MARK: - Errors

    enum SerialError: Error, LocalizedError {
        case portNotFound
        case connectionFailed
        case notConnected
        case sendFailed
        case invalidData

        var errorDescription: String? {
            switch self {
            case .portNotFound: return "Serial port not found"
            case .connectionFailed: return "Failed to open serial port"
            case .notConnected: return "Not connected to device"
            case .sendFailed: return "Failed to send data"
            case .invalidData: return "Invalid data"
            }
        }
    }
}

// MARK: - ORSSerialPort Delegate

extension SerialPortService: ORSSerialPortDelegate {
    func serialPortWasOpened(_ serialPort: ORSSerialPort) {
        isConnected = true
        onConnectionChange?(true)
    }

    func serialPortWasClosed(_ serialPort: ORSSerialPort) {
        isConnected = false
        onConnectionChange?(false)
    }

    func serialPortWasRemovedFromSystem(_ serialPort: ORSSerialPort) {
        isConnected = false
        port = nil
        onConnectionChange?(false)
    }

    func serialPort(_ serialPort: ORSSerialPort, didReceive data: Data) {
        // Append to buffer
        responseBuffer.append(data)

        // Process complete lines
        while let newlineIndex = responseBuffer.firstIndex(of: 0x0A) {  // \n
            let lineData = responseBuffer[..<newlineIndex]
            responseBuffer = Data(responseBuffer[(newlineIndex + 1)...])

            if let line = String(data: lineData, encoding: .utf8) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    onResponse?(trimmed)
                }
            }
        }
    }

    func serialPort(_ serialPort: ORSSerialPort, didEncounterError error: Error) {
        print("Serial port error: \(error.localizedDescription)")
    }
}

// MARK: - Port Discovery Notifications

extension SerialPortService {
    /// Start observing port additions/removals
    func startObservingPorts(onAdd: @escaping (ORSSerialPort) -> Void,
                             onRemove: @escaping (ORSSerialPort) -> Void) {
        NotificationCenter.default.addObserver(
            forName: .ORSSerialPortsWereConnected,
            object: nil,
            queue: .main
        ) { notification in
            if let ports = notification.userInfo?[ORSConnectedSerialPortsKey] as? [ORSSerialPort] {
                ports.forEach(onAdd)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .ORSSerialPortsWereDisconnected,
            object: nil,
            queue: .main
        ) { notification in
            if let ports = notification.userInfo?[ORSDisconnectedSerialPortsKey] as? [ORSSerialPort] {
                ports.forEach(onRemove)
            }
        }
    }
}
