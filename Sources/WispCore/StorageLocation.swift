import Foundation

/// Where `scratchpad.md` lives: `~/Documents` unless the config names a folder. A synced folder
/// carries the note across Macs, but its sync isn't conflict-aware. The folder is always passed
/// in, since `wisp.jsonc` is its only store.
public enum StorageLocation {
    public static let scratchpadFilename = "scratchpad.md"
    public static let backupPrefix = "scratchpad-local-backup-"

    public static var defaultFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    /// Empty means the default; a leading `~` expands.
    public static func folder(forConfiguredPath path: String) -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return defaultFolder }
        return URL(fileURLWithPath: NSString(string: trimmed).expandingTildeInPath)
    }

    public static func isCustom(_ path: String) -> Bool {
        !path.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public static func scratchpadURL(in folder: URL) -> URL {
        folder.appendingPathComponent(scratchpadFilename)
    }

    /// Names the backup kept when a folder switch would overwrite the local text.
    public static func backupFilename(at date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime]
        let stamp = formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
        return "\(backupPrefix)\(stamp).md"
    }

    /// `backupURL` is set when an existing file replaced the local text.
    public struct SwitchResult {
        public let text: String
        public let backupURL: URL?
    }

    /// Moves the local text to `folder`, unless it already holds a scratchpad: then the local
    /// text is backed up in the old folder and the existing file loads.
    public static func setFolder(
        _ folder: URL, currentText: String, currentFolder: URL
    ) throws -> SwitchResult {
        let fm = FileManager.default
        let oldURL = scratchpadURL(in: currentFolder)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let newURL = scratchpadURL(in: folder)

        if (newURL.standardizedFileURL.path) == (oldURL.standardizedFileURL.path) {
            return SwitchResult(text: currentText, backupURL: nil)
        }

        if fm.fileExists(atPath: newURL.path) {
            let backupURL = oldURL.deletingLastPathComponent()
                .appendingPathComponent(backupFilename())
            try? currentText.write(to: backupURL, atomically: true, encoding: .utf8)
            let loaded = (try? String(contentsOf: newURL, encoding: .utf8)) ?? currentText
            // The local text is in the backup now.
            try? fm.removeItem(at: oldURL)
            return SwitchResult(text: loaded, backupURL: backupURL)
        } else {
            try currentText.write(to: newURL, atomically: true, encoding: .utf8)
            try? fm.removeItem(at: oldURL)
            return SwitchResult(text: currentText, backupURL: nil)
        }
    }

    /// Leaves the custom folder's file in place: other Macs may still sync through it.
    public static func resetToDefault(currentText: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: defaultFolder, withIntermediateDirectories: true)
        let defaultURL = scratchpadURL(in: defaultFolder)
        try currentText.write(to: defaultURL, atomically: true, encoding: .utf8)
    }
}
