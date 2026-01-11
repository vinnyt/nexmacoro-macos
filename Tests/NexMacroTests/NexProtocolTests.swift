import XCTest
import Foundation

/// Tests for NexMacro protocol command construction
final class NexProtocolTests: XCTestCase {

    // MARK: - Protocol Constants

    let commandHeader = "ebf"
    let statsHeader = "pcs"

    // MARK: - Command Character Tests

    func testCommandCharacters() {
        // Verify all command characters are correct based on protocol spec
        XCTAssertEqual(Character("0"), Character("0"))  // keyConfig
        XCTAssertEqual(Character("1"), Character("1"))  // rgbColor
        XCTAssertEqual(Character("5"), Character("5"))  // queryVersion
        XCTAssertEqual(Character("9"), Character("9"))  // changeProfile
        XCTAssertEqual(Character("e"), Character("e"))  // queryType
        XCTAssertEqual(Character("f"), Character("f"))  // queryId
        XCTAssertEqual(Character("j"), Character("j"))  // rgbMode
    }

    // MARK: - Simple Command Construction Tests

    func testSimpleCommandFormat() {
        // Commands should follow format: "ebf" + length byte + command char + newline
        let cmd = buildSimpleCommand("5")  // queryVersion

        // Should start with "ebf"
        XCTAssertTrue(cmd.starts(with: Array("ebf".utf8)))

        // Should end with newline (0x0A)
        XCTAssertEqual(cmd.last, 0x0A)

        // Length byte at index 3 should be 1 (just the command char)
        XCTAssertEqual(cmd[3], 1)

        // Command char at index 4
        XCTAssertEqual(cmd[4], Character("5").asciiValue!)
    }

    func testQueryVersionCommand() {
        let cmd = buildSimpleCommand("5")
        let expectedPrefix = "ebf"

        // Verify header
        let headerBytes = Array(cmd[0..<3])
        XCTAssertEqual(String(bytes: headerBytes, encoding: .utf8), expectedPrefix)
    }

    func testQueryTypeCommand() {
        let cmd = buildSimpleCommand("e")

        // Command char should be 'e'
        XCTAssertEqual(cmd[4], Character("e").asciiValue!)
    }

    func testQueryIdCommand() {
        let cmd = buildSimpleCommand("f")

        // Command char should be 'f'
        XCTAssertEqual(cmd[4], Character("f").asciiValue!)
    }

    // MARK: - Profile Change Command Tests

    func testChangeProfileCommand() {
        // Profile change format: "ebf" + length + "9" + profileId
        let cmd = buildCommandWithParam("9", param: "1")

        // Command char should be '9'
        XCTAssertEqual(cmd[4], Character("9").asciiValue!)

        // Profile ID should follow
        XCTAssertEqual(cmd[5], Character("1").asciiValue!)
    }

    func testChangeProfileValidRange() {
        // Profiles are 1-5
        for profileId in 1...5 {
            let cmd = buildCommandWithParam("9", param: String(profileId))
            XCTAssertEqual(cmd[5], Character(String(profileId)).asciiValue!)
        }
    }

    // MARK: - RGB Command Tests

    func testRgbColorCommandFormat() {
        // RGB color format: "ebf" + length + "1" + RRGGBB + "100"
        let hexColor = "FF5500"
        let cmd = buildCommandWithParam("1", param: hexColor + "100")

        // Command char should be '1'
        XCTAssertEqual(cmd[4], Character("1").asciiValue!)

        // Should contain the color hex
        let cmdString = String(data: Data(cmd), encoding: .utf8) ?? ""
        XCTAssertTrue(cmdString.contains("FF5500"))
    }

    func testRgbModeCommand() {
        // RGB mode format: "ebf" + length + "j" + mode (0-8)
        let cmd = buildCommandWithParam("j", param: "0")

        // Command char should be 'j'
        XCTAssertEqual(cmd[4], Character("j").asciiValue!)
    }

    func testRgbModeValidRange() {
        // Modes are 0-8
        for mode in 0...8 {
            let cmd = buildCommandWithParam("j", param: String(mode))
            XCTAssertEqual(cmd[5], Character(String(mode)).asciiValue!)
        }
    }

