import Foundation
import Testing
import WispCore

@testable import Wisp

@Suite("HotKeyMonitor", .serialized)
@MainActor
struct HotKeyMonitorTests {
    @Test("Registers multiple chords and deduplicates equivalent spellings")
    func registersMultipleChords() throws {
        let first = try #require(KeyChord.parse("hyper+f11"))
        let firstAlias = try #require(KeyChord.parse("ctrl+opt+shift+cmd+f11"))
        let second = try #require(KeyChord.parse("hyper+f12"))
        let monitor = HotKeyMonitor()
        defer { monitor.unregister() }

        try #require(
            monitor.register([first, firstAlias, second], onPress: { _ in }, onRelease: {}))
        #expect(monitor.chords == [first, second])

        let firstProbe = HotKeyMonitor()
        defer { firstProbe.unregister() }
        #expect(!firstProbe.register([first], onPress: { _ in }, onRelease: {}))

        let secondProbe = HotKeyMonitor()
        defer { secondProbe.unregister() }
        #expect(!secondProbe.register([second], onPress: { _ in }, onRelease: {}))
    }

    @Test("Reload releases obsolete chords and keeps requested chords registered")
    func reloadReconcilesChords() throws {
        let obsolete = try #require(KeyChord.parse("hyper+f9"))
        let retained = try #require(KeyChord.parse("hyper+f10"))
        let added = try #require(KeyChord.parse("hyper+f8"))
        let monitor = HotKeyMonitor()
        defer { monitor.unregister() }

        try #require(monitor.register([obsolete, retained], onPress: { _ in }, onRelease: {}))
        try #require(monitor.register([retained, added], onPress: { _ in }, onRelease: {}))
        #expect(monitor.chords == [retained, added])

        let obsoleteProbe = HotKeyMonitor()
        defer { obsoleteProbe.unregister() }
        try #require(obsoleteProbe.register([obsolete], onPress: { _ in }, onRelease: {}))

        let retainedProbe = HotKeyMonitor()
        defer { retainedProbe.unregister() }
        #expect(!retainedProbe.register([retained], onPress: { _ in }, onRelease: {}))

        let addedProbe = HotKeyMonitor()
        defer { addedProbe.unregister() }
        #expect(!addedProbe.register([added], onPress: { _ in }, onRelease: {}))
    }

    @Test("Partial conflict keeps independently registered requested chords")
    func partialConflictKeepsAvailableChord() throws {
        let available = try #require(KeyChord.parse("hyper+f7"))
        let occupied = try #require(KeyChord.parse("hyper+f6"))
        let blocker = HotKeyMonitor()
        defer { blocker.unregister() }
        try #require(blocker.register([occupied], onPress: { _ in }, onRelease: {}))

        let monitor = HotKeyMonitor()
        defer { monitor.unregister() }
        #expect(!monitor.register([available, occupied], onPress: { _ in }, onRelease: {}))
        #expect(monitor.chords == [available])

        let availableProbe = HotKeyMonitor()
        defer { availableProbe.unregister() }
        #expect(!availableProbe.register([available], onPress: { _ in }, onRelease: {}))
    }

    @Test("Total conflict preserves previous registrations")
    func totalConflictPreservesPreviousChords() throws {
        let previous = try #require(KeyChord.parse("hyper+f5"))
        let occupied = try #require(KeyChord.parse("hyper+f4"))
        let monitor = HotKeyMonitor()
        defer { monitor.unregister() }
        try #require(monitor.register([previous], onPress: { _ in }, onRelease: {}))

        let blocker = HotKeyMonitor()
        defer { blocker.unregister() }
        try #require(blocker.register([occupied], onPress: { _ in }, onRelease: {}))

        #expect(!monitor.register([occupied], onPress: { _ in }, onRelease: {}))
        #expect(monitor.chords == [previous])

        let previousProbe = HotKeyMonitor()
        defer { previousProbe.unregister() }
        #expect(!previousProbe.register([previous], onPress: { _ in }, onRelease: {}))
    }

    @Test("Capture replacement can restore aliases after a failed save")
    func captureReplacementRestoresSavedAliases() throws {
        let first = try #require(KeyChord.parse("hyper+f1"))
        let second = try #require(KeyChord.parse("hyper+f12"))
        let captured = try #require(KeyChord.parse("hyper+f3"))
        let monitor = HotKeyMonitor()
        defer { monitor.unregister() }

        try #require(monitor.register([first, second], onPress: { _ in }, onRelease: {}))
        let savedChords = monitor.chords
        try #require(monitor.register([captured], onPress: { _ in }, onRelease: {}))
        #expect(monitor.chords == [captured])
        try #require(monitor.register(savedChords, onPress: { _ in }, onRelease: {}))
        #expect(monitor.chords == savedChords)

        let firstProbe = HotKeyMonitor()
        defer { firstProbe.unregister() }
        #expect(!firstProbe.register([first], onPress: { _ in }, onRelease: {}))

        let secondProbe = HotKeyMonitor()
        defer { secondProbe.unregister() }
        #expect(!secondProbe.register([second], onPress: { _ in }, onRelease: {}))

        let capturedProbe = HotKeyMonitor()
        defer { capturedProbe.unregister() }
        try #require(capturedProbe.register([captured], onPress: { _ in }, onRelease: {}))
    }

    @Test("An empty chord list unregisters all aliases")
    func emptyListClearsRegistrations() throws {
        let first = try #require(KeyChord.parse("hyper+f3"))
        let second = try #require(KeyChord.parse("hyper+f2"))
        let monitor = HotKeyMonitor()
        defer { monitor.unregister() }

        try #require(monitor.register([first, second], onPress: { _ in }, onRelease: {}))
        try #require(monitor.register([], onPress: { _ in }, onRelease: {}))
        #expect(monitor.chords.isEmpty)

        let firstProbe = HotKeyMonitor()
        defer { firstProbe.unregister() }
        try #require(firstProbe.register([first], onPress: { _ in }, onRelease: {}))

        let secondProbe = HotKeyMonitor()
        defer { secondProbe.unregister() }
        try #require(secondProbe.register([second], onPress: { _ in }, onRelease: {}))
    }

    @Test("Registration warnings report partial and total conflicts, then clear on recovery")
    func registrationWarningsRecover() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wisp-hotkey-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = Settings(configFileURL: directory.appendingPathComponent("wisp.jsonc"))
        let available = try #require(KeyChord.parse("hyper+f7"))
        let occupied = try #require(KeyChord.parse("hyper+f6"))
        let blocker = HotKeyMonitor()
        defer { blocker.unregister() }
        try #require(blocker.register([occupied], onPress: { _ in }, onRelease: {}))
        let monitor = HotKeyMonitor()
        defer { monitor.unregister() }

        #expect(!monitor.register([available, occupied], onPress: { _ in }, onRelease: {}))
        settings.reportSummonRegistration(
            requested: [available, occupied], registered: monitor.chords)
        let warning = try #require(settings.summonWarning)
        #expect(warning.contains(occupied.displayString))
        #expect(!warning.contains(available.displayString))
        #expect(settings.warning == warning)
        #expect(monitor.chords == [available])

        #expect(!monitor.register([occupied], onPress: { _ in }, onRelease: {}))
        settings.reportSummonRegistration(requested: [occupied], registered: monitor.chords)
        #expect(settings.summonWarning != nil)
        #expect(monitor.chords == [available])

        blocker.unregister()
        try #require(monitor.register([occupied], onPress: { _ in }, onRelease: {}))
        settings.reportSummonRegistration(requested: [occupied], registered: monitor.chords)
        #expect(settings.summonWarning == nil)
        #expect(monitor.chords == [occupied])
    }

}
