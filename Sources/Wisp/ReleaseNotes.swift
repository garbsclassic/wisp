import Foundation

/// Extracts the short, human "what's new" bullets from a GitHub release
/// body for display in the in-app update card.
///
/// Convention: a release body starts with a few one-line bullets, then a
/// `<!--wisp:more-->` marker, then any longer prose (install commands,
/// etc.). The marker is an HTML comment, so it's invisible on the GitHub
/// release page — web readers see the whole body, the app shows only the
/// curated bullets above the marker.
enum ReleaseNotes {
    static let marker = "<!--wisp:more-->"
    /// Defensive cap so a malformed body can never fill the card.
    static let maxHighlights = 6

    /// Returns the clean one-line highlights (bullet markers stripped).
    /// Only lines above the marker that begin with a bullet (`-`, `*`,
    /// or `•`) count — intro prose and the long section below the marker
    /// are ignored, so an old release without the convention shows
    /// nothing rather than a wall of text.
    static func highlights(from body: String) -> [String] {
        let head = body.components(separatedBy: marker).first ?? body
        var result: [String] = []
        for rawLine in head.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let stripped = strippedBullet(line) else { continue }
            if !stripped.isEmpty {
                result.append(stripped)
                if result.count == maxHighlights { break }
            }
        }
        return result
    }

    /// If `line` starts with a bullet marker, return the text after it;
    /// otherwise nil (not a bullet line).
    private static func strippedBullet(_ line: String) -> String? {
        for prefix in ["- ", "* ", "• "] {
            if line.hasPrefix(prefix) {
                return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}
