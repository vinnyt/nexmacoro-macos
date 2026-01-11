import SwiftUI
import AppKit

/// View for controlling RGB lighting on the device
struct RGBControlView: View {
    @Environment(DeviceManager.self) private var deviceManager
    @State private var selectedColor = Color.white
    @State private var selectedMode: DeviceManager.RgbMode = .constantOn

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text("RGB Lighting")
                .font(.headline)

            if !deviceManager.isReady {
                notConnectedView
            } else {
                // Mode selector
                modeSelector

                Divider()

                // Color picker (only show for modes that use color)
                if selectedMode != .off && selectedMode != .rainbow {
                    colorPicker
                }

                Spacer()

                // Preview
                colorPreview
            }
        }
        .padding()
        .onAppear {
            // Load current values from device manager
            selectedMode = deviceManager.rgbMode
            let rgb = deviceManager.rgbColor
            selectedColor = Color(
                red: Double(rgb.r) / 255.0,
                green: Double(rgb.g) / 255.0,
                blue: Double(rgb.b) / 255.0
            )
        }
    }

    // MARK: - Not Connected View

    private var notConnectedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "lightbulb.slash")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)

            Text("Connect a device to control RGB lighting")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Mode Selector

    private var modeSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lighting Mode")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Mode", selection: $selectedMode) {
                ForEach(DeviceManager.RgbMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .onChange(of: selectedMode) { _, newMode in
                deviceManager.setRgbMode(newMode)
            }
        }
    }

    // MARK: - Color Picker

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Color")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ColorPicker("Select Color", selection: $selectedColor, supportsOpacity: false)
                .labelsHidden()
                .onChange(of: selectedColor) { _, newColor in
                    applyColor(newColor)
                }

            // Quick color presets
            HStack(spacing: 8) {
                colorPreset(.red, label: "Red")
                colorPreset(.green, label: "Green")
                colorPreset(.blue, label: "Blue")
                colorPreset(.yellow, label: "Yellow")
                colorPreset(.cyan, label: "Cyan")
                colorPreset(.purple, label: "Purple")
                colorPreset(.white, label: "White")
            }
        }
    }

    private func colorPreset(_ color: Color, label: String) -> some View {
        Button {
            selectedColor = color
            applyColor(color)
        } label: {
            Circle()
                .fill(color)
                .frame(width: 24, height: 24)
                .overlay(
                    Circle()
                        .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(label)
    }

    // MARK: - Color Preview

    private var colorPreview: some View {
        VStack(spacing: 8) {
            Text("Preview")
                .font(.caption)
                .foregroundStyle(.secondary)

            RoundedRectangle(cornerRadius: 12)
                .fill(selectedMode == .off ? Color.black : selectedColor)
                .frame(height: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                )
                .overlay(
                    Group {
                        if selectedMode == .rainbow {
                            LinearGradient(
                                colors: [.red, .orange, .yellow, .green, .blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                )
        }
    }

    // MARK: - Helpers

    private func applyColor(_ color: Color) {
        // Convert SwiftUI Color to NSColor then to RGB
        let nsColor = NSColor(color)

        // Convert to sRGB color space to get reliable RGB components
        guard let rgbColor = nsColor.usingColorSpace(.sRGB) else { return }

        let r = UInt8(min(255, max(0, rgbColor.redComponent * 255)))
        let g = UInt8(min(255, max(0, rgbColor.greenComponent * 255)))
        let b = UInt8(min(255, max(0, rgbColor.blueComponent * 255)))

        deviceManager.setRgbColor(r: r, g: g, b: b)
    }
}

#Preview {
    RGBControlView()
        .environment(DeviceManager())
        .frame(width: 350, height: 400)
}
