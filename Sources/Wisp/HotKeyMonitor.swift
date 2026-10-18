import AppKit
import Carbon.HIToolbox
import WispCore

/// System-wide hotkeys through Carbon, which needs no Accessibility grant and reports the
/// key's release, which hold-to-peek relies on.
@MainActor
final class HotKeyMonitor {
    private struct Registration {
        let chord: KeyChord
        let ref: EventHotKeyRef
        let id: UInt32
    }

    private var registrations: [Registration] = []
    var chords: [KeyChord] { registrations.map(\.chord) }

    private static var nextID: UInt32 = 1
    private static var eventHandlerInstalled = false
    // Carbon's callback runs on the main run loop but isn't main-actor isolated; only
    // main-actor methods write this.
    private static nonisolated(unsafe) var handlers: [UInt32: Handlers] = [:]

    private struct Handlers {
        let pressed: () -> Void
        let released: () -> Void
    }

    // No deinit: the app delegate holds this for the app's lifetime.

    /// Keeps working aliases if some are unavailable, and the old set if every new chord fails.
    @discardableResult
    func register(
        _ chords: [KeyChord],
        onPress: @escaping (KeyChord) -> Void, onRelease: @escaping () -> Void
    ) -> Bool {
        Self.installSharedEventHandler()
        var next: [Registration] = []
        for chord in chords where !next.contains(where: { $0.chord == chord }) {
            let registration: Registration
            if let existing = registrations.first(where: { $0.chord == chord }) {
                registration = existing
            } else {
                let id = Self.nextID
                Self.nextID += 1
                let hotKeyID = EventHotKeyID(signature: 0x57495350, id: id)  // 'WISP'
                var ref: EventHotKeyRef?
                let status = RegisterEventHotKey(
                    chord.keyCode, chord.carbonModifiers, hotKeyID,
                    GetEventDispatcherTarget(), 0, &ref)
                guard status == noErr, let ref else { continue }
                registration = Registration(chord: chord, ref: ref, id: id)
            }
            Self.handlers[registration.id] = Handlers(
                pressed: { onPress(chord) }, released: onRelease)
            next.append(registration)
        }
        guard chords.isEmpty || !next.isEmpty else { return false }
        for old in registrations where !next.contains(where: { $0.id == old.id }) {
            UnregisterEventHotKey(old.ref)
            Self.handlers.removeValue(forKey: old.id)
        }
        registrations = next
        return chords.allSatisfy { chord in next.contains(where: { $0.chord == chord }) }
    }

    func unregister() {
        for registration in registrations {
            UnregisterEventHotKey(registration.ref)
            Self.handlers.removeValue(forKey: registration.id)
        }
        registrations = []
    }

    private static func installSharedEventHandler() {
        guard !eventHandlerInstalled else { return }
        eventHandlerInstalled = true

        var specs = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]

        InstallEventHandler(
            GetEventDispatcherTarget(),
            { (_, event, _) -> OSStatus in
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr,
                      let handlers = HotKeyMonitor.handlers[hotKeyID.id]
                else { return noErr }
                let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
                DispatchQueue.main.async { pressed ? handlers.pressed() : handlers.released() }
                return noErr
            },
            specs.count,
            &specs,
            nil,
            nil
        )
    }
}
