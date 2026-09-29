// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Woodcase",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "Woodcase",
            targets: ["Woodcase"]
        ),
        .library(
            name: "WoodcaseScripting",
            targets: ["WoodcaseScripting"]
        ),
        .executable(
            name: "woodcase",
            targets: ["WoodcaseCommand"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.3"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        // Test-only: the headless-WebKit host behind WebViewTestHarness.
        // macOS-only (it links WebKit.framework), so the target dependency
        // below is conditional and the Woodcase library never sees it.
        .package(url: "https://github.com/bensyverson/sleepyhollow.git", branch: "main"),
        // The viewer's server-rendered HTML DSL. Approved by Ben 2026-08-29 and pinned
        // to an exact version: it is a 0.x package, so a minor bump may break the API.
        // WoodcaseViewer is its only consumer; the Woodcase library never sees it.
        .package(url: "https://github.com/sliemeobn/elementary", exact: "0.8.1"),
        // The overlay helpers behind `shot --grid` and `shot --outline`: labeled
        // rulers and boxes drawn in layout points. A repo we own, so it follows
        // `main` (Ben's ruling, 2026-08-29). WoodcaseCommand is its only consumer;
        // the Woodcase library never sees it.
        .package(url: "https://github.com/bensyverson/PixelPeeper.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "Woodcase",
            resources: [
                .copy("IconFonts/Fonts"),
                .copy("CodeGen/ViewerTemplates"),
                // Emitted source, not compiled here: the SwiftUI emitter copies it into
                // every package it writes. The library never links SwiftUI.
                .copy("CodeGen/SwiftUITemplates"),
            ]
        ),
        // Apple-only, like the CoreGraphics renderer it wraps: the server is
        // Network.framework and the render cache is CoreGraphics. SwiftPM cannot make a
        // target conditional (only a dependency), so the target is always declared;
        // on a platform without Network.framework it simply builds no sources.
        .target(
            name: "WoodcaseViewer",
            dependencies: [
                "Woodcase",
                .product(name: "Elementary", package: "elementary"),
            ]
        ),
        // The JavaScript host. Apple-only, like WoodcaseViewer: JavaScriptCore is a
        // system framework on macOS and iOS and absent on Linux. SwiftPM cannot make a
        // target conditional (only a dependency), so the target is always declared and
        // every file inside it is wrapped in `#if canImport(JavaScriptCore)`; on a
        // platform without the framework it builds to nothing. The boundary is the
        // point: `Woodcase` itself never sees JavaScriptCore, and a
        // `ScriptingIsolationTests` grep proves it.
        .target(
            name: "WoodcaseScripting",
            dependencies: ["Woodcase"]
        ),
        // Every verb, option group, formatter and failure type. A library rather than
        // part of the executable so the tests can link it without dragging in an
        // `@main`: `@main`'s async entry body is emitted under the fixed, module-less
        // symbol `async_Main`, and under `-O` the thunk reaching it is a *shared*
        // specialization whose mangled name carries no module either. A test bundle
        // that links an executable target therefore coalesces the two, and
        // `swift test -c release` runs the CLI instead of the tests.
        // `PackagingTests` is the tripwire.
        .target(
            name: "WoodcaseCommandCore",
            dependencies: [
                "Woodcase",
                "WoodcaseViewer",
                // `find` runs its predicate through the host's read side; the CLI holds
                // no JavaScript of its own.
                "WoodcaseScripting",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "PixelPeeper", package: "PixelPeeper"),
            ]
        ),
        // One file: the `@main` shim over WoodcaseCommandCore's root command.
        .executableTarget(
            name: "WoodcaseCommand",
            dependencies: ["WoodcaseCommandCore"]
        ),
        .testTarget(
            name: "WoodcaseTests",
            dependencies: [
                "Woodcase",
                // One suite: `PerformanceBudgets.SetVerbTests` times the `set` verb itself,
                // so the budget covers what a caller waits for. It lives here because every
                // budget must run inside the one `.serialized` `PerformanceBudgets` suite —
                // two timing tests running at once measure each other.
                "WoodcaseCommandCore",
                // Every snapshot MAE goes through PixelPeeper's comparator.
                .product(name: "PixelPeeper", package: "PixelPeeper"),
                .product(
                    name: "SleepyHollow",
                    package: "sleepyhollow",
                    condition: .when(platforms: [.macOS])
                ),
            ],
            resources: [
                .copy("Fixtures"),
                .copy("Fonts"),
            ]
        ),
        .testTarget(
            name: "WoodcaseCommandTests",
            // WoodcaseCommandCore, never the WoodcaseCommand executable — see the
            // comment on that target. The binary-driven tests still run the real
            // `woodcase`: `swift test` builds every product in the package, and
            // `CommandFixture` launches it as a process (or `$WOODCASE_BINARY`).
            // WoodcaseScripting is here for one suite: `ScriptReadParityTests` compares
            // what `doc.tree/get/lint/schema` return against the bytes the real binary
            // prints with --json. Only a target that can both run the process and call
            // the host can ask that question.
            dependencies: [
                "WoodcaseCommandCore",
                "Woodcase",
                "WoodcaseScripting",
                // `ShotImageProbe` decodes and compares through PixelPeeper.
                .product(name: "PixelPeeper", package: "PixelPeeper"),
            ],
            resources: [
                // The `shot --grid --outline` golden. Declared so SwiftPM treats the
                // directory as a resource rather than warning about an unhandled file;
                // the snapshot test itself reads the PNG beside its own source, so
                // `UPDATE_GOLDEN=1` rewrites the file under version control.
                .copy("Fixtures"),
            ]
        ),
        .testTarget(
            name: "WoodcaseScriptingTests",
            // The host's own tests. They read fixtures from Tests/WoodcaseTests/Fixtures
            // by path rather than copying them in, so there is one copy of batch.pen.
            dependencies: ["WoodcaseScripting", "Woodcase"]
        ),
        .testTarget(
            name: "WoodcaseViewerTests",
            dependencies: [
                "WoodcaseViewer",
                // The golden previews render components directly, so the tests need the
                // DSL the components are written in.
                .product(name: "Elementary", package: "elementary"),
                // The acceptance test drives the served page in a headless WebKit view.
                .product(
                    name: "SleepyHollow",
                    package: "sleepyhollow",
                    condition: .when(platforms: [.macOS])
                ),
            ],
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
