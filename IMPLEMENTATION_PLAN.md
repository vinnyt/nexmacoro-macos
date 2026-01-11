# NexMacro macOS - Implementation Plan

## Current State (v1.0.0-rc)

### Core Features - COMPLETE
- [x] Hardware monitoring & stats transmission (CPU, GPU, RAM, disk, network)
- [x] Device auto-connect & authentication via USB serial
- [x] Menu bar UI with live stats display
- [x] Profile switching from menu bar (profiles 1-5)
- [x] Settings window with proper focus handling (AppDelegate approach)
- [x] CI/CD with GitHub Actions (build + 37 tests)

### Macro System - COMPLETE
- [x] All 13 action types implemented:
  - [x] Keyboard Shortcut (Cmd+C, Ctrl+Shift+N, etc.)
  - [x] Type Text (with optional Enter)
  - [x] Media Control (play/pause, volume, track controls)
  - [x] Launch Application (by path or bundle ID)
  - [x] Open Website (URL in default browser)
  - [x] Open Folder (in Finder)
  - [x] Run Command (shell commands)
  - [x] Mouse Click (left, right, double)
  - [x] Mouse Move (X,Y with optional drag)
  - [x] Function Keys (F1-F15, special keys)
  - [x] Delay (milliseconds)
  - [x] Change Profile (1-5)
  - [x] System Controls (calculator, browser controls, search)
- [x] ActionExecutor service with CGEvent simulation
- [x] Key press handler wired up in DeviceManager

### Configuration - COMPLETE
- [x] Profile model (5 profiles, 8 keys each)
- [x] KeyConfig model (actions array, alias, HID mode)
- [x] JSON persistence in ~/Library/Application Support/NexMacro/
- [x] Per-device configuration storage
- [x] Profile sync to device

### Configuration UI - COMPLETE
- [x] Keys tab - 8-key visual layout matching device
- [x] Click key to edit with action list
- [x] Action type picker with parameter editors
- [x] Add/remove actions per key
- [x] Profile selector tabs
- [x] RGB tab - Color picker + 9 lighting modes
- [x] General tab - Update interval, launch at login, dynamic profiles
- [x] Device tab - Device info, reconnect, reset options

### Dynamic Profile Switching - COMPLETE
- [x] NSWorkspace frontmost app monitoring
- [x] App-to-profile mapping configuration
- [x] Auto-switch on app focus change
- [x] Default profile fallback

---

## Remaining for v1.0.0

### High Priority
- [ ] **App Icon** - Design and add proper app icon (currently uses default)
- [ ] **Verify RGB Mode** - Test all 9 lighting modes with physical device

### Nice to Have
- [ ] **About Window** - Version info, links, credits
- [ ] **Import/Export** - Backup/restore configurations to JSON file

---

## Technical Architecture

### Key Press Flow
```
Device sends: "ebf.k.{profileId}.{keyId}"
  → SerialPortService receives data
  → NexProtocol.parseResponse() extracts profile/key
  → DeviceManager.handleKeyPress() called
  → ActionExecutor.execute(actions for key)
```

### Project Structure
```
Sources/
├── CPcStats/           # C code for IOKit hardware monitoring
├── NexMacro/
│   ├── App/            # NexMacroApp.swift, AppDelegate
│   ├── Models/         # Device, KeyAction, NexProtocol, PcStats
│   ├── Services/       # DeviceManager, SerialPortService,
│   │                   # ActionExecutor, HardwareMonitor
│   └── Views/          # SettingsView, KeyConfigurationView,
│                       # RGBSettingsView, MenuBarView
Tests/
└── NexMacroTests/      # Protocol and model tests
```

### File Locations
- Config: `~/Library/Application Support/NexMacro/`
- Device configs: `configs/{deviceId}/`

### Protocol Reference
| Command | Format | Description |
|---------|--------|-------------|
| Query Version | `ebf05` | Get firmware version |
| Query Type | `ebf0e` | Get device type |
| Query ID | `ebf0f` | Get device ID |
| Change Profile | `ebf09N` | Switch to profile N (1-5) |
| RGB Color | `ebf01RRGGBB100` | Set RGB color (hex) |
| RGB Mode | `ebf0jN` | Set lighting mode (0-8) |
| PC Stats | `pcs{len}{json}` | Send system stats |

---

## Completed Milestones

- **2024-01-10**: Initial protocol analysis from C# decompilation
- **2024-01-11**: GitHub repo setup with CI/CD
- **2024-01-11**: Added 37 unit tests for protocol and models
- **2024-01-11**: Fixed Settings window focus with AppDelegate pattern

---

## Dependencies

- [ORSSerialPort](https://github.com/armadsen/ORSSerialPort) - Serial port communication
- macOS 14.0+ (Sonoma) - SwiftUI MenuBarExtra, modern APIs
