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

    @Test("Config reload replaces summon aliases and preserves unrelated settings")
    func configReloadReplacesSummonAliases() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wisp-summon-reload-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = directory.appendingPathComponent("wisp.jsonc")

        let originalSummon: [String] = ["hyper+f5", "hyper+f6"]
        let updatedSummon: [String] = ["hyper+f7", "hyper+f8"]
        let original = WispConfig(
            theme: .light,
            scratchpadFolder: "/tmp/wisp-test-scratchpad",
            keymap: Keymap([
                .summon: ChordSet(originalSummon), .bold: "cmd+b",
            ]))
        try ConfigStore.write(original, at: configURL)

        let settings = Settings(configFileURL: configURL)
        let monitor = HotKeyMonitor()
        defer { monitor.unregister() }
        #expect(monitor.register(settings.config.summonChords, onPress: { _ in }, onRelease: {}))
        let originalChords = monitor.chords
        #expect(originalChords.count == 2)

        var edited = settings.config
        edited.keymap = Keymap([
            .summon: ChordSet(updatedSummon), .bold: "cmd+b",
        ])
        try ConfigStore.update(["keymap"], to: edited.keymap, in: edited, at: configURL)

        #expect(settings.reload())
        #expect(
            monitor.register(settings.config.summonChords, onPress: { _ in }, onRelease: {}))
        let updatedChords = try updatedSummon.map { try #require(KeyChord.parse($0)) }
        #expect(monitor.chords == updatedChords)
        #expect(settings.config.theme == .light)
        #expect(settings.config.scratchpadFolder == "/tmp/wisp-test-scratchpad")
        #expect(settings.config.keymap.chord(for: .bold) == "cmd+b")

        let oldProbe = HotKeyMonitor()
        defer { oldProbe.unregister() }
        try #require(oldProbe.register(originalChords, onPress: { _ in }, onRelease: {}))

        let activeProbe = HotKeyMonitor()
        defer { activeProbe.unregister() }
        #expect(!activeProbe.register(monitor.chords, onPress: { _ in }, onRelease: {}))
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
