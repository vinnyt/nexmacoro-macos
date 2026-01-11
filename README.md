# NexMacro for macOS

A native macOS menu bar application for controlling NexMacro macro keypads. Provides full device configuration, PC stats monitoring, and macro key execution.

## Features

### Device Communication
- Auto-detection and connection to NexMacro devices via USB serial
- Device authentication and firmware version detection
- Support for 8-key and other NexMacro device variants

### PC Stats Monitoring
- Real-time system statistics sent to device display:
  - CPU temperature, load, and power consumption
  - GPU temperature, load, frequency, and power
  - Memory usage and availability
  - Disk usage percentage
  - Network upload/download speeds
  - System uptime

### Macro Key Configuration
- 5 profiles with 8 configurable keys each
- 13 action types:
  - **Keyboard Shortcut** - Any key combination (Cmd+C, Ctrl+Shift+N, etc.)
  - **Type Text** - Type strings with optional Enter
  - **Media Control** - Play/pause, next/prev track, volume, mute
  - **Launch Application** - Open apps by path or bundle ID
  - **Open Website** - Open URLs in default browser
  - **Open Folder** - Open folders in Finder
  - **Run Command** - Execute shell commands in Terminal
  - **Mouse Click** - Left, right, or double click
  - **Mouse Move** - Move cursor to coordinates (with optional drag)
  - **Function Keys** - F1-F15 and special keys
  - **Delay** - Wait between actions (milliseconds)
  - **Change Profile** - Switch to another profile
  - **System Controls** - Calculator, browser controls, search, etc.

### RGB Lighting Control
- Set custom RGB colors
- 9 lighting modes: Off, Static, Breathing, Fast Breathing, Dim, Flowing, Press React, Rainbow, Slow Breathing

### Dynamic Profile Switching
- Automatically switch profiles based on the active application
- Configure app-to-profile mappings

## Requirements

- macOS 14.0 (Sonoma) or later
- NexMacro macro keypad connected via USB

## Building

```bash
# Clone the repository
git clone https://github.com/vinnyt/nexmacoro-macos.git
cd nexmacoro-macos

# Build with Swift Package Manager
swift build

# Run the app
.build/debug/NexMacro
```

## Usage

1. Connect your NexMacro device via USB
2. Launch NexMacro - it appears in the menu bar
3. The app will automatically detect and connect to your device
4. Click the menu bar icon to:
   - View system stats
   - Switch profiles (1-5)
   - Toggle stats sending to device
   - Open Settings

### Settings

- **Keys tab** - Configure actions for each key in each profile
- **RGB tab** - Set lighting color and mode
- **General tab** - Configure update interval, launch at login, dynamic profile switching
- **Device tab** - View device info, reconnect, reset configuration

## Architecture

```
Sources/
├── CPcStats/           # C code for hardware monitoring via IOKit
├── NexMacro/
│   ├── App/            # Main app entry point and menu bar UI
│   ├── Models/         # Data models (Device, KeyAction, Profile, etc.)
│   ├── Services/       # Business logic
│   │   ├── DeviceManager.swift      # Central device and profile management
│   │   ├── SerialPortService.swift  # USB serial communication
│   │   ├── ActionExecutor.swift     # Macro action execution via CGEvent
│   │   ├── HardwareMonitor.swift    # System stats collection
│   │   └── ...
│   └── Views/          # SwiftUI views for settings
```

## Protocol

The app communicates with the device using a simple ASCII protocol:

| Command | Format | Description |
|---------|--------|-------------|
| Query Version | `ebf05` | Get firmware version |
| Query Type | `ebf0e` | Get device type |
| Query ID | `ebf0f` | Get device ID |
| Change Profile | `ebf09N` | Switch to profile N (1-5) |
| RGB Color | `ebf01RRGGBB100` | Set RGB color (hex) |
| RGB Mode | `ebf0jN` | Set lighting mode (0-8) |
| PC Stats | `pcs0{json}` | Send system stats JSON |

## Dependencies

- [ORSSerialPort](https://github.com/armadsen/ORSSerialPort) - Serial port communication

## License

MIT License

## Acknowledgments

- Built with assistance from Claude (Anthropic)
