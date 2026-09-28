import WoodcaseCommandCore

/// The `woodcase` executable: one `@main` and nothing else.
///
/// Every verb, option group, formatter and failure type lives in
/// `WoodcaseCommandCore`, which is a plain library. This target exists only to carry
/// the entry point, and it must stay that way — `WoodcaseCommandTests` depends on the
/// library, never on this target, because a test bundle that links an executable
/// target's objects coalesces its `@main` with the bundle's own in an optimized build
/// and `swift test -c release` then runs `woodcase` instead of the tests.
/// `PackagingTests` is the tripwire; see <doc:WoodcasePerformance>.
@main
enum Main {
    /// Parses the command line and runs the verb it names.
    ///
    /// Never returns: the root command ends the process with a house exit code.
    static func main() async {
        await WoodcaseCommandCore.WoodcaseCommand.main()
    }
}
