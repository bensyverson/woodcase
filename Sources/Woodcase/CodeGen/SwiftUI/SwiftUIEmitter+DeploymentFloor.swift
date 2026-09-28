//
//  SwiftUIEmitter+DeploymentFloor.swift
//  Woodcase
//

public extension SwiftUIEmitter {
    /// The oldest OS releases the emitted package supports.
    ///
    /// Component and page code is written for the newest floor and is the same at every
    /// floor; a lower floor is served only by `#available` branches inside the emitted
    /// `PenSupport.swift`, so choosing one changes the package's declared platforms and
    /// nothing a reader of a view would see.
    enum DeploymentFloor: String, Friendly, CaseIterable {
        /// iOS 26 and macOS 26: the default.
        case iOS26 = "ios26"

        /// iOS 18 and macOS 15, through the support file's availability branches.
        case iOS18 = "ios18"

        /// The iOS release, as a version string (`"26.0"`).
        public var iOSVersion: String {
            switch self {
            case .iOS26: "26.0"
            case .iOS18: "18.0"
            }
        }

        /// The macOS release, as a version string (`"15.0"`).
        public var macOSVersion: String {
            switch self {
            case .iOS26: "26.0"
            case .iOS18: "15.0"
            }
        }
    }
}
