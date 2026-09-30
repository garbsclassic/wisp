import AppKit
import Carbon.HIToolbox
import Foundation

/// A hotkey chord parsed from config text such as `"ctrl+opt+."`. Key codes are physical ANSI
/// positions, so `/` is wherever slash sits on a US keyboard, whatever the input source.
public struct KeyChord: Equatable, Sendable {
    public let keyCode: UInt32
    public let carbonModifiers: UInt32

    public init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    /// Order and spacing don't matter; the one non-modifier token is the key.
    public static func parse(_ text: String) -> KeyChord? {
        let tokens =
            text
            .lowercased()
            .split(separator: "+", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }

        var modifiers: UInt32 = 0
        var keyToken: String?

        for token in tokens {
            if hyperSpellings.contains(token) {
                modifiers |= hyperMask
            } else if let mask = modifierMasks[token] {
                modifiers |= mask
            } else {
                // A second bare key is a malformed chord, not an override.
                guard keyToken == nil else { return nil }
                keyToken = token
            }
        }

        guard let keyToken, let keyCode = keyCodes[keyToken] else { return nil }
        return KeyChord(keyCode: keyCode, carbonModifiers: modifiers)
    }

    /// The glyph is accepted because the help page prints it, as with `⌘`. Follows Clef.
    private static let hyperSpellings: Set<String> = ["hyper", hyperGlyph]

    private static let hyperMask: UInt32 =
        UInt32(controlKey) | UInt32(optionKey) | UInt32(shiftKey) | UInt32(cmdKey)

    private static let modifierMasks: [String: UInt32] = [
        "cmd": UInt32(cmdKey), "command": UInt32(cmdKey), "⌘": UInt32(cmdKey),
        "opt": UInt32(optionKey), "option": UInt32(optionKey), "alt": UInt32(optionKey),
        "⌥": UInt32(optionKey),
        "shift": UInt32(shiftKey), "⇧": UInt32(shiftKey),
        "ctrl": UInt32(controlKey), "control": UInt32(controlKey), "⌃": UInt32(controlKey),
    ]

    private static let keyCodes: [String: UInt32] = {
        var codes: [String: UInt32] = [
            "a": UInt32(kVK_ANSI_A), "b": UInt32(kVK_ANSI_B), "c": UInt32(kVK_ANSI_C),
            "d": UInt32(kVK_ANSI_D), "e": UInt32(kVK_ANSI_E), "f": UInt32(kVK_ANSI_F),
            "g": UInt32(kVK_ANSI_G), "h": UInt32(kVK_ANSI_H), "i": UInt32(kVK_ANSI_I),
            "j": UInt32(kVK_ANSI_J), "k": UInt32(kVK_ANSI_K), "l": UInt32(kVK_ANSI_L),
            "m": UInt32(kVK_ANSI_M), "n": UInt32(kVK_ANSI_N), "o": UInt32(kVK_ANSI_O),
            "p": UInt32(kVK_ANSI_P), "q": UInt32(kVK_ANSI_Q), "r": UInt32(kVK_ANSI_R),
            "s": UInt32(kVK_ANSI_S), "t": UInt32(kVK_ANSI_T), "u": UInt32(kVK_ANSI_U),
            "v": UInt32(kVK_ANSI_V), "w": UInt32(kVK_ANSI_W), "x": UInt32(kVK_ANSI_X),
            "y": UInt32(kVK_ANSI_Y), "z": UInt32(kVK_ANSI_Z),
            "0": UInt32(kVK_ANSI_0), "1": UInt32(kVK_ANSI_1), "2": UInt32(kVK_ANSI_2),
            "3": UInt32(kVK_ANSI_3), "4": UInt32(kVK_ANSI_4), "5": UInt32(kVK_ANSI_5),
            "6": UInt32(kVK_ANSI_6), "7": UInt32(kVK_ANSI_7), "8": UInt32(kVK_ANSI_8),
            "9": UInt32(kVK_ANSI_9),
            "/": UInt32(kVK_ANSI_Slash), "slash": UInt32(kVK_ANSI_Slash),
            "\\": UInt32(kVK_ANSI_Backslash), "backslash": UInt32(kVK_ANSI_Backslash),
            "[": UInt32(kVK_ANSI_LeftBracket), "leftbracket": UInt32(kVK_ANSI_LeftBracket),
            "]": UInt32(kVK_ANSI_RightBracket), "rightbracket": UInt32(kVK_ANSI_RightBracket),
            ",": UInt32(kVK_ANSI_Comma), "comma": UInt32(kVK_ANSI_Comma),
            ".": UInt32(kVK_ANSI_Period), "period": UInt32(kVK_ANSI_Period),
            ";": UInt32(kVK_ANSI_Semicolon), "semicolon": UInt32(kVK_ANSI_Semicolon),
            "'": UInt32(kVK_ANSI_Quote), "quote": UInt32(kVK_ANSI_Quote),
            "`": UInt32(kVK_ANSI_Grave), "grave": UInt32(kVK_ANSI_Grave),
            "-": UInt32(kVK_ANSI_Minus), "minus": UInt32(kVK_ANSI_Minus),
            "=": UInt32(kVK_ANSI_Equal), "equal": UInt32(kVK_ANSI_Equal),
            "space": UInt32(kVK_Space), "return": UInt32(kVK_Return),
            "enter": UInt32(kVK_Return), "tab": UInt32(kVK_Tab),
            "escape": UInt32(kVK_Escape), "esc": UInt32(kVK_Escape),
            "delete": UInt32(kVK_Delete),
            "left": UInt32(kVK_LeftArrow), "right": UInt32(kVK_RightArrow),
            "up": UInt32(kVK_UpArrow), "down": UInt32(kVK_DownArrow),
        ]
        for index in 1...12 {
            let fKeys: [UInt32] = [
                UInt32(kVK_F1), UInt32(kVK_F2), UInt32(kVK_F3), UInt32(kVK_F4),
                UInt32(kVK_F5), UInt32(kVK_F6), UInt32(kVK_F7), UInt32(kVK_F8),
                UInt32(kVK_F9), UInt32(kVK_F10), UInt32(kVK_F11), UInt32(kVK_F12),
            ]
            codes["f\(index)"] = fKeys[index - 1]
        }
        return codes
    }()

