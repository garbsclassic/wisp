import CoreServices
import Foundation

/// Calls back when anything in one directory changes. FSEvents, since atomic saves and sync
/// clients rename over the file and a descriptor watch would follow the replaced one.
/// `@unchecked Sendable`: the stream runs on the main queue, which serialises every touch.
public final class DirectoryWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let onChange: @MainActor () -> Void

    /// Set when live reload couldn't start; the footer shows it so a stale note isn't silent.
    public private(set) var failureDescription: String?

    /// Collapses a burst of writes, such as a sync client landing several files, into one call.
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
            // The stream runs on the main queue.
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
                    | kFSEventStreamCreateFlagIgnoreSelf  // our own writes are in memory
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
