import Foundation

/// A surgical editor for the config file's *text*.
///
/// The app mutates settings from its own UI — the theme cycle, the type-size
/// cycle, the shortcut capture, the storage picker, the panel frame — so
/// `wisp.jsonc` has to round-trip. Re-encoding the whole document on every one
/// of those would rewrite key order, re-indent, and drop any comment the user
/// added, which turns `chezmoi diff` into noise and makes hand-editing feel
/// adversarial.
///
/// So instead: find the one value's span in the file text and splice a new
/// literal over it, leaving every other byte — including comments and trailing
/// commas the JSON5 reader allows — exactly where it was.
///
/// This is a *rewriter*, not a parser: it understands enough syntax to find a
/// value's boundaries and nothing more. A key it can't find returns nil, and
/// the caller falls back to a full strict-JSON encode.
public enum JSONTextEdit {
    /// Replaces the value at `path` (e.g. `["keymap", "summon"]`) with
    /// `literal`, which must already be valid JSON for the value it stands in
    /// for. Returns nil when the path isn't present in the text.
    public static func replacingValue(
        in text: String, at path: [String], with literal: String
    ) -> String? {
        guard !path.isEmpty else { return nil }
        let chars = Array(text)
        guard let range = valueRange(in: chars, at: path) else { return nil }
        return String(chars[..<range.lowerBound]) + literal + String(chars[range.upperBound...])
    }

    /// The half-open index range of the value at `path`, or nil.
    static func valueRange(in chars: [Character], at path: [String]) -> Range<Int>? {
        var cursor = skipTrivia(chars, from: 0)
        guard cursor < chars.count, chars[cursor] == "{" else { return nil }

        var range: Range<Int>?
        for (depth, key) in path.enumerated() {
            guard let found = member(named: key, inObjectAt: cursor, chars) else { return nil }
            range = found
            if depth < path.count - 1 {
                // Every step but the last has to land on an object to descend
                // into; a scalar mid-path means the file's shape moved on.
                let start = skipTrivia(chars, from: found.lowerBound)
                guard start < chars.count, chars[start] == "{" else { return nil }
                cursor = start
            }
        }
        return range
    }

    /// Scans one object's immediate members for `key`, returning that
    /// member's value range. Nested objects are skipped wholesale, so a key
    /// that also appears one level down never shadows the one being looked
    /// for.
    private static func member(named key: String, inObjectAt objectStart: Int, _ chars: [Character])
        -> Range<Int>?
    {
        var i = objectStart + 1  // past the '{'
        while true {
            i = skipTrivia(chars, from: i)
            guard i < chars.count else { return nil }
            if chars[i] == "}" { return nil }
            if chars[i] == "," {
                i += 1
                continue
            }
            guard let (name, afterName) = readKey(chars, from: i) else { return nil }
            var j = skipTrivia(chars, from: afterName)
            guard j < chars.count, chars[j] == ":" else { return nil }
            j = skipTrivia(chars, from: j + 1)
            guard let end = valueEnd(chars, from: j) else { return nil }
            if name == key { return j..<end }
            i = end
        }
    }

    /// A member name, quoted (JSON) or bare (JSON5).
    private static func readKey(_ chars: [Character], from index: Int) -> (String, Int)? {
        if chars[index] == "\"" || chars[index] == "'" {
            let quote = chars[index]
            var i = index + 1
            var name = ""
            while i < chars.count {
                if chars[i] == "\\" && i + 1 < chars.count {
                    name.append(chars[i + 1])
                    i += 2
                    continue
                }
                if chars[i] == quote { return (name, i + 1) }
                name.append(chars[i])
                i += 1
            }
            return nil
        }
        var i = index
        var name = ""
        while i < chars.count, chars[i].isLetter || chars[i].isNumber || chars[i] == "_"
            || chars[i] == "$"
        {
            name.append(chars[i])
            i += 1
        }
        return name.isEmpty ? nil : (name, i)
    }

    /// The index just past the value starting at `index`. Objects and arrays
    /// are matched by nesting; scalars run to the first delimiter that isn't
    /// inside a string.
    private static func valueEnd(_ chars: [Character], from index: Int) -> Int? {
        guard index < chars.count else { return nil }
        switch chars[index] {
        case "{", "[":
            var depth = 0
            var i = index
            while i < chars.count {
                let c = chars[i]
                if c == "\"" || c == "'" {
                    guard let after = skipString(chars, from: i) else { return nil }
                    i = after
                    continue
                }
                if c == "/" {
                    let after = skipTrivia(chars, from: i)
                    if after != i {
                        i = after
                        continue
                    }
                }
                if c == "{" || c == "[" { depth += 1 }
                if c == "}" || c == "]" {
                    depth -= 1
                    if depth == 0 { return i + 1 }
                }
                i += 1
            }
            return nil
        case "\"", "'":
            return skipString(chars, from: index)
        default:
            var i = index
            while i < chars.count, chars[i] != ",", chars[i] != "}", chars[i] != "]",
                !chars[i].isNewline
            {
                i += 1
            }
            // Trailing spaces belong to the layout, not to the value.
            while i > index, chars[i - 1].isWhitespace { i -= 1 }
            return i > index ? i : nil
        }
    }

    private static func skipString(_ chars: [Character], from index: Int) -> Int? {
        let quote = chars[index]
        var i = index + 1
        while i < chars.count {
            if chars[i] == "\\" {
                i += 2
                continue
            }
            if chars[i] == quote { return i + 1 }
            i += 1
        }
        return nil
    }

    /// Whitespace plus both JSON5 comment forms — the reason the rewriter can
    /// be pointed at a commented file at all.
    private static func skipTrivia(_ chars: [Character], from index: Int) -> Int {
        var i = index
        while i < chars.count {
            if chars[i].isWhitespace {
                i += 1
                continue
            }
            if chars[i] == "/", i + 1 < chars.count {
                if chars[i + 1] == "/" {
                    while i < chars.count, !chars[i].isNewline { i += 1 }
                    continue
                }
                if chars[i + 1] == "*" {
                    i += 2
                    while i + 1 < chars.count, !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                    i = min(i + 2, chars.count)
                    continue
                }
            }
            break
        }
        return i
    }
}
