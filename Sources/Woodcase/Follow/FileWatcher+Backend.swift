//
//  FileWatcher+Backend.swift
//  Woodcase
//

public extension FileWatcher {
    /// How a ``FileWatcher`` notices that a file changed.
    enum Backend: Friendly, CaseIterable {
        /// The platform's own notification API: kqueue on Apple platforms, inotify on
        /// Linux, polling anywhere else.
        case native
        /// Compares `stat` results on a timer. Slower to notice, but works on every
        /// filesystem, including network mounts that deliver no notifications.
        case polling
    }
}
