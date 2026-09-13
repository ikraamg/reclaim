import Foundation
import CoreServices

/// One FSEvents stream over the config file's directory; the directory need not exist when it starts.
@MainActor
final class ConfigWatcher {
    private let fileURL: URL
    private let onChange: @MainActor () -> Void
    private var stream: FSEventStreamRef?
    private var reload: Task<Void, Never>?

    init(fileURL: URL, onChange: @escaping @MainActor () -> Void) {
        self.fileURL = fileURL
        self.onChange = onChange
    }

    func start() {
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<ConfigWatcher>.fromOpaque(info).takeUnretainedValue()
            let changed = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as! [String]
            MainActor.assumeIsolated { watcher.pathsChanged(changed) }
        }
        let flags = kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer
        guard let stream = FSEventStreamCreate(nil, callback, &context,
                                               [fileURL.deletingLastPathComponent().path] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0,
                                               FSEventStreamCreateFlags(flags)) else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    func stop() {
        reload?.cancel()
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func pathsChanged(_ paths: [String]) {
        guard paths.contains(where: { $0.hasSuffix("/" + fileURL.lastPathComponent) }) else { return }
        reload?.cancel()
        reload = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            onChange()
        }
    }
}
