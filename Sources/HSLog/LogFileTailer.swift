import Darwin
import Foundation

/// Follows one growing log file from a byte offset.
///
/// Reads are triggered by a vnode `DispatchSource` (low latency, idle when nothing
/// changes) and by the owner's backup poll, because vnode events can be missed
/// across a reopen or rename. Only complete lines are delivered; a line cut by a
/// read is held until its `\n` arrives. The file may not exist yet, may be
/// truncated (reading restarts at 0) or replaced by a new file (reopened from 0).
///
/// Not thread-safe: every call, and every `onLines` callback, happens on `queue`.
final class LogFileTailer {
    static let chunkSize = 1 << 20

    let url: URL
    private let queue: DispatchQueue
    private let onLines: ([String]) -> Void
    private var onCaughtUp: (() -> Void)?

    private var handle: FileHandle?
    private var fileIdentity: (device: dev_t, inode: ino_t)?
    private var offset: UInt64 = 0
    private var splitter = LogLineSplitter()
    private var source: DispatchSourceFileSystemObject?

    /// - Parameters:
    ///   - startOffset: Where to start reading; must be the start of a line.
    ///   - onCaughtUp: Called once, after the first read of what the file already held.
    init(
        url: URL, queue: DispatchQueue, startOffset: UInt64 = 0,
        onLines: @escaping ([String]) -> Void, onCaughtUp: (() -> Void)? = nil
    ) {
        self.url = url
        self.queue = queue
        self.offset = startOffset
        self.onLines = onLines
        self.onCaughtUp = onCaughtUp
    }

    /// Reads everything new since the last read.
    func poll() {
        dispatchPrecondition(condition: .onQueue(queue))
        read()
        if let caughtUp = onCaughtUp {
            onCaughtUp = nil
            caughtUp()
        }
    }

    private func read() {
        var info = stat()
        guard stat(url.path(percentEncoded: false), &info) == 0 else {
            // Gone (or not created yet). Keep the offset: if the same file comes back
            // the identity check below decides whether it's new.
            closeFile()
            return
        }
        let identity = (device: info.st_dev, inode: info.st_ino)
        if let known = fileIdentity, known.device != identity.device || known.inode != identity.inode {
            // Replaced by a different file: start it from the top.
            closeFile()
            resetPosition()
        }
        if handle == nil, !openFile(identity: identity) { return }
        let size = UInt64(info.st_size)
        if size < offset {
            resetPosition()
        }
        guard size > offset, let handle else { return }
        do {
            try handle.seek(toOffset: offset)
            while let chunk = try handle.read(upToCount: Self.chunkSize), !chunk.isEmpty {
                offset += UInt64(chunk.count)
                var lines: [String] = []
                splitter.append(chunk) { lines.append($0) }
                if !lines.isEmpty { onLines(lines) }
            }
        } catch {
            closeFile()
        }
    }

    func stop() {
        dispatchPrecondition(condition: .onQueue(queue))
        closeFile()
    }

    private func resetPosition() {
        offset = 0
        splitter = LogLineSplitter()
    }

    private func openFile(identity: (device: dev_t, inode: ino_t)) -> Bool {
        guard let opened = try? FileHandle(forReadingFrom: url) else { return false }
        handle = opened
        fileIdentity = identity
        watch()
        return true
    }

    private func closeFile() {
        source?.cancel()
        source = nil
        try? handle?.close()
        handle = nil
    }

    private func watch() {
        let descriptor = open(url.path(percentEncoded: false), O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.extend, .write, .delete, .rename],
            queue: queue
        )
        source.setEventHandler { [weak self] in self?.poll() }
        source.setCancelHandler { close(descriptor) }
        self.source = source
        source.activate()
    }
}
