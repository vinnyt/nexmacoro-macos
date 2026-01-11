// swift-tools-version: 5.9
// NexMacro - macOS Menu Bar App for Macro Keypad Configuration

import PackageDescription

let package = Package(
    name: "NexMacro",
    platforms: [
        .macOS(.v14)  // macOS 14+ for modern SwiftUI features
    ],
    products: [
        .executable(name: "NexMacro", targets: ["NexMacro"])
    ],
    dependencies: [
        // ORSSerialPort for serial communication
        .package(url: "https://github.com/armadsen/ORSSerialPort.git", from: "2.1.0")
    ],
    targets: [
        // C library target for hardware monitoring
        .target(
            name: "CPcStats",
            dependencies: [],
            path: "Sources/CPcStats",
            sources: ["pcstats.c"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include"),
                .unsafeFlags(["-fmodules", "-fcxx-modules"])
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation")
            ]
        ),
        // Main Swift application
        .executableTarget(
            name: "NexMacro",
            dependencies: [
                "CPcStats",
                .product(name: "ORSSerial", package: "ORSSerialPort")
            ],
            path: "Sources/NexMacro",
            resources: [
                .process("../Resources")
            ],
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals"),
                .enableExperimentalFeature("StrictConcurrency")
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        ),
        // Test target
        .testTarget(
            name: "NexMacroTests",
            dependencies: [],
            path: "Tests/NexMacroTests"
        )
    ]
)
