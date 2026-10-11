import Foundation

/// Splices or inserts one config value while preserving unrelated text.
public enum JSONTextEdit {
    /// `literal` must already be valid JSON. Nil for an incompatible path.
    public static func replacingValue(
        in text: String, at path: [String], with literal: String
    ) -> String? {
        guard !path.isEmpty else { return nil }
        var chars = Array(text)
        var cursor = skipTrivia(chars, from: 0)
        guard cursor < chars.count, chars[cursor] == "{" else { return nil }
        for (depth, key) in path.enumerated() {
            if let found = member(named: key, inObjectAt: cursor, chars) {
                if depth == path.count - 1 {
                    chars.replaceSubrange(found, with: literal)
                    return String(chars)
                }
                guard chars[found.lowerBound] == "{" else { return nil }
                cursor = found.lowerBound
                continue
            }
            guard let objectEnd = valueEnd(chars, from: cursor) else { return nil }
            var end = objectEnd - 1
            // Add the separator beside the previous value, ahead of its trailing comments.
            var i = cursor + 1
            var lastEnd: Int?
            while true {
                i = skipTrivia(chars, from: i)
                if i >= end { break }
                if chars[i] == "," { i += 1; continue }
                guard let (_, afterName) = readKey(chars, from: i) else { return nil }
                let colon = skipTrivia(chars, from: afterName)
                guard colon < end, chars[colon] == ":",
                    let afterValue = valueEnd(chars, from: skipTrivia(chars, from: colon + 1))
                else { return nil }
                lastEnd = afterValue
                i = afterValue
            }
            if let lastEnd, chars[skipTrivia(chars, from: lastEnd)] != "," {
                chars.insert(",", at: lastEnd)
                end += 1
            }
            var nested = literal
            for name in path.dropFirst(depth + 1).reversed() {
                guard let quoted = ConfigStore.jsonLiteral(for: name) else { return nil }
                nested = "{\(quoted): \(nested)}"
            }
            guard let quoted = ConfigStore.jsonLiteral(for: key) else { return nil }
            let object = String(chars[cursor...end])
            if let newline = object.first(where: \.isNewline).map(String.init) {
                var lineStart = end
                while lineStart > cursor, !chars[lineStart - 1].isNewline { lineStart -= 1 }
                let closingIndent = String(chars[lineStart..<end].prefix { $0 == " " || $0 == "\t" })
                var first = skipTrivia(chars, from: cursor + 1)
                while first > cursor, !chars[first - 1].isNewline { first -= 1 }
                let memberIndent = String(chars[first..<end].prefix { $0 == " " || $0 == "\t" })
                let indent = memberIndent.count > closingIndent.count
                    ? memberIndent : closingIndent + "  "
                if chars[lineStart..<end].allSatisfy({ $0.isWhitespace }) {
                    chars.insert(contentsOf: "\(indent)\(quoted): \(nested)\(newline)", at: lineStart)
                } else {
                    chars.insert(
                        contentsOf: "\(newline)\(indent)\(quoted): \(nested)\(newline)\(closingIndent)",
                        at: end)
                }
            } else {
                chars.insert(contentsOf: " \(quoted): \(nested) ", at: end)
            }
            return String(chars)
        }
        return nil
    }

    /// Immediate members only, so a same-named key one level down can't shadow `key`.
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
        let end: Int
        if chars[index] == "\"" || chars[index] == "'" {
            guard let after = skipString(chars, from: index) else { return nil }
            end = after
        } else {
            var i = index
            while i < chars.count, chars[i].isLetter || chars[i].isNumber || chars[i] == "_"
                || chars[i] == "$" || chars[i] == "\\"
            {
                i += 1
            }
            guard i > index else { return nil }
            end = i
        }
        let key = String(chars[index..<end])
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        guard let object = try? decoder.decode(
            [String: Int].self, from: Data("{\(key):0}".utf8)), let name = object.keys.first
        else { return nil }
        return (name, end)
    }

    /// The index just past the value at `index`.
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
                if chars[i] == "/", i + 1 < chars.count,
                    chars[i + 1] == "/" || chars[i + 1] == "*" { break }
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

    /// Whitespace and both comment forms.
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
