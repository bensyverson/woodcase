//
//  FileWatchBackendFactory.swift
//  Woodcase
//

/// Builds the backend for a ``FileWatcher/Backend`` choice on this platform.
enum FileWatchBackendFactory {
    /// Makes a backend.
    ///
    /// - Parameters:
    ///   - kind: The caller's choice.
    ///   - onEvent: Called, on an arbitrary queue, with each path that may have changed.
    /// - Returns: The backend. `.native` falls back to polling where the platform has no
    ///   native notification API, or the kernel refuses one.
    static func make(
        _ kind: FileWatcher.Backend,
        onEvent: @escaping @Sendable (String) -> Void
    ) -> any FileWatchBackend {
        switch kind {
        case .polling:
            return PollingFileWatchBackend(onEvent: onEvent)
        case .native:
            #if canImport(Darwin)
                return DarwinFileWatchBackend(onEvent: onEvent)
            #elseif canImport(Glibc)
                if let backend = InotifyFileWatchBackend(onEvent: onEvent) { return backend }
                return PollingFileWatchBackend(onEvent: onEvent)
            #else
                return PollingFileWatchBackend(onEvent: onEvent)
            #endif
        }
    }
}
