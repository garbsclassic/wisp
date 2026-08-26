// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Wisp",
    platforms: [.macOS(.v13)],
    dependencies: [
        // Command Line Tools ships neither XCTest nor a bundled Testing
        // module, so Swift Testing comes in as a source dependency.
        //
        // Pinned exactly: from 6.3 on, the Testing target link-directives
        // `_TestingInterop`, which it expects the *toolchain* to provide —
        // the package only vends its own copy under a _DO_NOT_USE name, so
        // 6.3+ fails to link here. 6.2.4 is the last tag that doesn't.
        .package(url: "https://github.com/swiftlang/swift-testing.git", exact: "6.2.4")
    ],
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
        // An executable, not a `.testTarget`: SwiftPM's test runner links
        // XCTest, which Command Line Tools does not ship. Run the suites
        // with `swift run WispCoreTests`.
        .executableTarget(
            name: "WispCoreTests",
            dependencies: [
                "WispCore",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/WispCoreTests"
        ),
    ]
)
