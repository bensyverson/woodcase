//
//  InotifyFileWatchBackend.swift
//  Woodcase
//

#if canImport(Glibc)
    import Dispatch
    import Foundation
    import Glibc
    import Synchronization

    /// inotify on each file's parent directory, filtered by name.
    ///
    /// Watching the directory rather than the file is what makes the delete-then-recreate
    /// case free: the directory's `create`, `moved_to` and `delete` events name the file
    /// whether or not an inode is currently behind it, so there is nothing to re-arm.
    final class InotifyFileWatchBackend: FileWatchBackend {
        /// Creates a backend, or returns `nil` when the kernel refuses an inotify instance.
        ///
        /// - Parameter onEvent: Called with each path that may have changed.
        init?(onEvent: @escaping @Sendable (String) -> Void) {
            let descriptor = inotify_init1(Int32(IN_NONBLOCK) | Int32(IN_CLOEXEC))
            guard descriptor >= 0 else { return nil }
            self.descriptor = descriptor
            self.onEvent = onEvent
            let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
            source.setEventHandler { [weak self] in self?.readEvents() }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            readSource.withLock { $0 = source }
        }

        deinit {
            readSource.withLock { $0?.cancel() }
        }

        func watch(path: String) -> Bool {
            let directory = Self.parentDirectory(of: path)
            let name = URL(fileURLWithPath: path).lastPathComponent
            return state.withLock { state in
                let watch: Int32
                if let existing = state.watchByDirectory[directory] {
                    watch = existing
                } else {
                    let mask = UInt32(IN_MODIFY) | UInt32(IN_CLOSE_WRITE) | UInt32(IN_ATTRIB)
                        | UInt32(IN_CREATE) | UInt32(IN_DELETE) | UInt32(IN_MOVED_FROM) | UInt32(IN_MOVED_TO)
                    watch = inotify_add_watch(descriptor, directory, mask)
                    guard watch >= 0 else { return false }
                    state.watchByDirectory[directory] = watch
                }
                state.pathsByWatch[watch, default: [:]][name] = path
                return true
            }
        }

        var watchedCount: Int {
            state.withLock { $0.pathsByWatch.values.reduce(0) { $0 + $1.count } }
        }

        func stop() {
            state.withLock { state in
                state.watchByDirectory.removeAll()
                state.pathsByWatch.removeAll()
            }
        }

        // MARK: - Private

        private struct State {
            var watchByDirectory: [String: Int32] = [:]
            /// Per watch descriptor: file name to the full path it was registered as.
            var pathsByWatch: [Int32: [String: String]] = [:]
        }

        private let descriptor: Int32
        private let onEvent: @Sendable (String) -> Void
        private let queue = DispatchQueue(label: "dev.woodcase.filewatcher.inotify")
        private let state = Mutex(State())
        private let readSource = Mutex<(any DispatchSourceRead)?>(nil)

        /// Drains the inotify descriptor, reporting each event whose name is watched.
        private func readEvents() {
            var buffer = [UInt8](repeating: 0, count: 8192)
            let headerSize = MemoryLayout<inotify_event>.size
            while true {
                let count = read(descriptor, &buffer, buffer.count)
                guard count > 0 else { return }
                var offset = 0
                while offset + headerSize <= count {
                    let watch = buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Int32.self) }
                    let length = buffer.withUnsafeBytes {
                        Int($0.loadUnaligned(fromByteOffset: offset + 12, as: UInt32.self))
                    }
                    let nameBytes = buffer[(offset + headerSize) ..< min(offset + headerSize + length, count)]
                    let name = String(decoding: nameBytes.prefix { $0 != 0 }, as: UTF8.self)
                    offset += headerSize + length
                    if let path = state.withLock({ $0.pathsByWatch[watch]?[name] }) {
                        onEvent(path)
                    }
                }
            }
        }
    }
#endif
