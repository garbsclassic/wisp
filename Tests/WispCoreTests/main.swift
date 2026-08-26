import Testing

/// Entry point for `swift run WispCoreTests`.
///
/// The suites in this target are ordinary Swift Testing `@Test` functions.
/// They are run through swift-testing's own SwiftPM entry point rather
/// than `swift test`, because SwiftPM's test runner links XCTest and
/// Command Line Tools ships neither XCTest nor a bundled Testing module —
/// hence the explicit `swift-testing` package dependency as well.
await Testing.__swiftPMEntryPoint() as Never
