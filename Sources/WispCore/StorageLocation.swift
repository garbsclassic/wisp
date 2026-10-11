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
        _ folder: URL, currentText: String, currentFolder: URL,
        removeCurrent: Bool = true, commit: () throws -> Void = {}
    ) throws -> SwitchResult {
        let fm = FileManager.default
        let oldURL = scratchpadURL(in: currentFolder)
        let newURL = scratchpadURL(in: folder)
        if newURL.resolvingSymlinksInPath() == oldURL.resolvingSymlinksInPath() {
            try commit()
            return SwitchResult(text: currentText, backupURL: nil)
        }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let result: SwitchResult
        if fm.fileExists(atPath: newURL.path) {
            let loaded = try String(contentsOf: newURL, encoding: .utf8)
            try fm.createDirectory(at: currentFolder, withIntermediateDirectories: true)
            let name = String(backupFilename().dropLast(3)) + "-\(UUID().uuidString).md"
            let backupURL = currentFolder.appendingPathComponent(name)
            try Data(currentText.utf8).write(to: backupURL, options: .withoutOverwriting)
            result = SwitchResult(text: loaded, backupURL: backupURL)
        } else {
            try currentText.write(to: newURL, atomically: true, encoding: .utf8)
            result = SwitchResult(text: currentText, backupURL: nil)
        }
        // A failed config write leaves the old note and the active location intact.
        try commit()
        if removeCurrent { try? fm.removeItem(at: oldURL) }
        return result
    }

    /// Keeps the custom note for other Macs, and preserves an existing default note.
    public static func resetToDefault(
        currentText: String, currentFolder: URL, commit: () throws -> Void = {}
    ) throws -> SwitchResult {
        try setFolder(
            defaultFolder, currentText: currentText, currentFolder: currentFolder,
            removeCurrent: false, commit: commit)
    }
}
