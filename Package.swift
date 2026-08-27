// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Wisp",
    platforms: [.macOS(.v13)],
    targets: [
        // Logic the app is built out of — text parsing, config, theme
        // tokens, frame validation. No views and no controllers, so it
        // unit tests without a running NSApplication.
        .target(
            name: "WispCore",
            path: "Sources/WispCore"
        ),
        .executableTarget(
            name: "Wisp",
            dependencies: ["WispCore"],
            path: "Sources/Wisp"
        ),
        // Command Line Tools ships its own Testing.framework but not on the
        // default search path, so `swift test` alone fails with "no such
        // module 'Testing'" — scripts/test.sh points the compiler, linker,
        // and dyld at it directly, the same trick Clef's test.sh uses.
        .testTarget(
            name: "WispCoreTests",
            dependencies: ["WispCore"],
            path: "Tests/WispCoreTests"
        ),
    ]
)
