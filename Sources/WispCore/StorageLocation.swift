import Foundation

/// Where `scratchpad.md` lives on disk.
///
/// Default: `~/Documents/scratchpad.md`. The user can pick any folder
/// from the menu bar menu — putting it inside
/// `~/Library/Mobile Documents/com~apple~CloudDocs/...` (iCloud Drive),
/// `~/Dropbox/...`, or any sync tool's folder makes Wisp's scratchpad
/// follow the user across machines for free, since macOS handles that
/// folder's syncing for us.
///
/// Tradeoff: file-system sync isn't conflict-aware. Typing on two Macs
/// at the same instant can produce a `scratchpad (Mac-X's conflicted
/// copy).md` file that Wisp doesn't merge automatically. The single-
/// person-many-Macs case rarely hits this.
/// The folder is passed in rather than read here: `wisp.jsonc` is the single
/// source of truth for it, and a helper that reached for UserDefaults behind
/// the caller's back would quietly reintroduce the shadow store.
public enum StorageLocation {
    /// The pre-config UserDefaults key. Read once on first run to seed
    /// `scratchpadPath`, then never again.
    public static let legacyFolderKey = "ScratchpadFolder"
    public static let scratchpadFilename = "scratchpad.md"
    public static let backupPrefix = "scratchpad-local-backup-"

    /// `~/Documents/`
    public static var defaultFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    /// Resolve a configured `scratchpadPath` to a folder. Empty means the
    /// default; a leading `~` expands, so the path is writable by hand.
    public static func folder(forConfiguredPath path: String) -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return defaultFolder }
        return URL(fileURLWithPath: NSString(string: trimmed).expandingTildeInPath)
    }

    public static func isCustom(_ path: String) -> Bool {
        !path.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Pure: compose the scratchpad file URL inside a given folder.
    public static func scratchpadURL(in folder: URL) -> URL {
        folder.appendingPathComponent(scratchpadFilename)
    }

    /// Pure: timestamped backup filename used when a folder switch
    /// would otherwise overwrite the user's local text.
    public static func backupFilename(at date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime]
        let stamp = formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
        return "\(backupPrefix)\(stamp).md"
    }

    /// Outcome of switching folders. Drives the UI (whether to swap
    /// the in-memory text for the loaded existing file, and whether to
    /// surface a backup-was-saved message).
    public struct SwitchResult {
        public let newText: String
        public let backupURL: URL?
        public let loadedExisting: Bool
        /// The path to persist into `scratchpadPath`. Empty for the default
        /// folder, so a reset clears the key rather than pinning it.
        public let folderPath: String
    }

    /// Switch to a new folder. Two paths:
    /// - destination is empty → move local text there
    /// - destination has its own scratchpad.md → save a timestamped
    ///   backup of the local text in the old folder, then load the
    ///   existing file (the "Mac B joining iCloud sync" case)
    public static func setFolder(
        _ folder: URL, currentText: String, currentFolder: URL
    ) throws -> SwitchResult {
        let fm = FileManager.default
        let oldURL = scratchpadURL(in: currentFolder)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let newURL = scratchpadURL(in: folder)

        // Same folder — nothing to do.
        if (newURL.standardizedFileURL.path) == (oldURL.standardizedFileURL.path) {
            return SwitchResult(
                newText: currentText, backupURL: nil, loadedExisting: false,
                folderPath: folder.path)
        }

        if fm.fileExists(atPath: newURL.path) {
            let backupURL = oldURL.deletingLastPathComponent()
                .appendingPathComponent(backupFilename())
            try? currentText.write(to: backupURL, atomically: true, encoding: .utf8)
            let loaded = (try? String(contentsOf: newURL, encoding: .utf8)) ?? currentText
            // Stop pointing at the old file; remove it so the old
            // location doesn't keep getting stale writes.
            try? fm.removeItem(at: oldURL)
            return SwitchResult(
                newText: loaded, backupURL: backupURL, loadedExisting: true,
                folderPath: folder.path)
        } else {
            try currentText.write(to: newURL, atomically: true, encoding: .utf8)
            try? fm.removeItem(at: oldURL)
            return SwitchResult(
                newText: currentText, backupURL: nil, loadedExisting: false,
                folderPath: folder.path)
        }
    }

    /// Switch back to the default folder. Copies current text to the
    /// default location and clears the custom path. The custom-folder
    /// file is *not* deleted — other Macs may still be syncing through
    /// it, and removing it here would yank their content too.
    public static func resetToDefault(currentText: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: defaultFolder, withIntermediateDirectories: true)
        let defaultURL = scratchpadURL(in: defaultFolder)
        try currentText.write(to: defaultURL, atomically: true, encoding: .utf8)
    }
}
