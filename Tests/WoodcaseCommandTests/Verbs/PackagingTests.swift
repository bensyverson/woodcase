//
//  PackagingTests.swift
//  WoodcaseCommandTests
//

#if canImport(Darwin)
    import Darwin
#endif
import Testing

/// Pins the one packaging rule that keeps `swift test -c release` able to run.
///
/// `@main` on an `async` entry point makes the compiler emit the entry body under the
/// fixed, module-less symbol `async_Main`, and under `-O` it emits the thunk that
/// reaches it as a *shared* function-signature specialization —
/// `$sIetH_yts5Error_pIegHrzo_TR10async_MainTf3npf_n` — whose mangled name likewise
/// carries no module. SwiftPM renames only the C `main` wrapper of an executable
/// target under test (`-entry-point-function-name WoodcaseCommand_main`), so when a
/// test target depends on an executable target, the release link coalesces the two
/// identically-named thunks and the test bundle's `main` ends up running whichever one
/// the linker kept. Here that was `woodcase`'s, and the whole release run answered
/// `Error: Unknown option '--test-bundle-path'`. Debug never specialized, kept both
/// `async_Main` bodies local to their own object files, and so never showed it.
///
/// The fix is structural: every command type lives in the `WoodcaseCommandCore`
/// library, the `WoodcaseCommand` executable is a one-file `@main` shim, and this test
/// target depends on the library only. `woodcase` is still built — it is a product of
/// the package — and ``CommandFixture`` still drives it as a real process; it just is
/// not *linked into* the bundle any more.
///
/// This test is the tripwire: `WoodcaseCommand_main` is exported by the executable
/// target's objects, so it is visible to `dlsym` exactly when those objects have been
/// linked in. See <doc:WoodcasePerformance>.
@Suite("Packaging")
struct PackagingTests {
    #if canImport(Darwin)
        @Test("The test bundle does not link the woodcase executable's entry point")
        func bundleDoesNotCarryTheExecutableEntryPoint() {
            let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)
            let symbol = dlsym(defaultHandle, "WoodcaseCommand_main")
            #expect(
                symbol == nil,
                """
                The test bundle links the `woodcase` executable target, so its `main` \
                and the bundle's own are one coalesced symbol in release and \
                `swift test -c release` runs the CLI instead of the tests. Depend on \
                WoodcaseCommandCore, never on WoodcaseCommand.
                """
            )
        }
    #endif
}
