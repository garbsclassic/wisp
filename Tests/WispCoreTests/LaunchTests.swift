import Foundation
import Testing

@testable import WispCore

@Suite("LaunchSource")
struct LaunchSourceTests {
    /// AppKit annotates the launch notification, but not on every path —
    /// missing means user-initiated, so we never silently swallow the
    /// panel on a launch AppKit didn't label.
    @Test("An unlabeled launch is treated as user-initiated")
    func fallbacks() {
        #expect(LaunchSource.isUserInitiated(launchUserInfo: nil))
        #expect(LaunchSource.isUserInitiated(launchUserInfo: [:]))
        #expect(LaunchSource.isUserInitiated(launchUserInfo: ["SomeOtherKey": false]))
    }

    @Test("The launch key decides, as a Bool or a bridged NSNumber")
    func labeledLaunches() {
        let key = LaunchSource.isDefaultLaunchKey
        #expect(LaunchSource.isUserInitiated(launchUserInfo: [key: true]))
        #expect(!LaunchSource.isUserInitiated(launchUserInfo: [key: false]))
        #expect(LaunchSource.isUserInitiated(launchUserInfo: [key: NSNumber(value: true)]))
        #expect(!LaunchSource.isUserInitiated(launchUserInfo: [key: NSNumber(value: false)]))
    }
}

@Suite("LaunchAtLogin")
struct LaunchAtLoginTests {
    /// Smoke-only: SMAppService talks to a system daemon that an unbundled
    /// test run can't register with, so this checks the API contract
    /// without mutating real state.
    @Test("Reading is total and re-setting the current state is a no-op")
    func contract() {
        let before = LaunchAtLogin.isEnabled
        LaunchAtLogin.setEnabled(before)
        #expect(LaunchAtLogin.isEnabled == before)
    }
}
