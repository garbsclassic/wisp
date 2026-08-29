import CoreServices
import Foundation

/// Watches one directory and calls back when anything inside it changes.
///
/// FSEvents rather than a `DispatchSource` on the directory's descriptor:
/// every writer Wisp cares about — its own atomic saves, iCloud Drive,
/// Dropbox, Syncthing, a chezmoi apply — replaces the file by writing a
/// temporary one and renaming over the original. A descriptor watch follows
/// the file that was replaced; FSEvents reports the directory, which is what
/// actually happened. Ported from Clef's VaultWatcher.
///
/// `@unchecked Sendable` because the C callback hands back an opaque pointer
/// to `self`: the stream is dispatched to the main queue, so every touch of
/// the instance is already serialised there.
public final class DirectoryWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let onChange: @MainActor () -> Void

    /// Non-nil when the stream couldn't be created or started — live reload
    /// is off for this directory until relaunch. Surfaced in the footer
    /// rather than left as silent staleness, since the failure mode is a
    /// panel quietly showing yesterday's note.
    public private(set) var failureDescription: String?

    /// `IgnoreSelf` drops the events Wisp causes itself — every debounced
    /// note save and every config write comes back as one otherwise, and
    /// what it would report is already in memory.
    ///
    /// Bursts of writes — a sync client landing several files, or an editor
    /// saving twice in a second — collapse into one callback.
    private static let coalescingInterval: CFTimeInterval = 0.3

    public init(directoryURL: URL, onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
            // Dispatched to the main queue below, so this already is the
            // main actor — the compiler just can't see through the C call.
            MainActor.assumeIsolated { watcher.onChange() }
        }

        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [directoryURL.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            Self.coalescingInterval,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents
                    | kFSEventStreamCreateFlagNoDefer
                    | kFSEventStreamCreateFlagIgnoreSelf
            )
        )

        guard let stream else {
            failureDescription = Self.failure(for: directoryURL)
            return
        }
        FSEventStreamSetDispatchQueue(stream, .main)
        if !FSEventStreamStart(stream) {
            failureDescription = Self.failure(for: directoryURL)
        }
    }

    private static func failure(for url: URL) -> String {
        "Not watching \(url.path) — changes there won't appear until you Refresh (⌘R)"
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
