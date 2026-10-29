import AppKit
import Carbon.HIToolbox
import Testing
import WispCore

@testable import Wisp

@Suite("Reset shortcuts", .serialized)
@MainActor
struct ResetShortcutTests {
    @Test("The status menu dispatches the position and size shortcuts")
    func menuDispatchesResetShortcuts() throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        var actions: [KeymapAction] = []
        let controller = MenuBarController(
            perform: { actions.append($0) },
            currentLaunchAtLogin: { false },
            onToggleLaunchAtLogin: {},
            isStorageCustom: { false },
            onPickStorageLocation: {},
            onResetStorageLocation: {})
        controller.apply(Keymap())
        let children = Dictionary(
            uniqueKeysWithValues: Mirror(reflecting: controller).children.compactMap {
                child -> (String, Any)? in
                guard let label = child.label else { return nil }
                return (label, child.value)
            })
        defer {
            if let item = children["statusItem"] as? NSStatusItem {
                NSStatusBar.system.removeStatusItem(item)
            }
        }
        let menu = try #require(children["menu"] as? NSMenu)
        let statusItem = try #require(children["statusItem"] as? NSStatusItem)
        #expect(statusItem.menu === menu)
        menu.autoenablesItems = false

        #expect(!menu.items.contains(where: { $0.title == "Set Shortcut…" }))
        #expect(menu.items.contains(where: { $0.title == "Toggle Panel" }))

        let positionItem = menu.items.first(where: { $0.title == "Reset Position" })
        let sizeItem = menu.items.first(where: { $0.title == "Reset Size" })
        #expect(positionItem?.keyEquivalent == "0")
        #expect(positionItem?.keyEquivalentModifierMask == [.command, .option])
        #expect(sizeItem?.keyEquivalent == "0")
        #expect(sizeItem?.keyEquivalentModifierMask == [.command, .shift])

        let position = try keyEvent(
            UInt16(kVK_ANSI_0), modifiers: [.command, .option], characters: "0")
        #expect(menu.performKeyEquivalent(with: position))
        #expect(actions == [.resetPosition])

        let size = try keyEvent(UInt16(kVK_ANSI_0), modifiers: [.command, .shift], characters: ")")
        #expect(menu.performKeyEquivalent(with: size))
        #expect(actions == [.resetPosition, .resetSize])
        let refresh = try keyEvent(
            UInt16(kVK_ANSI_R), modifiers: [.command], characters: "r")
        #expect(menu.performKeyEquivalent(with: refresh))
        #expect(actions == [.resetPosition, .resetSize, .refresh])

        controller.apply(
            Keymap([
                .resetPosition: "cmd+opt+p", .resetSize: "cmd+shift+9",
            ]))
        #expect(!menu.performKeyEquivalent(with: position))
        #expect(!menu.performKeyEquivalent(with: size))
        let remappedPosition = try keyEvent(
            UInt16(kVK_ANSI_P), modifiers: [.command, .option], characters: "p")
        let remappedSize = try keyEvent(
            UInt16(kVK_ANSI_9), modifiers: [.command, .shift], characters: "(")
        #expect(menu.performKeyEquivalent(with: remappedPosition))
        #expect(menu.performKeyEquivalent(with: remappedSize))
        #expect(
            actions == [.resetPosition, .resetSize, .refresh, .resetPosition, .resetSize])

        controller.apply(Keymap())
        #expect(menu.performKeyEquivalent(with: position))
        #expect(menu.performKeyEquivalent(with: size))
        controller.apply(Keymap([.resetPosition: "", .resetSize: ""]))
        #expect(!menu.performKeyEquivalent(with: position))
        #expect(!menu.performKeyEquivalent(with: size))
        #expect(
            actions
                == [
                    .resetPosition, .resetSize, .refresh, .resetPosition, .resetSize,
                    .resetPosition, .resetSize,
                ])
        #expect(menu.performKeyEquivalent(with: refresh))
        #expect(
            actions
                == [
                    .resetPosition, .resetSize, .refresh, .resetPosition, .resetSize,
                    .resetPosition, .resetSize, .refresh,
                ])
        let toggleIndex = menu.indexOfItem(withTitle: "Toggle Panel")
        #expect(toggleIndex >= 0)
        if toggleIndex >= 0 { menu.performActionForItem(at: toggleIndex) }
        #expect(actions.last == .summon)
    }

    private func keyEvent(
        _ keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        characters: String
    ) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: 0, windowNumber: 0, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))
    }

    @Test("Focused key handling dispatches both reset shortcuts only when focused")
    func focusedPanelDispatchesResetShortcuts() throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        var isFocused = false
        var actions: [KeymapAction] = []
        let monitor = KeyBindingMonitor(
            isPanelFocused: { isFocused }, perform: { actions.append($0) })
        monitor.apply(Keymap())

        let position = try keyEvent(
            UInt16(kVK_ANSI_0), modifiers: [.command, .option], characters: "0")
        let size = try keyEvent(UInt16(kVK_ANSI_0), modifiers: [.command, .shift], characters: ")")

        NSApplication.shared.sendEvent(position)
        NSApplication.shared.sendEvent(size)
        #expect(actions.isEmpty)

        isFocused = true
        NSApplication.shared.sendEvent(position)
        NSApplication.shared.sendEvent(size)
        #expect(actions == [.resetPosition, .resetSize])
    }
}
