import ArgumentParser

/// Supported output formats for the render command.
enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
    case png
    case pdf
}
