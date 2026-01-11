import Foundation

/// All supported action types for macro keys
/// Based on Windows NexMacro app action types
enum KeyActionType: Int, Codable, CaseIterable {
    case accessWebsite = 1      // Open URL in browser
    case command = 2            // Run shell command
    case delay = 3              // Wait milliseconds
    case functionKey = 4        // F1-F12, special keys
    case launchApp = 5          // Launch application
    case changeProfile = 6      // Switch to profile 1-5
    case mediaControl = 7       // Play/pause, volume, etc.
    case mouseClick = 8         // Left/right/double click
    case mouseMove = 9          // Move cursor to X,Y
    case openFolder = 10        // Open folder in Finder
    case shortcut = 11          // Keyboard shortcut (Cmd+C, etc.)
    case textInput = 12         // Type text string
    case controlAction = 13     // Browser/system controls

    var displayName: String {
        switch self {
        case .accessWebsite: return "Open Website"
        case .command: return "Run Command"
        case .delay: return "Delay"
        case .functionKey: return "Function Key"
        case .launchApp: return "Launch Application"
        case .changeProfile: return "Change Profile"
        case .mediaControl: return "Media Control"
        case .mouseClick: return "Mouse Click"
        case .mouseMove: return "Mouse Move"
        case .openFolder: return "Open Folder"
        case .shortcut: return "Keyboard Shortcut"
        case .textInput: return "Type Text"
        case .controlAction: return "System Control"
        }
    }
}

/// Media control options
enum MediaControlType: String, Codable, CaseIterable {
    case playPause = "MK_PP"
    case nextTrack = "MK_NEXT"
    case prevTrack = "MK_PREV"
    case stop = "MK_STOP"
    case mute = "MK_MUTE"
    case volumeUp = "MK_VOLUP"
    case volumeDown = "MK_VOLDOWN"

    var displayName: String {
        switch self {
        case .playPause: return "Play/Pause"
        case .nextTrack: return "Next Track"
        case .prevTrack: return "Previous Track"
        case .stop: return "Stop"
        case .mute: return "Mute"
        case .volumeUp: return "Volume Up"
        case .volumeDown: return "Volume Down"
        }
    }
}

/// Mouse click types
enum MouseClickType: String, Codable, CaseIterable {
    case leftClick = "LMOUSE"
    case doubleClick = "LLMOUSE"
    case rightClick = "RMOUSE"

    var displayName: String {
        switch self {
        case .leftClick: return "Left Click"
        case .doubleClick: return "Double Click"
        case .rightClick: return "Right Click"
        }
    }
}

/// System/browser control actions
enum ControlActionType: String, Codable, CaseIterable {
    case calculator = "CC_CALCULATOR"
    case browser = "CC_BROWSER"
    case search = "CC_SEARCH"
    case home = "CC_HOME"
    case back = "CC_BACK"
    case forward = "CC_FORWARD"
    case stop = "CC_BR_STOP"
    case refresh = "CC_REFRESH"
    case bookmarks = "CC_BOOKMARKS"
    case email = "CC_EMAIL"

    var displayName: String {
        switch self {
        case .calculator: return "Calculator"
        case .browser: return "Browser"
        case .search: return "Search"
        case .home: return "Browser Home"
        case .back: return "Browser Back"
        case .forward: return "Browser Forward"
        case .stop: return "Browser Stop"
        case .refresh: return "Browser Refresh"
        case .bookmarks: return "Bookmarks"
        case .email: return "Email"
        }
    }
}

/// Modifier keys for shortcuts
struct ModifierKeys: OptionSet, Codable {
    let rawValue: Int

    static let control = ModifierKeys(rawValue: 1 << 0)
    static let shift = ModifierKeys(rawValue: 1 << 1)
    static let option = ModifierKeys(rawValue: 1 << 2)  // Alt on Windows
    static let command = ModifierKeys(rawValue: 1 << 3) // Windows key

    static let none: ModifierKeys = []
}

/// A single action that can be executed
struct KeyAction: Codable, Identifiable, Equatable {
    var id = UUID()
    var type: KeyActionType
    var parameter: String

