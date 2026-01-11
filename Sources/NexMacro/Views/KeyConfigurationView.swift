import SwiftUI

/// Main view for configuring macro keys
struct KeyConfigurationView: View {
    @Environment(DeviceManager.self) private var deviceManager
    @State private var selectedKeyId: Int? = nil
    @State private var selectedProfileId: Int = 1

    var body: some View {
        VStack(spacing: 0) {
            // Profile selector
            profileSelector
                .padding(.horizontal, 16)
                .padding(.top, 12)

            Divider()
                .padding(.vertical, 8)

            // Key grid
            keyGrid
                .padding(.horizontal, 16)

            Divider()
                .padding(.vertical, 8)

            // Action editor for selected key
            if let keyId = selectedKeyId {
                ActionEditorView(
                    profileId: selectedProfileId,
                    keyId: keyId
                )
                .padding(.horizontal, 16)
            } else {
                emptySelection
            }

            Spacer()
        }
        .frame(minWidth: 400, minHeight: 500)
    }

    // MARK: - Profile Selector

    private var profileSelector: some View {
        HStack {
            Text("Profile:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Profile", selection: $selectedProfileId) {
                ForEach(deviceManager.profiles) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Spacer()
        }
    }

    // MARK: - Key Grid

    private var keyGrid: some View {
        let profile = deviceManager.profiles.first { $0.id == selectedProfileId }

        return VStack(spacing: 12) {
            Text("Keys")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 2 rows of 4 keys
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(0..<4) { keyId in
                        keyButton(for: keyId, in: profile)
                    }
                }
                HStack(spacing: 8) {
                    ForEach(4..<8) { keyId in
                        keyButton(for: keyId, in: profile)
                    }
                }
            }
        }
    }

    private func keyButton(for keyId: Int, in profile: Profile?) -> some View {
        let keyConfig = profile?.keys.first { $0.id == keyId }
        let isSelected = selectedKeyId == keyId
        let hasActions = !(keyConfig?.actions.isEmpty ?? true)

        return Button {
            selectedKeyId = keyId
        } label: {
            VStack(spacing: 4) {
                Text(keyConfig?.alias ?? "Key \(keyId + 1)")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .lineLimit(1)

                if hasActions {
                    Text("\(keyConfig?.actions.count ?? 0) actions")
                        .font(.system(.caption2))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Empty")
                        .font(.system(.caption2))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 80, height: 60)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty Selection

    private var emptySelection: some View {
        VStack(spacing: 8) {
            Image(systemName: "keyboard")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)

            Text("Select a key to configure")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Editor view for a single key's actions
struct ActionEditorView: View {
    @Environment(DeviceManager.self) private var deviceManager
    let profileId: Int
    let keyId: Int

    @State private var keyAlias: String = ""
    @State private var showingAddAction = false

    private var keyConfig: KeyConfig? {
        deviceManager.profiles
            .first { $0.id == profileId }?
            .keys.first { $0.id == keyId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Key name editor
            HStack {
                Text("Key Name:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("Key Name", text: $keyAlias)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                    .onAppear {
                        keyAlias = keyConfig?.alias ?? "Key \(keyId + 1)"
                    }
                    .onChange(of: keyAlias) { _, newValue in
                        updateKeyAlias(newValue)
                    }

                Spacer()

                Button {
                    showingAddAction = true
                } label: {
                    Label("Add Action", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            // Actions list
            actionsListView

            Spacer()
        }
        .sheet(isPresented: $showingAddAction) {
            AddActionSheet(profileId: profileId, keyId: keyId)
                .environment(deviceManager)
        }
    }

    private var actionsListView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Actions")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let config = keyConfig, !config.actions.isEmpty {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(Array(config.actions.enumerated()), id: \.offset) { index, action in
                            ActionRowView(
                                action: action,
                                index: index,
                                profileId: profileId,
                                keyId: keyId
                            )
                        }
                    }
                }
                .frame(maxHeight: 200)
            } else {
                Text("No actions configured")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            }
        }
    }

    private func updateKeyAlias(_ newAlias: String) {
        guard var config = keyConfig else { return }
        config.alias = newAlias
        deviceManager.updateKeyConfig(profileId: profileId, keyId: keyId, config: config)
    }
}

/// Row view for a single action
struct ActionRowView: View {
    @Environment(DeviceManager.self) private var deviceManager
    let action: KeyAction
    let index: Int
    let profileId: Int
    let keyId: Int

    var body: some View {
        HStack {
            Image(systemName: iconForAction(action.type))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(action.type.displayName)
                    .font(.caption)
                    .fontWeight(.medium)

                Text(action.parameter.isEmpty ? "No parameter" : action.parameter)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Move up/down buttons
            HStack(spacing: 4) {
                Button {
                    moveAction(at: index, direction: -1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.plain)
                .disabled(index == 0)

                Button {
                    moveAction(at: index, direction: 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.plain)
                .disabled(isLastAction)

                Button {
                    deleteAction(at: index)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
            .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.1))
        )
    }

    private var isLastAction: Bool {
        guard let config = deviceManager.profiles
            .first(where: { $0.id == profileId })?
            .keys.first(where: { $0.id == keyId }) else { return true }
        return index >= config.actions.count - 1
    }

    private func moveAction(at index: Int, direction: Int) {
        guard let profile = deviceManager.profiles.first(where: { $0.id == profileId }),
              var keyConfig = profile.keys.first(where: { $0.id == keyId }) else { return }

        let newIndex = index + direction
        guard newIndex >= 0, newIndex < keyConfig.actions.count else { return }

        keyConfig.actions.swapAt(index, newIndex)
        deviceManager.updateKeyConfig(profileId: profileId, keyId: keyId, config: keyConfig)
    }

    private func deleteAction(at index: Int) {
        guard let profile = deviceManager.profiles.first(where: { $0.id == profileId }),
              var keyConfig = profile.keys.first(where: { $0.id == keyId }) else { return }

        keyConfig.actions.remove(at: index)
        deviceManager.updateKeyConfig(profileId: profileId, keyId: keyId, config: keyConfig)
    }

    private func iconForAction(_ type: KeyActionType) -> String {
        switch type {
        case .shortcut: return "command"
        case .textInput: return "text.cursor"
        case .mediaControl: return "play.circle"
        case .delay: return "timer"
        case .launchApp: return "app.badge"
        case .accessWebsite: return "globe"
        case .openFolder: return "folder"
        case .command: return "terminal"
        case .mouseClick: return "cursorarrow.click"
        case .mouseMove: return "cursorarrow.motionlines"
        case .functionKey: return "keyboard"
        case .changeProfile: return "person.2"
        case .controlAction: return "gearshape"
        }
    }
}

/// Sheet for adding a new action
struct AddActionSheet: View {
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(\.dismiss) private var dismiss

    let profileId: Int
    let keyId: Int

    @State private var selectedType: KeyActionType = .shortcut
    @State private var parameter: String = ""

    // Shortcut-specific
    @State private var useCommand = true
    @State private var useShift = false
    @State private var useOption = false
    @State private var useControl = false
    @State private var shortcutKey = ""

    // Media-specific
    @State private var selectedMediaControl: MediaControlType = .playPause

    // Mouse-specific
    @State private var selectedMouseClick: MouseClickType = .leftClick
    @State private var mouseX: String = ""
    @State private var mouseY: String = ""
    @State private var mouseDrag = false

    // Control action-specific
    @State private var selectedControlAction: ControlActionType = .calculator

    // Profile change-specific
    @State private var selectedProfile: Int = 1

    // Delay-specific
    @State private var delayMs: String = "100"

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Action")
                .font(.headline)

            // Action type picker
            Picker("Action Type", selection: $selectedType) {
                ForEach(KeyActionType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            Divider()

            // Type-specific parameters
            parameterEditor

            Spacer()

            // Buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Add") {
                    addAction()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 350, height: 400)
    }

    @ViewBuilder
    private var parameterEditor: some View {
        switch selectedType {
        case .shortcut:
            shortcutEditor

        case .textInput:
            TextField("Text to type", text: $parameter)
                .textFieldStyle(.roundedBorder)

        case .mediaControl:
            Picker("Media Control", selection: $selectedMediaControl) {
                ForEach(MediaControlType.allCases, id: \.self) { control in
                    Text(control.displayName).tag(control)
                }
            }
            .pickerStyle(.menu)

        case .delay:
            HStack {
                TextField("Milliseconds", text: $delayMs)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                Text("ms")
            }

        case .launchApp, .accessWebsite, .openFolder, .command:
            TextField(placeholderForType(selectedType), text: $parameter)
                .textFieldStyle(.roundedBorder)

        case .mouseClick:
            Picker("Click Type", selection: $selectedMouseClick) {
                ForEach(MouseClickType.allCases, id: \.self) { click in
                    Text(click.displayName).tag(click)
                }
            }
            .pickerStyle(.menu)

        case .mouseMove:
            VStack {
                HStack {
                    TextField("X", text: $mouseX)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    TextField("Y", text: $mouseY)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                Toggle("Drag (hold left mouse)", isOn: $mouseDrag)
            }

        case .functionKey:
            TextField("Key (F1-F12, ENTER, etc.)", text: $parameter)
                .textFieldStyle(.roundedBorder)

        case .changeProfile:
            Picker("Profile", selection: $selectedProfile) {
                ForEach(1...5, id: \.self) { id in
                    Text("Profile \(id)").tag(id)
                }
            }
            .pickerStyle(.menu)

        case .controlAction:
            Picker("Control Action", selection: $selectedControlAction) {
                ForEach(ControlActionType.allCases, id: \.self) { action in
                    Text(action.displayName).tag(action)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var shortcutEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Modifiers:")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Toggle("⌘", isOn: $useCommand)
                Toggle("⇧", isOn: $useShift)
                Toggle("⌥", isOn: $useOption)
                Toggle("⌃", isOn: $useControl)
            }
            .toggleStyle(.button)

            TextField("Key (A-Z, 0-9, etc.)", text: $shortcutKey)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func placeholderForType(_ type: KeyActionType) -> String {
        switch type {
        case .launchApp: return "App path or bundle ID"
        case .accessWebsite: return "URL (https://...)"
        case .openFolder: return "Folder path"
        case .command: return "Shell command"
        default: return "Parameter"
        }
    }

    private func addAction() {
        let action: KeyAction

        switch selectedType {
        case .shortcut:
            var modifiers: ModifierKeys = []
            if useCommand { modifiers.insert(.command) }
            if useShift { modifiers.insert(.shift) }
            if useOption { modifiers.insert(.option) }
            if useControl { modifiers.insert(.control) }
            action = .shortcut(modifiers: modifiers, key: shortcutKey)

        case .textInput:
            action = .text(parameter)

        case .mediaControl:
            action = .media(selectedMediaControl)

        case .delay:
            action = .delay(milliseconds: Int(delayMs) ?? 100)

        case .launchApp:
            action = .launchApp(path: parameter)

        case .accessWebsite:
            action = .openURL(parameter)

        case .openFolder:
            action = .openFolder(parameter)

        case .command:
            action = .runCommand(parameter)

        case .mouseClick:
            action = .mouseClick(selectedMouseClick)

        case .mouseMove:
            action = .mouseMove(x: Int(mouseX) ?? 0, y: Int(mouseY) ?? 0, drag: mouseDrag)

        case .functionKey:
            action = .functionKey(parameter)

        case .changeProfile:
            action = .changeProfile(selectedProfile)

        case .controlAction:
            action = .control(selectedControlAction)
        }

        // Add to key config
        guard var keyConfig = deviceManager.profiles
            .first(where: { $0.id == profileId })?
            .keys.first(where: { $0.id == keyId }) else { return }

        keyConfig.actions.append(action)
        deviceManager.updateKeyConfig(profileId: profileId, keyId: keyId, config: keyConfig)
    }
}

#Preview {
    KeyConfigurationView()
        .environment(DeviceManager())
        .frame(width: 450, height: 600)
}
