#!/usr/bin/env swift

import AppKit
import Foundation

// Icon sizes needed for macOS app icon
let sizes: [(size: Int, scale: Int, suffix: String)] = [
    (16, 1, "16x16"),
    (16, 2, "16x16@2x"),
    (32, 1, "32x32"),
    (32, 2, "32x32@2x"),
    (128, 1, "128x128"),
    (128, 2, "128x128@2x"),
    (256, 1, "256x256"),
    (256, 2, "256x256@2x"),
    (512, 1, "512x512"),
    (512, 2, "512x512@2x"),
]

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))

    image.lockFocus()

    let bounds = NSRect(x: 0, y: 0, width: size, height: size)
    let inset = size * 0.05
    let cornerRadius = size * 0.22

    // Background gradient (dark blue to purple)
    let backgroundPath = NSBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: inset), xRadius: cornerRadius, yRadius: cornerRadius)

    let gradient = NSGradient(colors: [
        NSColor(red: 0.1, green: 0.1, blue: 0.25, alpha: 1.0),
        NSColor(red: 0.15, green: 0.1, blue: 0.3, alpha: 1.0),
        NSColor(red: 0.2, green: 0.1, blue: 0.35, alpha: 1.0)
    ])
    gradient?.draw(in: backgroundPath, angle: -45)

    // Subtle inner shadow/glow
    let innerRect = bounds.insetBy(dx: inset + size * 0.02, dy: inset + size * 0.02)
    let innerPath = NSBezierPath(roundedRect: innerRect, xRadius: cornerRadius * 0.9, yRadius: cornerRadius * 0.9)
    NSColor(white: 1.0, alpha: 0.03).setFill()
    innerPath.fill()

    // Draw 8-key grid (2x4 layout like the NexMacro device)
    let gridInset = size * 0.18
    let gridRect = bounds.insetBy(dx: gridInset, dy: gridInset)
    let keySpacing = size * 0.025
    let cols = 4
    let rows = 2
    let keyWidth = (gridRect.width - keySpacing * CGFloat(cols - 1)) / CGFloat(cols)
    let keyHeight = (gridRect.height - keySpacing * CGFloat(rows - 1)) / CGFloat(rows)
    let keyCorner = size * 0.04

    // Colors for keys (RGB effect)
    let keyColors: [NSColor] = [
        NSColor(red: 0.9, green: 0.2, blue: 0.3, alpha: 1.0),   // Red
        NSColor(red: 0.95, green: 0.5, blue: 0.2, alpha: 1.0),  // Orange
        NSColor(red: 0.95, green: 0.8, blue: 0.2, alpha: 1.0),  // Yellow
        NSColor(red: 0.3, green: 0.85, blue: 0.4, alpha: 1.0),  // Green
        NSColor(red: 0.2, green: 0.7, blue: 0.9, alpha: 1.0),   // Cyan
        NSColor(red: 0.3, green: 0.4, blue: 0.95, alpha: 1.0),  // Blue
        NSColor(red: 0.6, green: 0.3, blue: 0.9, alpha: 1.0),   // Purple
        NSColor(red: 0.9, green: 0.3, blue: 0.7, alpha: 1.0),   // Pink
    ]

    for row in 0..<rows {
        for col in 0..<cols {
            let keyIndex = row * cols + col
            let x = gridRect.minX + CGFloat(col) * (keyWidth + keySpacing)
            let y = gridRect.minY + CGFloat(rows - 1 - row) * (keyHeight + keySpacing)
            let keyRect = NSRect(x: x, y: y, width: keyWidth, height: keyHeight)
            let keyPath = NSBezierPath(roundedRect: keyRect, xRadius: keyCorner, yRadius: keyCorner)

            // Key background (dark)
            NSColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1.0).setFill()
            keyPath.fill()

            // Key glow/LED effect at top
            let glowRect = NSRect(x: x + keyWidth * 0.2, y: y + keyHeight * 0.65, width: keyWidth * 0.6, height: keyHeight * 0.25)
            let glowPath = NSBezierPath(roundedRect: glowRect, xRadius: keyCorner * 0.5, yRadius: keyCorner * 0.5)

            let glowColor = keyColors[keyIndex]
            let glowGradient = NSGradient(colors: [
                glowColor.withAlphaComponent(0.9),
                glowColor.withAlphaComponent(0.4)
            ])
            glowGradient?.draw(in: glowPath, angle: 90)

            // Subtle key border
            NSColor(white: 0.3, alpha: 0.3).setStroke()
            keyPath.lineWidth = size * 0.005
            keyPath.stroke()
        }
    }

    // Add "NM" text or just leave as keypad visual
    // Keeping it clean with just the keypad visual

    image.unlockFocus()

    return image
}

func saveImage(_ image: NSImage, to path: String) {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to create PNG data")
        return
    }

    do {
        try pngData.write(to: URL(fileURLWithPath: path))
        print("Saved: \(path)")
    } catch {
        print("Failed to save \(path): \(error)")
    }
}

// Main
let scriptDir = CommandLine.arguments[0].components(separatedBy: "/").dropLast().joined(separator: "/")
let projectDir = scriptDir.components(separatedBy: "/").dropLast().joined(separator: "/")
let iconsetPath = projectDir + "/Sources/Resources/AppIcon.iconset"

// Create iconset directory
let fileManager = FileManager.default
try? fileManager.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

print("Generating NexMacro app icon...")
print("Output: \(iconsetPath)")

for (size, scale, suffix) in sizes {
    let pixelSize = size * scale
    let image = drawIcon(size: CGFloat(pixelSize))
    let filename = "icon_\(suffix).png"
    let path = iconsetPath + "/" + filename
    saveImage(image, to: path)
}

print("\nGenerating .icns file...")
let icnsPath = projectDir + "/Sources/Resources/AppIcon.icns"
let result = Process()
result.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
result.arguments = ["-c", "icns", iconsetPath, "-o", icnsPath]
try? result.run()
result.waitUntilExit()

if result.terminationStatus == 0 {
    print("Created: \(icnsPath)")
    print("\nDone! App icon generated successfully.")
} else {
    print("Failed to create .icns file")
}
