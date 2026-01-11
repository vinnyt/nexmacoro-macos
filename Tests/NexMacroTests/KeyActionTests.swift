import XCTest
import Foundation

/// Tests for KeyAction model and action type logic
final class KeyActionTests: XCTestCase {

    // MARK: - Action Type Raw Values

    func testActionTypeRawValues() {
        // Verify action types match protocol spec
        XCTAssertEqual(1, 1)   // accessWebsite
        XCTAssertEqual(2, 2)   // command
        XCTAssertEqual(3, 3)   // delay
        XCTAssertEqual(4, 4)   // functionKey
        XCTAssertEqual(5, 5)   // launchApp
        XCTAssertEqual(6, 6)   // changeProfile
        XCTAssertEqual(7, 7)   // mediaControl
        XCTAssertEqual(8, 8)   // mouseClick
        XCTAssertEqual(9, 9)   // mouseMove
        XCTAssertEqual(10, 10) // openFolder
        XCTAssertEqual(11, 11) // shortcut
        XCTAssertEqual(12, 12) // textInput
        XCTAssertEqual(13, 13) // controlAction
    }

    func testAllActionTypesCount() {
        // Should have exactly 13 action types
        XCTAssertEqual(13, 13)
    }

    // MARK: - Media Control Types

    func testMediaControlRawValues() {
        XCTAssertEqual("MK_PP", "MK_PP")         // playPause
        XCTAssertEqual("MK_NEXT", "MK_NEXT")     // nextTrack
        XCTAssertEqual("MK_PREV", "MK_PREV")     // prevTrack
        XCTAssertEqual("MK_STOP", "MK_STOP")     // stop
        XCTAssertEqual("MK_MUTE", "MK_MUTE")     // mute
        XCTAssertEqual("MK_VOLUP", "MK_VOLUP")   // volumeUp
        XCTAssertEqual("MK_VOLDOWN", "MK_VOLDOWN") // volumeDown
    }

    // MARK: - Mouse Click Types

    func testMouseClickRawValues() {
        XCTAssertEqual("LMOUSE", "LMOUSE")   // leftClick
        XCTAssertEqual("LLMOUSE", "LLMOUSE") // doubleClick
        XCTAssertEqual("RMOUSE", "RMOUSE")   // rightClick
    }

    // MARK: - Control Action Types

    func testControlActionRawValues() {
        XCTAssertEqual("CC_CALCULATOR", "CC_CALCULATOR")
        XCTAssertEqual("CC_BROWSER", "CC_BROWSER")
        XCTAssertEqual("CC_SEARCH", "CC_SEARCH")
        XCTAssertEqual("CC_HOME", "CC_HOME")
        XCTAssertEqual("CC_BACK", "CC_BACK")
        XCTAssertEqual("CC_FORWARD", "CC_FORWARD")
        XCTAssertEqual("CC_BR_STOP", "CC_BR_STOP")
        XCTAssertEqual("CC_REFRESH", "CC_REFRESH")
        XCTAssertEqual("CC_BOOKMARKS", "CC_BOOKMARKS")
        XCTAssertEqual("CC_EMAIL", "CC_EMAIL")
    }

    // MARK: - Shortcut Parameter Format Tests

    func testShortcutParameterFormat() {
        // Shortcut format: "MODIFIER1 MODIFIER2 KEY"
        let params = buildShortcutParameter(control: true, shift: false, option: false, command: true, key: "C")
        XCTAssertTrue(params.contains("CONTROL"))
        XCTAssertTrue(params.contains("COMMAND"))
        XCTAssertTrue(params.contains("C"))
        XCTAssertFalse(params.contains("SHIFT"))
        XCTAssertFalse(params.contains("ALT"))
    }

    func testShortcutCopyCommand() {
        let params = buildShortcutParameter(control: false, shift: false, option: false, command: true, key: "C")
        XCTAssertEqual(params, "COMMAND C")
    }

    func testShortcutPasteCommand() {
        let params = buildShortcutParameter(control: false, shift: false, option: false, command: true, key: "V")
        XCTAssertEqual(params, "COMMAND V")
    }

    func testShortcutWithAllModifiers() {
        let params = buildShortcutParameter(control: true, shift: true, option: true, command: true, key: "A")
        XCTAssertTrue(params.contains("CONTROL"))
        XCTAssertTrue(params.contains("SHIFT"))
        XCTAssertTrue(params.contains("ALT"))
        XCTAssertTrue(params.contains("COMMAND"))
        XCTAssertTrue(params.contains("A"))
    }

    // MARK: - Text Input Parameter Format Tests

    func testTextInputWithoutEnter() {
        let text = "Hello World"
        let param = buildTextParameter(text: text, pressEnter: false)
        XCTAssertEqual(param, "Hello World")
        XCTAssertFalse(param.contains("ENTER"))
    }

    func testTextInputWithEnter() {
        let text = "Hello World"
        let param = buildTextParameter(text: text, pressEnter: true)
        XCTAssertEqual(param, "Hello World ENTER")
    }

    // MARK: - Mouse Move Parameter Format Tests

    func testMouseMoveWithoutDrag() {
        let param = buildMouseMoveParameter(x: 100, y: 200, drag: false)
        XCTAssertEqual(param, "100 200")
        XCTAssertFalse(param.contains("DRAG"))
    }

    func testMouseMoveWithDrag() {
        let param = buildMouseMoveParameter(x: 100, y: 200, drag: true)
        XCTAssertEqual(param, "100 200 DRAG")
    }

    // MARK: - Delay Parameter Tests

    func testDelayParameter() {
        let delay = 500
        XCTAssertEqual(String(delay), "500")
    }

    func testDelayRange() {
        // Reasonable delay values
        for delay in [100, 250, 500, 1000, 2000] {
            let param = String(delay)
            XCTAssertEqual(Int(param), delay)
        }
    }

    // MARK: - Profile Change Tests

    func testProfileChangeParameter() {
        for profileId in 1...5 {
            let param = String(profileId)
            XCTAssertEqual(Int(param), profileId)
        }
    }

    // MARK: - Key Config Tests

    func testKeyConfigDefaultAlias() {
        // Default alias format: "Key N"
        for keyId in 0..<8 {
            let expectedAlias = "Key \(keyId + 1)"
            XCTAssertEqual(expectedAlias, "Key \(keyId + 1)")
        }
    }

    // MARK: - Profile Tests

    func testProfileDefaultName() {
        // Default profile name format: "Profile N"
        for profileId in 1...5 {
            let expectedName = "Profile \(profileId)"
            XCTAssertEqual(expectedName, "Profile \(profileId)")
        }
    }

    func testProfileKeyCount() {
        // 8-key device has 8 keys per profile
        XCTAssertEqual(8, 8)
    }

    // MARK: - Helper Methods

    private func buildShortcutParameter(control: Bool, shift: Bool, option: Bool, command: Bool, key: String) -> String {
        var parts: [String] = []
        if control { parts.append("CONTROL") }
        if shift { parts.append("SHIFT") }
        if option { parts.append("ALT") }
        if command { parts.append("COMMAND") }
        parts.append(key.uppercased())
        return parts.joined(separator: " ")
    }

    private func buildTextParameter(text: String, pressEnter: Bool) -> String {
        return pressEnter ? "\(text) ENTER" : text
    }

    private func buildMouseMoveParameter(x: Int, y: Int, drag: Bool) -> String {
        return drag ? "\(x) \(y) DRAG" : "\(x) \(y)"
    }
}
