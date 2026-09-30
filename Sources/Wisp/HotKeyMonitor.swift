import AppKit
import Carbon.HIToolbox

/// A system-wide hotkey through Carbon, which needs no Accessibility grant and reports the
/// key's release, which hold-to-peek relies on.
@MainActor
final class HotKeyMonitor {
    private var hotKeyRef: EventHotKeyRef?
    private let id: UInt32

    private static var nextID: UInt32 = 1
    private static var eventHandlerInstalled = false
    // Carbon's callback runs on the main run loop but isn't main-actor isolated; only
    // main-actor methods write this.
    private static nonisolated(unsafe) var handlers: [UInt32: Handlers] = [:]

    private struct Handlers {
        let pressed: () -> Void
        let released: () -> Void
    }

    init() {
        id = Self.nextID
        Self.nextID += 1
    }

    // No deinit: the app delegate holds this for the app's lifetime.

    /// `keyCode` is a Carbon `kVK_*`; `modifiers` is a Carbon mask.
    @discardableResult
    func register(
        keyCode: UInt32, modifiers: UInt32,
        onPress: @escaping () -> Void, onRelease: @escaping () -> Void
    ) -> Bool {
        // Drop the old registration first, or a rebind leaves a dead ref.
        unregister()

        Self.installSharedEventHandler()
        Self.handlers[id] = Handlers(pressed: onPress, released: onRelease)

        let signature: OSType = 0x57495350  // 'WISP'
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        return status == noErr
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        Self.handlers.removeValue(forKey: id)
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
