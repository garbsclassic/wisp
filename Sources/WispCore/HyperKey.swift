import Foundation

/// The modifier combination represented by `hyper` and `❖` in the keymap.
public struct HyperKey: Codable, Equatable, Sendable {
    public static let standard = HyperKey("ctrl+opt+shift+cmd")!

    public let rawValue: String
    public let carbonModifiers: UInt32

    public init?(_ text: String) {
        let tokens = text.lowercased().split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var mask: UInt32 = 0
        for token in tokens {
            guard let modifier = KeyChord.modifierMask(for: token) else { return nil }
            mask |= modifier
        }
        guard mask != 0 else { return nil }
        rawValue = text
        carbonModifiers = mask
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let value = Self(text) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Expected a nonempty combination of modifiers")
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
