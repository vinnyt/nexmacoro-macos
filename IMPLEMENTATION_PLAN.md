# NexMacro macOS - Implementation Plan

## Current State (Completed)
- [x] Hardware monitoring & stats transmission
- [x] Device auto-connect & authentication
- [x] Basic menu bar UI with stats display
- [x] Auto-start on app launch
- [x] Timezone-adjusted timestamps

---

## Phase 1: Core Macro Functionality

**Goal**: Make device keys execute actions when pressed

### 1.1 Action System Architecture
- [ ] Define `KeyAction` enum/protocol for all 13 action types
- [ ] Create `ActionExecutor` service to run actions
- [ ] Wire up key press handler in `DeviceManager` (stub exists at line 209)

### 1.2 Basic Action Types
- [ ] **Keyboard Shortcut** - Send key combinations (Cmd+C, Cmd+V, etc.)
- [ ] **Text Input** - Type text strings with optional Enter
- [ ] **Media Keys** - Play/pause, volume up/down, next/prev track
- [ ] **Delay** - Wait milliseconds between actions

### 1.3 Advanced Action Types
- [ ] **Launch Application** - Open apps by path or bundle ID
- [ ] **Open URL** - Launch default browser with URL
- [ ] **Open Folder** - Open Finder at path
- [ ] **Run Command** - Execute shell commands
- [ ] **Mouse Click** - Left, right, double click
- [ ] **Mouse Move** - Move cursor to X,Y coordinates
- [ ] **Function Keys** - F1-F12, arrows, Home/End, Page Up/Down
- [ ] **Change Profile** - Switch to profile 1-5
- [ ] **Browser Control** - Back, forward, refresh, bookmarks

---

## Phase 2: Configuration & Persistence

**Goal**: Save and load key configurations

### 2.1 Data Models
- [ ] `Profile` model (id, name, keys[8])
- [ ] `KeyConfig` model (keyId, actions[], alias, icon)
- [ ] `AppSettings` model (all user preferences)

### 2.2 Storage Layer
- [ ] JSON config in `~/Library/Application Support/NexMacro/`
- [ ] Per-device directories: `configs/{deviceId}/`
- [ ] File format: `profile_{n}_key_{m}.json`
- [ ] Settings persistence

### 2.3 Profile Management
- [ ] Support 5 profiles per device
- [ ] Track active profile
- [ ] Sync profile changes to device

---

## Phase 3: Configuration UI

**Goal**: Visual key configuration

### 3.1 Key Configuration View
- [ ] 8-key visual layout matching physical device
- [ ] Click key to select and edit
- [ ] Action list with add/remove/reorder
- [ ] Action type picker dropdown
- [ ] Parameter editors per action type
- [ ] Alias/name field for each key

### 3.2 Profile Management UI
- [ ] Profile tabs or selector
- [ ] Rename profile
- [ ] Copy profile
- [ ] Reset to defaults

### 3.3 RGB Control UI
- [ ] Native SwiftUI color picker
- [ ] RGB mode dropdown (static, breathing, rainbow, etc.)
- [ ] Live preview - send to device on change
- [ ] Persist RGB settings

---

## Phase 4: Enhanced Features

**Goal**: Feature parity with Windows app

### 4.1 Dynamic Profile Switching
- [ ] Monitor frontmost application via NSWorkspace
- [ ] App-to-profile mapping configuration
- [ ] Auto-switch when app focus changes
- [ ] Default profile fallback

### 4.2 Import/Export
- [ ] Export all configs to JSON file
- [ ] Import configs from file
- [ ] Backup/restore functionality

### 4.3 System Integration
- [ ] Login item (launch at startup)
- [ ] Proper app icon and branding
- [ ] About window with version info
- [ ] Menu bar icon options

---

## Technical Notes

### Key Press Flow
```
Device sends: "ebf.k.{profileId}.{keyId}"
  → SerialPortService receives data
  → NexProtocol.parseResponse() extracts profile/key
  → DeviceManager.handleKeyPress() called
  → ActionExecutor.execute(actions for key)
```

### macOS APIs Needed
- **CGEvent** - Keyboard/mouse simulation
- **NSWorkspace** - Launch apps, open URLs, monitor active app
- **NSAppleScript** - System commands (optional)
- **ServiceManagement** - Login items

### File Locations
- Config: `~/Library/Application Support/NexMacro/`
- Logs: `~/Library/Logs/NexMacro/` (optional)

---

## Priority Order

1. **Phase 1.1-1.2** - Basic actions working (keyboard, media, text)
2. **Phase 2** - Persistence so configs survive restart
3. **Phase 3.1** - UI to configure keys
4. **Phase 1.3** - Remaining action types
5. **Phase 3.2-3.3** - Profile and RGB UI
6. **Phase 4** - Polish features

---

## References

- Windows C# source: `/nexmacro/decompiled/`
- Protocol docs: `NexProtocol.swift`
- Device models: `Device.swift`