    // MARK: Modifiers

    /// The Carbon mask as AppKit flags. `CGEventFlags` shares these bits, so
    /// `CGEventFlags(rawValue:)` converts it again.
    public var modifierFlags: NSEvent.ModifierFlags {
        Self.modifierBits.reduce(into: []) { flags, pair in
            if carbonModifiers & pair.carbon != 0 { flags.insert(pair.flag) }
        }
    }

    /// The Carbon mask for a key event's flags, counting only the four chord
    /// modifiers — an arrow also carries `.function` and `.numericPad`.
    public static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        modifierBits.reduce(0) { mask, pair in
            flags.contains(pair.flag) ? mask | pair.carbon : mask
        }
    }

    private static let modifierBits: [(carbon: UInt32, flag: NSEvent.ModifierFlags)] = [
        (UInt32(controlKey), .control), (UInt32(optionKey), .option),
        (UInt32(shiftKey), .shift), (UInt32(cmdKey), .command),
    ]

    // MARK: Display

    /// All four modifiers, as a remapped Caps Lock sends them: one glyph, not `⌃⌥⇧⌘`.
    public static let hyperGlyph = "❖"

    /// "⌥Space", "⇧⌘P", or "❖.", with modifiers always in ⌃⌥⇧⌘ order.
    public var displayString: String {
        var s = ""
        if carbonModifiers & Self.hyperMask == Self.hyperMask {
            s = Self.hyperGlyph
        } else {
            if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
            if carbonModifiers & UInt32(optionKey) != 0 { s += "⌥" }
            if carbonModifiers & UInt32(shiftKey) != 0 { s += "⇧" }
            if carbonModifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        }
        return s + (Self.displayNames[Int(keyCode)] ?? "Key\(keyCode)")
    }

    private static let displayNames: [Int: String] = [
        kVK_Space: "Space",
        kVK_Return: "↩",
        kVK_Tab: "⇥",
        kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋",
        kVK_LeftArrow: "←",
        kVK_RightArrow: "→",
        kVK_UpArrow: "↑",
        kVK_DownArrow: "↓",
        kVK_Home: "↖",
        kVK_End: "↘",
        kVK_PageUp: "⇞",
        kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
        kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
        kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
        kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
        kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Period: ".", kVK_ANSI_Comma: ",",
        kVK_ANSI_Slash: "/", kVK_ANSI_Backslash: "\\",
        kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'",
        kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Minus: "−", kVK_ANSI_Equal: "=",
        kVK_ANSI_Grave: "`",
    ]

    // MARK: Config spelling

    /// The inverse of `parse`, for the Set Shortcut… capture. Nil for an unmapped key code rather
    /// than a string the parser would reject.
    public static func string(keyCode: UInt32, carbonModifiers: UInt32) -> String? {
        guard let key = keyNames[keyCode] else { return nil }
        // `hyper+.` rather than the four-word form, which parses but reads badly.
        if carbonModifiers & hyperMask == hyperMask { return "hyper+\(key)" }
        var parts: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 { parts.append("ctrl") }
        if carbonModifiers & UInt32(optionKey) != 0 { parts.append("opt") }
        if carbonModifiers & UInt32(shiftKey) != 0 { parts.append("shift") }
        if carbonModifiers & UInt32(cmdKey) != 0 { parts.append("cmd") }
        parts.append(key)
        return parts.joined(separator: "+")
    }

    /// One canonical token per key code, preferring `preferredKeyTokens`: `.` over "period",
    /// "escape" over "esc".
    private static let keyNames: [UInt32: String] = {
        var names: [UInt32: String] = [:]
        for token in preferredKeyTokens {
            if let code = keyCodes[token], names[code] == nil { names[code] = token }
        }
        for (token, code) in keyCodes where names[code] == nil { names[code] = token }
        return names
    }()

    /// What an `NSMenuItem` wants: AppKit matches the character, not the key code, and arrows use
    /// its function-key scalars. Shift stays in the mask; an uppercase character draws a second ⇧.
    public var menuEquivalent: (character: String, modifiers: NSEvent.ModifierFlags)? {
        guard let character = Self.menuCharacters[keyCode] else { return nil }
        return (character, modifierFlags)
    }

    private static let menuCharacters: [UInt32: String] = {
        var map: [UInt32: String] = [:]
        for token in preferredKeyTokens where token.count == 1 {
            if let code = keyCodes[token] { map[code] = token }
        }
        for (token, code) in keyCodes where token.count == 1 && map[code] == nil {
            map[code] = token
        }
        let functionKeys: [(Int, Int)] = [
            (kVK_UpArrow, NSUpArrowFunctionKey), (kVK_DownArrow, NSDownArrowFunctionKey),
            (kVK_LeftArrow, NSLeftArrowFunctionKey), (kVK_RightArrow, NSRightArrowFunctionKey),
            (kVK_Home, NSHomeFunctionKey), (kVK_End, NSEndFunctionKey),
            (kVK_PageUp, NSPageUpFunctionKey), (kVK_PageDown, NSPageDownFunctionKey),
            (kVK_F1, NSF1FunctionKey), (kVK_F2, NSF2FunctionKey), (kVK_F3, NSF3FunctionKey),
            (kVK_F4, NSF4FunctionKey), (kVK_F5, NSF5FunctionKey), (kVK_F6, NSF6FunctionKey),
            (kVK_F7, NSF7FunctionKey), (kVK_F8, NSF8FunctionKey), (kVK_F9, NSF9FunctionKey),
            (kVK_F10, NSF10FunctionKey), (kVK_F11, NSF11FunctionKey), (kVK_F12, NSF12FunctionKey),
        ]
        for (code, scalar) in functionKeys {
            map[UInt32(code)] = String(UnicodeScalar(UInt32(scalar))!)
        }
        map[UInt32(kVK_Space)] = " "
        map[UInt32(kVK_Return)] = "\r"
        map[UInt32(kVK_Tab)] = "\t"
        map[UInt32(kVK_Delete)] = String(UnicodeScalar(UInt32(NSBackspaceCharacter))!)
        return map
    }()

    private static let preferredKeyTokens: [String] = [
        "/", "\\", "[", "]", ",", ".", ";", "\'", "`", "-", "=",
        "space", "return", "tab", "escape", "delete",
        "left", "right", "up", "down",
    ]
}
