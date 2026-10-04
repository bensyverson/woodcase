//
//  DarwinFileWatchBackend.swift
//  Woodcase
//

#if canImport(Darwin)
    import Darwin
    import Dispatch
    import Foundation
    import Synchronization

    /// kqueue, through Dispatch: a source on each file **and** one on its directory.
    ///
    /// A source on the file alone follows the inode, so it goes quiet when an atomic
    /// replace unlinks that inode — and, worse, when the path is deleted and recreated
    /// by someone else, there is no inode to re-open at the moment the delete fires. The
    /// directory source is what sees the recreate: its event re-arms every watched path
    /// that is missing or now names a different inode, and reports it.
    final class DarwinFileWatchBackend: FileWatchBackend {
        /// Creates a backend.
        ///
        /// - Parameter onEvent: Called with each path that may have changed.
        init(onEvent: @escaping @Sendable (String) -> Void) {
            self.onEvent = onEvent
        }

        deinit {
            stop()
        }

        func watch(path: String) -> Bool {
            let directory = Self.parentDirectory(of: path)
            return state.withLock { state in
                guard !state.isStopped else { return false }
                if state.directories[directory] == nil {
                    guard let source = makeDirectorySource(directory) else { return false }
                    state.directories[directory] = Directory(source: source, paths: [])
                }
                state.directories[directory]?.paths.insert(path)
                state.files[path] = arm(path)
                return true
            }
        }

        var watchedCount: Int {
            state.withLock(\.files.count)
        }

        func stop() {
            state.withLock { state in
                state.isStopped = true
                for file in state.files.values {
                    file.source?.cancel()
                }
                for directory in state.directories.values {
                    directory.source.cancel()
                }
                state.files.removeAll()
                state.directories.removeAll()
            }
        }

        // MARK: - Private

        /// A watched file: the live source and the inode it was armed on, both `nil`
        /// while the path does not exist.
        private struct Armed {
            var source: (any DispatchSourceFileSystemObject)?
            var inode: UInt64?
        }

        private struct Directory {
            var source: any DispatchSourceFileSystemObject
            var paths: Set<String>
        }

        private struct State {
            var files: [String: Armed] = [:]
            var directories: [String: Directory] = [:]
            var isStopped = false
        }

        private let onEvent: @Sendable (String) -> Void
        private let queue = DispatchQueue(label: "dev.woodcase.filewatcher.darwin")
        private let state = Mutex(State())

        private func makeDirectorySource(_ directory: String) -> (any DispatchSourceFileSystemObject)? {
            let descriptor = open(directory, O_EVTONLY)
            guard descriptor >= 0 else { return nil }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .delete, .rename, .revoke],
                queue: queue
            )
            source.setEventHandler { [weak self] in self?.directoryChanged(directory) }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            return source
        }

        /// Opens a path and arms a source on it; an `Armed` with no source if it is missing.
        private func arm(_ path: String) -> Armed {
            let descriptor = open(path, O_EVTONLY)
            guard descriptor >= 0 else { return Armed(source: nil, inode: nil) }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .extend, .attrib, .delete, .rename, .revoke],
                queue: queue
            )
            source.setEventHandler { [weak self] in self?.fileChanged(path) }
            source.setCancelHandler { close(descriptor) }
            let inode = FileSignature.read(descriptor: descriptor)?.inode
            source.resume()
            return Armed(source: source, inode: inode)
        }

        /// The file's own source fired: re-arm at once, then report.
        private func fileChanged(_ path: String) {
            let known: Bool = state.withLock { state in
                guard !state.isStopped, let old = state.files[path] else { return false }
                old.source?.cancel()
                state.files[path] = arm(path)
                return true
            }
            if known { onEvent(path) }
        }

        /// The directory's source fired: re-arm every path that is missing or replaced.
        private func directoryChanged(_ directory: String) {
            let changed: [String] = state.withLock { state in
                guard !state.isStopped, let paths = state.directories[directory]?.paths else { return [] }
                var changed: [String] = []
                for path in paths {
                    guard let old = state.files[path] else { continue }
                    let current = FileSignature.read(at: path)?.inode
                    guard current != old.inode else { continue }
                    old.source?.cancel()
                    state.files[path] = arm(path)
                    changed.append(path)
                }
                return changed
            }
            for path in changed {
                onEvent(path)
            }
        }
    }
#endif
