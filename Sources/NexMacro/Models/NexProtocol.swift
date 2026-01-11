import Foundation
import CommonCrypto

/// NexMacro device communication protocol
/// Based on decompiled EezBotFun_Config Windows application
enum NexProtocol {
    // MARK: - Magic Headers
    static let commandHeader = "ebf"  // Commands to device
    static let statsHeader = "pcs"     // PC stats to device

    // MARK: - Commands (ebf protocol)
    enum Command: Character {
        case keyConfig = "0"
        case rgbColor = "1"
        case addAlias = "2"
        case deleteAlias = "3"
        case wifiConfig = "4"
        case queryVersion = "5"
        case addScript = "6"
        case deleteScript = "7"
        case queryConfig = "8"
        case changeProfile = "9"
        case setHidMode = "a"
        case resetHidMode = "b"
        case reboot = "c"
        case reset = "d"
        case queryType = "e"
        case queryId = "f"
        case authenticate = "g"
        case setBrightTheme = "h"
        case clearPairedDongle = "i"
        case rgbMode = "j"
        case restoreLastVersion = "z"
    }

    // MARK: - Response Types (from device)
    enum Response: Character {
        case version = "v"
        case hasAlias = "a"
        case noAlias = "b"
        case keyConfig = "c"
        case hasScript = "d"
        case deviceType = "e"
        case deviceId = "f"
        case authenticate = "g"
        case keyDown = "k"
    }

    // MARK: - Command Construction

    /// Build a simple command (no parameters)
    static func buildCommand(_ cmd: Command) -> Data {
        let str = "\(commandHeader)\0\(cmd.rawValue)"
        var data = Data(str.utf8)
        // Set length byte at index 3
        if data.count > 3 {
            data[3] = UInt8(data.count - 4)
        }
        // Append newline terminator
        data.append(0x0A)
        return data
    }

    /// Build a command with a boolean parameter
    static func buildCommand(_ cmd: Command, value: Bool) -> Data {
        let str = "\(commandHeader)\0\(cmd.rawValue)\(value ? "1" : "0")"
        var data = Data(str.utf8)
        if data.count > 3 {
            data[3] = UInt8(data.count - 4)
        }
        // Append newline terminator
        data.append(0x0A)
        return data
    }

    /// Build a command with a string parameter
    static func buildCommand(_ cmd: Command, param: String) -> Data {
        let str = "\(commandHeader)\0\(cmd.rawValue)\(param)"
        var data = Data(str.utf8)
        if data.count > 3 {
            data[3] = UInt8(data.count - 4)
        }
        // Append newline terminator
        data.append(0x0A)
        return data
    }

    /// Build a command with profile and key IDs
    static func buildCommand(_ cmd: Command, profileId: Int, keyId: Int) -> Data {
        let str = "\(commandHeader)\0\(cmd.rawValue)\(profileId).\(keyId)"
        var data = Data(str.utf8)
        if data.count > 3 {
            data[3] = UInt8(data.count - 4)
        }
        // Append newline terminator
        data.append(0x0A)
        return data
    }

    /// Build a command with profile, key, and parameter
    static func buildCommand(_ cmd: Command, profileId: Int, keyId: Int, param: String) -> Data {
        let str = "\(commandHeader)\0\(cmd.rawValue)\(profileId).\(keyId):\(param)"
        var data = Data(str.utf8)
        if data.count > 3 {
            data[3] = UInt8(data.count - 4)
        }
        // Append newline terminator
        data.append(0x0A)
        return data
    }

    /// Build a command with profile, key, and byte array
    static func buildCommand(_ cmd: Command, profileId: Int, keyId: Int, bytes: Data) -> Data {
        let prefix = "\(commandHeader)\0\(cmd.rawValue)\(profileId).\(keyId):"
        var data = Data(prefix.utf8)
        data.append(bytes)
        if data.count > 3 {
            data[3] = UInt8(prefix.count - 4 + bytes.count)
        }
        // Append newline terminator
        data.append(0x0A)
        return data
    }

    // MARK: - PC Stats Protocol

    /// Build PC stats packet
    /// Format: "pcs" + 2-byte length (big endian) + JSON
    static func buildStatsPacket(json: String) -> Data {
        let jsonData = Data(json.utf8)
        let length = jsonData.count

        var packet = Data()
        packet.append(contentsOf: statsHeader.utf8)
        packet.append(UInt8((length >> 8) & 0xFF))  // High byte
        packet.append(UInt8(length & 0xFF))          // Low byte
        packet.append(jsonData)

        return packet
    }

    // MARK: - Response Parsing

    struct ParsedResponse {
        let type: Response?
        let content: String
        let profileId: Int?
        let keyId: Int?
    }

    /// Parse a response line from the device
    static func parseResponse(_ line: String) -> ParsedResponse {
        guard !line.isEmpty else {
            return ParsedResponse(type: nil, content: "", profileId: nil, keyId: nil)
        }

        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for "X=content" format
        if trimmed.count >= 2 && trimmed[trimmed.index(trimmed.startIndex, offsetBy: 1)] == "=" {
            let typeChar = trimmed[trimmed.startIndex]
            let responseType = Response(rawValue: typeChar)
            let content = String(trimmed.dropFirst(2))
            return ParsedResponse(type: responseType, content: content, profileId: nil, keyId: nil)
        }

        // Check for "ebf.k.profileId.keyId" format (key down notification)
        if trimmed.hasPrefix(commandHeader) {
            let parts = trimmed.split(separator: ".")
            if parts.count >= 4 && parts[1] == "k" {
                let profileId = Int(parts[2])
                let keyId = Int(parts[3])
                return ParsedResponse(type: .keyDown, content: "", profileId: profileId, keyId: keyId)
            }
        }

        return ParsedResponse(type: nil, content: trimmed, profileId: nil, keyId: nil)
    }

    // MARK: - Authentication

    /// Generate HMAC-SHA256 authentication response
    /// Based on decompiled Device.Authenticate method
    static func generateAuthResponse(deviceId: String, challenge: String) -> String? {
        // Key is derived from device ID
        guard let keyData = deviceId.data(using: .utf8),
              let messageData = challenge.data(using: .utf8) else {
            return nil
        }

        var hmac = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        keyData.withUnsafeBytes { keyBytes in
            messageData.withUnsafeBytes { messageBytes in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256),
                       keyBytes.baseAddress, keyData.count,
                       messageBytes.baseAddress, messageData.count,
                       &hmac)
            }
        }

        return hmac.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Serial Port Constants

extension NexProtocol {
    static let baudRate: Int = 460800
    static let dataBits: Int = 8
    static let stopBits: Int = 1
    static let parity: Int = 0  // None
}