    init(type: KeyActionType, parameter: String = "") {
        self.type = type
        self.parameter = parameter
    }

    // MARK: - Convenience initializers

    /// Create a keyboard shortcut action
    static func shortcut(modifiers: ModifierKeys, key: String) -> KeyAction {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("CONTROL") }
        if modifiers.contains(.shift) { parts.append("SHIFT") }
        if modifiers.contains(.option) { parts.append("ALT") }
        if modifiers.contains(.command) { parts.append("COMMAND") }
        parts.append(key.uppercased())
        return KeyAction(type: .shortcut, parameter: parts.joined(separator: " "))
    }

    /// Create a media control action
    static func media(_ control: MediaControlType) -> KeyAction {
        KeyAction(type: .mediaControl, parameter: control.rawValue)
    }

    /// Create a text input action
    static func text(_ text: String, pressEnter: Bool = false) -> KeyAction {
        let param = pressEnter ? "\(text) ENTER" : text
        return KeyAction(type: .textInput, parameter: param)
    }

    /// Create a delay action
    static func delay(milliseconds: Int) -> KeyAction {
        KeyAction(type: .delay, parameter: String(milliseconds))
    }

    /// Create a mouse click action
    static func mouseClick(_ clickType: MouseClickType) -> KeyAction {
        KeyAction(type: .mouseClick, parameter: clickType.rawValue)
    }

    /// Create a mouse move action
    static func mouseMove(x: Int, y: Int, drag: Bool = false) -> KeyAction {
        let param = drag ? "\(x) \(y) DRAG" : "\(x) \(y)"
        return KeyAction(type: .mouseMove, parameter: param)
    }

    /// Create a launch app action
    static func launchApp(path: String) -> KeyAction {
        KeyAction(type: .launchApp, parameter: path)
    }

    /// Create an open URL action
    static func openURL(_ url: String) -> KeyAction {
        KeyAction(type: .accessWebsite, parameter: url)
    }

    /// Create an open folder action
    static func openFolder(_ path: String) -> KeyAction {
        KeyAction(type: .openFolder, parameter: path)
    }

    /// Create a run command action
    static func runCommand(_ command: String) -> KeyAction {
        KeyAction(type: .command, parameter: command)
    }

    /// Create a change profile action
    static func changeProfile(_ profileId: Int) -> KeyAction {
        KeyAction(type: .changeProfile, parameter: String(profileId))
    }

    /// Create a function key action
    static func functionKey(_ key: String) -> KeyAction {
        KeyAction(type: .functionKey, parameter: key.uppercased())
    }

    /// Create a control action
    static func control(_ action: ControlActionType) -> KeyAction {
        KeyAction(type: .controlAction, parameter: action.rawValue)
    }
}

/// Configuration for a single key on the device
struct KeyConfig: Codable, Identifiable {
    var id: Int  // Key ID (0-7 for 8-key device)
    var alias: String  // Display name for the key
    var actions: [KeyAction]  // Actions to execute when pressed
    var hidMode: Bool  // Whether to use HID mode

    init(id: Int, alias: String = "", actions: [KeyAction] = [], hidMode: Bool = false) {
        self.id = id
        self.alias = alias
        self.actions = actions
        self.hidMode = hidMode
    }

    /// Default key config with no actions
    static func empty(id: Int) -> KeyConfig {
        KeyConfig(id: id, alias: "Key \(id + 1)")
    }
}

/// A profile containing configurations for all keys
struct Profile: Codable, Identifiable {
    var id: Int  // Profile ID (1-5)
    var name: String
    var keys: [KeyConfig]

    init(id: Int, name: String? = nil) {
        self.id = id
        self.name = name ?? "Profile \(id)"
        self.keys = (0..<8).map { KeyConfig.empty(id: $0) }
    }

    /// Get key config by ID
    func key(_ keyId: Int) -> KeyConfig? {
        keys.first { $0.id == keyId }
    }

    /// Update key config
    mutating func setKey(_ keyId: Int, config: KeyConfig) {
        if let index = keys.firstIndex(where: { $0.id == keyId }) {
            keys[index] = config
        }
    }
}