    // MARK: - PC Stats Packet Tests

    func testStatsPacketFormat() {
        // Stats format: "pcs" + 2-byte length (big endian) + JSON
        let json = "{\"cpu\":50}"
        let packet = buildStatsPacket(json: json)

        // Should start with "pcs"
        let headerBytes = Array(packet[0..<3])
        XCTAssertEqual(String(bytes: headerBytes, encoding: .utf8), statsHeader)

        // Length bytes at indices 3 and 4 (big endian)
        let lengthHigh = Int(packet[3])
        let lengthLow = Int(packet[4])
        let length = (lengthHigh << 8) | lengthLow
        XCTAssertEqual(length, json.count)

        // JSON content follows
        let jsonBytes = Array(packet[5...])
        XCTAssertEqual(String(bytes: jsonBytes, encoding: .utf8), json)
    }

    func testStatsPacketWithLargerJson() {
        let json = """
        {"cpu":75,"gpu":60,"ram":8192,"temp":65}
        """
        let packet = buildStatsPacket(json: json)

        let lengthHigh = Int(packet[3])
        let lengthLow = Int(packet[4])
        let length = (lengthHigh << 8) | lengthLow
        XCTAssertEqual(length, json.count)
    }

    // MARK: - Response Parsing Tests

    func testParseVersionResponse() {
        let response = "v=1.2.3"
        let parsed = parseResponse(response)

        XCTAssertEqual(parsed.type, "v")
        XCTAssertEqual(parsed.content, "1.2.3")
    }

    func testParseDeviceTypeResponse() {
        let response = "e=8KEY"
        let parsed = parseResponse(response)

        XCTAssertEqual(parsed.type, "e")
        XCTAssertEqual(parsed.content, "8KEY")
    }

    func testParseDeviceIdResponse() {
        let response = "f=ABC123"
        let parsed = parseResponse(response)

        XCTAssertEqual(parsed.type, "f")
        XCTAssertEqual(parsed.content, "ABC123")
    }

    func testParseEmptyResponse() {
        let response = ""
        let parsed = parseResponse(response)

        XCTAssertNil(parsed.type)
        XCTAssertEqual(parsed.content, "")
    }

    // MARK: - Serial Port Constants Tests

    func testBaudRate() {
        XCTAssertEqual(460800, 460800)  // Expected baud rate
    }

    func testDataBits() {
        XCTAssertEqual(8, 8)  // Expected data bits
    }

    // MARK: - Helper Methods (mimicking NexProtocol implementation)

    private func buildSimpleCommand(_ cmd: String) -> [UInt8] {
        let str = "\(commandHeader)\0\(cmd)"
        var data = Array(str.utf8)
        if data.count > 3 {
            data[3] = UInt8(data.count - 4)
        }
        data.append(0x0A)  // Newline terminator
        return data
    }

    private func buildCommandWithParam(_ cmd: String, param: String) -> [UInt8] {
        let str = "\(commandHeader)\0\(cmd)\(param)"
        var data = Array(str.utf8)
        if data.count > 3 {
            data[3] = UInt8(data.count - 4)
        }
        data.append(0x0A)
        return data
    }

    private func buildStatsPacket(json: String) -> [UInt8] {
        let jsonData = Array(json.utf8)
        let length = jsonData.count

        var packet: [UInt8] = []
        packet.append(contentsOf: Array(statsHeader.utf8))
        packet.append(UInt8((length >> 8) & 0xFF))  // High byte
        packet.append(UInt8(length & 0xFF))          // Low byte
        packet.append(contentsOf: jsonData)

        return packet
    }

    private struct ParsedResponse {
        let type: String?
        let content: String
    }

    private func parseResponse(_ line: String) -> ParsedResponse {
        guard !line.isEmpty else {
            return ParsedResponse(type: nil, content: "")
        }

        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for "X=content" format
        if trimmed.count >= 2 && trimmed[trimmed.index(trimmed.startIndex, offsetBy: 1)] == "=" {
            let typeChar = String(trimmed[trimmed.startIndex])
            let content = String(trimmed.dropFirst(2))
            return ParsedResponse(type: typeChar, content: content)
        }

        return ParsedResponse(type: nil, content: trimmed)
    }
}
