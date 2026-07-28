//
//  LibraryFileWatcher.swift
//  Canvas Library
//
//  Recursive FSEvents watcher for library space roots.
//

import CoreServices
import Foundation

/// Watches one or more directory roots and delivers debounced path batches
/// on a private queue. Callers hop to MainActor as needed.
final class LibraryFileWatcher {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.ryanloechner.canvaslibrary.fsevents")
    private var roots: [String] = []
    /// Invoked on `queue` with absolute paths that changed (files or dirs).
    var onPathsChanged: (([String]) -> Void)?

    deinit {
        stop()
    }

    /// Replace watched roots. Empty list stops the stream.
    func setRoots(_ urls: [URL]) {
        let normalized = urls
            .map { $0.standardizedFileURL.path }
            .filter { FileManager.default.fileExists(atPath: $0) }
            .sorted()
        guard normalized != roots else { return }
        roots = normalized
        restart()
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func restart() {
        stop()
        guard !roots.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let paths = roots as CFArray
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { (_, info, numEvents, eventPaths, _, _) in
                guard let info else { return }
                let watcher = Unmanaged<LibraryFileWatcher>.fromOpaque(info).takeUnretainedValue()
                guard let pathArray = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else {
                    return
                }
                let count = Int(numEvents)
                let paths = Array(pathArray.prefix(count))
                guard !paths.isEmpty else { return }
                watcher.onPathsChanged?(paths)
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.35,
            flags
        ) else {
            return
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }
}
