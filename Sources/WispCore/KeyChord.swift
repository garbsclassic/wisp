import Carbon.HIToolbox
import Foundation

/// A parsed hotkey chord, in the form Carbon's hotkey API wants.
///
/// This is what makes `keymap.summon` hand-editable: the config stores
/// `"ctrl+opt+."`, not the pair of Carbon integers the registration wants.
///
/// Key codes are physical positions on an ANSI layout, not typed characters —
/// so `/` means "the key where slash sits on a US keyboard" regardless of the
/// active input source. Good enough here; a non-US layout would need
/// `UCKeyTranslate` to do better.
public struct KeyChord: Equatable, Sendable {
    public let keyCode: UInt32
    public let carbonModifiers: UInt32
    public let raw: String

    public init(keyCode: UInt32, carbonModifiers: UInt32, raw: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.raw = raw
    }

    /// Parses `"cmd+opt+/"`. Order doesn't matter and spacing is ignored;
    /// the last non-modifier token is the key.
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
            if let mask = modifierMasks[token] {
                modifiers |= mask
            } else {
                // A second bare key is a malformed chord, not an override.
                guard keyToken == nil else { return nil }
                keyToken = token
            }
        }

        guard let keyToken, let keyCode = keyCodes[keyToken] else { return nil }
        return KeyChord(keyCode: keyCode, carbonModifiers: modifiers, raw: text)
    }

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

    /// The inverse of `parse` — renders a captured key code and modifier
    /// mask back into a chord string.
    ///
    /// The Set Shortcut… overlay captures an `NSEvent`, and what has to land
    /// in the config is the same text a person would have typed there. An
    /// unmapped key code has no spelling, so it fails rather than writing
    /// something the parser would reject on the next launch.
    public static func string(keyCode: UInt32, carbonModifiers: UInt32) -> String? {
        guard let key = keyNames[keyCode] else { return nil }
        var parts: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 { parts.append("ctrl") }
        if carbonModifiers & UInt32(optionKey) != 0 { parts.append("opt") }
        if carbonModifiers & UInt32(shiftKey) != 0 { parts.append("shift") }
        if carbonModifiers & UInt32(cmdKey) != 0 { parts.append("cmd") }
        parts.append(key)
        return parts.joined(separator: "+")
    }

    /// Key code → the token `parse` prefers for it. Built by inverting
    /// `keyCodes`, keeping the *first* spelling of each code in a fixed
    /// preference order so `.` never comes back as "period" and `esc` never
    /// as "escape" — one code, one canonical spelling, round-tripping.
    private static let keyNames: [UInt32: String] = {
        var names: [UInt32: String] = [:]
        for token in preferredKeyTokens {
            if let code = keyCodes[token], names[code] == nil { names[code] = token }
        }
        for (token, code) in keyCodes where names[code] == nil { names[code] = token }
        return names
    }()

    private static let preferredKeyTokens: [String] = [
        "/", "\\", "[", "]", ",", ".", ";", "\'", "`", "-", "=",
        "space", "return", "tab", "escape", "delete",
        "left", "right", "up", "down",
    ]
}
