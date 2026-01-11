import Foundation
import AppKit
import Carbon.HIToolbox

/// Executes key actions using macOS APIs
/// Uses CGEvent for keyboard/mouse simulation, NSWorkspace for apps/URLs
actor ActionExecutor {
    static let shared = ActionExecutor()

    private init() {}

    // MARK: - Public API

    /// Execute a list of actions sequentially
    func execute(_ actions: [KeyAction]) async {
        for action in actions {
            await execute(action)
        }
    }

    /// Execute a single action
    func execute(_ action: KeyAction) async {
        switch action.type {
        case .shortcut:
            executeShortcut(action.parameter)
        case .textInput:
            executeTextInput(action.parameter)
        case .mediaControl:
            executeMediaControl(action.parameter)
        case .delay:
            await executeDelay(action.parameter)
        case .launchApp:
            executeLaunchApp(action.parameter)
        case .accessWebsite:
            executeOpenURL(action.parameter)
        case .openFolder:
            executeOpenFolder(action.parameter)
        case .command:
            executeCommand(action.parameter)
        case .mouseClick:
            executeMouseClick(action.parameter)
        case .mouseMove:
            executeMouseMove(action.parameter)
        case .functionKey:
            executeFunctionKey(action.parameter)
        case .changeProfile:
            await executeChangeProfile(action.parameter)
        case .controlAction:
            executeControlAction(action.parameter)
        }
    }

    // MARK: - Keyboard Shortcut

    private func executeShortcut(_ parameter: String) {
        let parts = parameter.uppercased().split(separator: " ").map(String.init)
        guard !parts.isEmpty else { return }

        var modifiers: CGEventFlags = []
        var keyCode: CGKeyCode?

        for part in parts {
            switch part {
            case "CONTROL", "CTRL":
                modifiers.insert(.maskControl)
            case "SHIFT":
                modifiers.insert(.maskShift)
            case "ALT", "OPTION":
                modifiers.insert(.maskAlternate)
            case "COMMAND", "CMD", "WINDOWS", "WIN":
                modifiers.insert(.maskCommand)
            default:
                // This is the main key
                keyCode = keyCodeForString(part)
            }
        }

        guard let code = keyCode else {
            print("ActionExecutor: Unknown key in shortcut: \(parameter)")
            return
        }

        pressKey(code, modifiers: modifiers)
    }

    // MARK: - Text Input

    private func executeTextInput(_ parameter: String) {
        var text = parameter
        var pressEnter = false

        // Check for ENTER suffix
        if text.uppercased().hasSuffix(" ENTER") {
            text = String(text.dropLast(6))
            pressEnter = true
        }

        // Type each character
        typeString(text)

        if pressEnter {
            pressKey(CGKeyCode(kVK_Return))
        }
    }

    // MARK: - Media Control

    private func executeMediaControl(_ parameter: String) {
        let keyCode: Int32
        switch parameter.uppercased() {
        case "MK_PP":
            keyCode = NX_KEYTYPE_PLAY
        case "MK_NEXT":
            keyCode = NX_KEYTYPE_NEXT
        case "MK_PREV":
            keyCode = NX_KEYTYPE_PREVIOUS
        case "MK_STOP":
            // macOS doesn't have a dedicated stop key, use play/pause
            keyCode = NX_KEYTYPE_PLAY
        case "MK_MUTE":
            keyCode = NX_KEYTYPE_MUTE
        case "MK_VOLUP":
            keyCode = NX_KEYTYPE_SOUND_UP
        case "MK_VOLDOWN":
            keyCode = NX_KEYTYPE_SOUND_DOWN
        default:
            print("ActionExecutor: Unknown media control: \(parameter)")
            return
        }

        pressMediaKey(keyCode)
    }

    // MARK: - Delay

    private func executeDelay(_ parameter: String) async {
        guard let ms = Int(parameter) else {
            print("ActionExecutor: Invalid delay value: \(parameter)")
            return
        }
        try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
    }

    // MARK: - Launch App

    private func executeLaunchApp(_ parameter: String) {
        let path = parameter.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return }

        // Try as bundle identifier first
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: path) {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
            return
        }

        // Try as file path
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return
        }

        // Try to find app by name
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.\(path)") {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: - Open URL

    private func executeOpenURL(_ parameter: String) {
        var urlString = parameter.trimmingCharacters(in: .whitespaces)

        // Add https:// if no scheme
        if !urlString.contains("://") {
            urlString = "https://\(urlString)"
        }

        guard let url = URL(string: urlString) else {
            print("ActionExecutor: Invalid URL: \(parameter)")
            return
        }

        NSWorkspace.shared.open(url)
    }

    // MARK: - Open Folder

    private func executeOpenFolder(_ parameter: String) {
        let path = parameter.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return }

        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }

    // MARK: - Run Command

    private func executeCommand(_ parameter: String) {
        let command = parameter.trimmingCharacters(in: .whitespaces)
        guard !command.isEmpty else { return }

        // Run in Terminal
        let script = """
        tell application "Terminal"
            activate
            do script "\(command.replacingOccurrences(of: "\"", with: "\\\""))"
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                print("ActionExecutor: AppleScript error: \(error)")
            }
        }
    }

    // MARK: - Mouse Click

    private func executeMouseClick(_ parameter: String) {
        let currentLocation = NSEvent.mouseLocation
        let screenHeight = NSScreen.main?.frame.height ?? 1080
        let point = CGPoint(x: currentLocation.x, y: screenHeight - currentLocation.y)

        switch parameter.uppercased() {
        case "LMOUSE":
            mouseClick(at: point, button: .left)
        case "LLMOUSE":
            mouseClick(at: point, button: .left)
            mouseClick(at: point, button: .left)
        case "RMOUSE":
            mouseClick(at: point, button: .right)
        default:
            print("ActionExecutor: Unknown mouse click type: \(parameter)")
        }
    }

    // MARK: - Mouse Move

    private func executeMouseMove(_ parameter: String) {
        let parts = parameter.uppercased().split(separator: " ").map(String.init)
        guard parts.count >= 2,
              let x = Int(parts[0]),
              let y = Int(parts[1]) else {
            print("ActionExecutor: Invalid mouse move parameters: \(parameter)")
            return
        }

        let drag = parts.count >= 3 && parts[2] == "DRAG"
        let point = CGPoint(x: x, y: y)

        if drag {
            mouseDrag(to: point)
        } else {
            mouseMove(to: point)
        }
    }

    // MARK: - Function Key

    private func executeFunctionKey(_ parameter: String) {
        guard let keyCode = functionKeyCode(for: parameter.uppercased()) else {
            print("ActionExecutor: Unknown function key: \(parameter)")
            return
        }
        pressKey(keyCode)
    }

    // MARK: - Change Profile

    private func executeChangeProfile(_ parameter: String) async {
        guard let profileId = Int(parameter) else {
            print("ActionExecutor: Invalid profile ID: \(parameter)")
            return
        }

        // Send profile change command to device via DeviceManager
        await MainActor.run {
            DeviceManager.shared.changeProfile(to: profileId)
        }
    }

    // MARK: - Control Action

    private func executeControlAction(_ parameter: String) {
        switch parameter.uppercased() {
        case "CC_CALCULATOR":
            executeLaunchApp("/System/Applications/Calculator.app")
        case "CC_BROWSER":
            executeLaunchApp("/Applications/Safari.app")
        case "CC_EMAIL":
            executeLaunchApp("/System/Applications/Mail.app")
        case "CC_SEARCH":
            // Spotlight search
            pressKey(CGKeyCode(kVK_Space), modifiers: .maskCommand)
        case "CC_HOME":
            pressKey(keyCodeForString("H"), modifiers: [.maskCommand, .maskShift])
        case "CC_BACK":
            pressKey(CGKeyCode(kVK_LeftArrow), modifiers: .maskCommand)
        case "CC_FORWARD":
            pressKey(CGKeyCode(kVK_RightArrow), modifiers: .maskCommand)
        case "CC_BR_STOP":
            pressKey(keyCodeForString("."), modifiers: .maskCommand)
        case "CC_REFRESH":
            pressKey(keyCodeForString("R"), modifiers: .maskCommand)
        case "CC_BOOKMARKS":
            pressKey(keyCodeForString("B"), modifiers: [.maskCommand, .maskAlternate])
        default:
            print("ActionExecutor: Unknown control action: \(parameter)")
        }
    }

    // MARK: - Low-level Key Simulation

    private func pressKey(_ keyCode: CGKeyCode, modifiers: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)

        // Key down
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            keyDown.flags = modifiers
            keyDown.post(tap: .cghidEventTap)
        }

        // Small delay
        usleep(10000)  // 10ms

        // Key up
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            keyUp.flags = modifiers
            keyUp.post(tap: .cghidEventTap)
        }
    }

    private func pressMediaKey(_ key: Int32) {
        // Create HID system event for media keys
        func postMediaKeyEvent(_ key: Int32, down: Bool) {
            let flags = NSEvent.ModifierFlags(rawValue: (down ? 0xa00 : 0xb00))
            let data1 = Int((key << 16) | (down ? 0xa00 : 0xb00))

            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            )

            event?.cgEvent?.post(tap: .cghidEventTap)
        }

        postMediaKeyEvent(key, down: true)
        postMediaKeyEvent(key, down: false)
    }

    private func typeString(_ string: String) {
        let source = CGEventSource(stateID: .hidSystemState)

        for char in string {
            if let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                var unicodeChar = Array(String(char).utf16)
                event.keyboardSetUnicodeString(stringLength: unicodeChar.count, unicodeString: &unicodeChar)
                event.post(tap: .cghidEventTap)
            }

            if let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                event.post(tap: .cghidEventTap)
            }

            usleep(5000)  // 5ms between characters
        }
    }

    private func mouseClick(at point: CGPoint, button: CGMouseButton) {
        let source = CGEventSource(stateID: .hidSystemState)
        let downType: CGEventType = button == .left ? .leftMouseDown : .rightMouseDown
        let upType: CGEventType = button == .left ? .leftMouseUp : .rightMouseUp

        if let mouseDown = CGEvent(mouseEventSource: source, mouseType: downType, mouseCursorPosition: point, mouseButton: button) {
            mouseDown.post(tap: .cghidEventTap)
        }

        usleep(10000)

        if let mouseUp = CGEvent(mouseEventSource: source, mouseType: upType, mouseCursorPosition: point, mouseButton: button) {
            mouseUp.post(tap: .cghidEventTap)
        }
    }

    private func mouseMove(to point: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        if let event = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) {
            event.post(tap: .cghidEventTap)
        }
    }

    private func mouseDrag(to point: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        let currentLocation = NSEvent.mouseLocation
        let screenHeight = NSScreen.main?.frame.height ?? 1080
        let startPoint = CGPoint(x: currentLocation.x, y: screenHeight - currentLocation.y)

        // Mouse down at current position
        if let mouseDown = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: startPoint, mouseButton: .left) {
            mouseDown.post(tap: .cghidEventTap)
        }

        usleep(10000)

        // Drag to target
        if let drag = CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: point, mouseButton: .left) {
            drag.post(tap: .cghidEventTap)
        }

        usleep(10000)

        // Mouse up at target
        if let mouseUp = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) {
            mouseUp.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Key Code Mapping

    private func keyCodeForString(_ key: String) -> CGKeyCode {
        // Single character keys
        if key.count == 1 {
            return keyCodeForCharacter(Character(key))
        }

        // Named keys
        switch key.uppercased() {
        case "RETURN", "ENTER": return CGKeyCode(kVK_Return)
        case "TAB": return CGKeyCode(kVK_Tab)
        case "SPACE": return CGKeyCode(kVK_Space)
        case "DELETE", "BACKSPACE": return CGKeyCode(kVK_Delete)
        case "ESCAPE", "ESC": return CGKeyCode(kVK_Escape)
        case "UP": return CGKeyCode(kVK_UpArrow)
        case "DOWN": return CGKeyCode(kVK_DownArrow)
        case "LEFT": return CGKeyCode(kVK_LeftArrow)
        case "RIGHT": return CGKeyCode(kVK_RightArrow)
        case "HOME": return CGKeyCode(kVK_Home)
        case "END": return CGKeyCode(kVK_End)
        case "PAGEUP": return CGKeyCode(kVK_PageUp)
        case "PAGEDOWN": return CGKeyCode(kVK_PageDown)
        case "F1": return CGKeyCode(kVK_F1)
        case "F2": return CGKeyCode(kVK_F2)
        case "F3": return CGKeyCode(kVK_F3)
        case "F4": return CGKeyCode(kVK_F4)
        case "F5": return CGKeyCode(kVK_F5)
        case "F6": return CGKeyCode(kVK_F6)
        case "F7": return CGKeyCode(kVK_F7)
        case "F8": return CGKeyCode(kVK_F8)
        case "F9": return CGKeyCode(kVK_F9)
        case "F10": return CGKeyCode(kVK_F10)
        case "F11": return CGKeyCode(kVK_F11)
        case "F12": return CGKeyCode(kVK_F12)
        default:
            return CGKeyCode(kVK_ANSI_A)  // Fallback
        }
    }

    private func keyCodeForCharacter(_ char: Character) -> CGKeyCode {
        let c = char.uppercased().first ?? char
        switch c {
        case "A": return CGKeyCode(kVK_ANSI_A)
        case "B": return CGKeyCode(kVK_ANSI_B)
        case "C": return CGKeyCode(kVK_ANSI_C)
        case "D": return CGKeyCode(kVK_ANSI_D)
        case "E": return CGKeyCode(kVK_ANSI_E)
        case "F": return CGKeyCode(kVK_ANSI_F)
        case "G": return CGKeyCode(kVK_ANSI_G)
        case "H": return CGKeyCode(kVK_ANSI_H)
        case "I": return CGKeyCode(kVK_ANSI_I)
        case "J": return CGKeyCode(kVK_ANSI_J)
        case "K": return CGKeyCode(kVK_ANSI_K)
        case "L": return CGKeyCode(kVK_ANSI_L)
        case "M": return CGKeyCode(kVK_ANSI_M)
        case "N": return CGKeyCode(kVK_ANSI_N)
        case "O": return CGKeyCode(kVK_ANSI_O)
        case "P": return CGKeyCode(kVK_ANSI_P)
        case "Q": return CGKeyCode(kVK_ANSI_Q)
        case "R": return CGKeyCode(kVK_ANSI_R)
        case "S": return CGKeyCode(kVK_ANSI_S)
        case "T": return CGKeyCode(kVK_ANSI_T)
        case "U": return CGKeyCode(kVK_ANSI_U)
        case "V": return CGKeyCode(kVK_ANSI_V)
        case "W": return CGKeyCode(kVK_ANSI_W)
        case "X": return CGKeyCode(kVK_ANSI_X)
        case "Y": return CGKeyCode(kVK_ANSI_Y)
        case "Z": return CGKeyCode(kVK_ANSI_Z)
        case "0": return CGKeyCode(kVK_ANSI_0)
        case "1": return CGKeyCode(kVK_ANSI_1)
        case "2": return CGKeyCode(kVK_ANSI_2)
        case "3": return CGKeyCode(kVK_ANSI_3)
        case "4": return CGKeyCode(kVK_ANSI_4)
        case "5": return CGKeyCode(kVK_ANSI_5)
        case "6": return CGKeyCode(kVK_ANSI_6)
        case "7": return CGKeyCode(kVK_ANSI_7)
        case "8": return CGKeyCode(kVK_ANSI_8)
        case "9": return CGKeyCode(kVK_ANSI_9)
        case "-": return CGKeyCode(kVK_ANSI_Minus)
        case "=": return CGKeyCode(kVK_ANSI_Equal)
        case "[": return CGKeyCode(kVK_ANSI_LeftBracket)
        case "]": return CGKeyCode(kVK_ANSI_RightBracket)
        case ";": return CGKeyCode(kVK_ANSI_Semicolon)
        case "'": return CGKeyCode(kVK_ANSI_Quote)
        case "\\": return CGKeyCode(kVK_ANSI_Backslash)
        case ",": return CGKeyCode(kVK_ANSI_Comma)
        case ".": return CGKeyCode(kVK_ANSI_Period)
        case "/": return CGKeyCode(kVK_ANSI_Slash)
        case "`": return CGKeyCode(kVK_ANSI_Grave)
        default: return CGKeyCode(kVK_ANSI_A)
        }
    }

    private func functionKeyCode(for key: String) -> CGKeyCode? {
        switch key {
        case "F1": return CGKeyCode(kVK_F1)
        case "F2": return CGKeyCode(kVK_F2)
        case "F3": return CGKeyCode(kVK_F3)
        case "F4": return CGKeyCode(kVK_F4)
        case "F5": return CGKeyCode(kVK_F5)
        case "F6": return CGKeyCode(kVK_F6)
        case "F7": return CGKeyCode(kVK_F7)
        case "F8": return CGKeyCode(kVK_F8)
        case "F9": return CGKeyCode(kVK_F9)
        case "F10": return CGKeyCode(kVK_F10)
        case "F11": return CGKeyCode(kVK_F11)
        case "F12": return CGKeyCode(kVK_F12)
        case "F13": return CGKeyCode(kVK_F13)
        case "F14": return CGKeyCode(kVK_F14)
        case "F15": return CGKeyCode(kVK_F15)
        case "TAB": return CGKeyCode(kVK_Tab)
        case "SPACE": return CGKeyCode(kVK_Space)
        case "ENTER", "RETURN": return CGKeyCode(kVK_Return)
        case "BACKSPACE", "DELETE": return CGKeyCode(kVK_Delete)
        case "FORWARDDELETE": return CGKeyCode(kVK_ForwardDelete)
        case "HOME": return CGKeyCode(kVK_Home)
        case "END": return CGKeyCode(kVK_End)
        case "PAGEUP": return CGKeyCode(kVK_PageUp)
        case "PAGEDOWN": return CGKeyCode(kVK_PageDown)
        case "UP": return CGKeyCode(kVK_UpArrow)
        case "DOWN": return CGKeyCode(kVK_DownArrow)
        case "LEFT": return CGKeyCode(kVK_LeftArrow)
        case "RIGHT": return CGKeyCode(kVK_RightArrow)
        case "ESCAPE", "ESC": return CGKeyCode(kVK_Escape)
        case "NUMLOCK": return CGKeyCode(kVK_ANSI_KeypadClear)
        case "KP_0": return CGKeyCode(kVK_ANSI_Keypad0)
        case "KP_1": return CGKeyCode(kVK_ANSI_Keypad1)
        case "KP_2": return CGKeyCode(kVK_ANSI_Keypad2)
        case "KP_3": return CGKeyCode(kVK_ANSI_Keypad3)
        case "KP_4": return CGKeyCode(kVK_ANSI_Keypad4)
        case "KP_5": return CGKeyCode(kVK_ANSI_Keypad5)
        case "KP_6": return CGKeyCode(kVK_ANSI_Keypad6)
        case "KP_7": return CGKeyCode(kVK_ANSI_Keypad7)
        case "KP_8": return CGKeyCode(kVK_ANSI_Keypad8)
        case "KP_9": return CGKeyCode(kVK_ANSI_Keypad9)
        case "KP_ENTER": return CGKeyCode(kVK_ANSI_KeypadEnter)
        case "KP_DOT", "KP_DECIMAL": return CGKeyCode(kVK_ANSI_KeypadDecimal)
        case "KP_PLUS": return CGKeyCode(kVK_ANSI_KeypadPlus)
        case "KP_MINUS": return CGKeyCode(kVK_ANSI_KeypadMinus)
        case "KP_ASTERISK", "KP_MULTIPLY": return CGKeyCode(kVK_ANSI_KeypadMultiply)
        case "KP_SLASH", "KP_DIVIDE": return CGKeyCode(kVK_ANSI_KeypadDivide)
        case "KP_EQUAL": return CGKeyCode(kVK_ANSI_KeypadEquals)
        case "PRINTSCREEN": return CGKeyCode(kVK_F13)  // macOS uses F13 for print screen
        case "INSERT": return CGKeyCode(kVK_Help)  // macOS uses Help key
        default: return nil
        }
    }
}

// MARK: - Media Key Constants
// These are from IOKit/hidsystem/ev_keymap.h
private let NX_KEYTYPE_PLAY: Int32 = 16
private let NX_KEYTYPE_NEXT: Int32 = 17
private let NX_KEYTYPE_PREVIOUS: Int32 = 18
private let NX_KEYTYPE_MUTE: Int32 = 7
private let NX_KEYTYPE_SOUND_UP: Int32 = 0
private let NX_KEYTYPE_SOUND_DOWN: Int32 = 1
