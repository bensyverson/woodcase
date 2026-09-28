# The release-only `CTFont` SIGTRAP was a Swift optimizer bug, not a font bug

2026-08-30 · closes `euSPm`

`swift test -c release` died with `EXC_BREAKPOINT` inside
`__CFCheckCFInfoPACSignature`, three for three, on
`PenTextMeasurerFontCacheTests.resolveFontReturnsCachedInstance`, taking the whole
run down. The stack pointed at `FontResolutionCache.__deallocating_deinit` →
`_DictionaryStorage.deinit` → `_CFRelease`, so the issue was filed as a `CTFont`
freed early — an under-retain somewhere in `Sources/Woodcase/PenTextMeasurer.swift`.

**That premise was wrong. Nothing in `Sources/Woodcase` is at fault, and the font was
never freed.** The corruption came from a *test helper*, and the defect is in the
Swift compiler: at `-O`, without whole-module optimization, it emits an unguarded
release of a local `var` that has been *declared but never assigned*.

## What the object actually looked like

`MallocStackLogging` on the crashing process reported one `ALLOC` for the address CF
trapped on, from `CTFontCreateWithFontDescriptor` by way of `PenTextMeasurer`, and
**no `FREE`**:

```
lldb --batch -k "…" -o run -- swiftpm-testing-helper …   # MallocStackLogging=1
ALLOC 0x9d41c4000-0x9d41c427f [size=640]: … CTFontCreateWithFontDescriptor …
```

`object_getClassName` on it returned `NSCTFont`, and `CFGetRetainCount` walked
1 → 2 → 3 exactly as the code implies. A live object with a healthy retain count,
and CF refusing to release it.

The tell is CoreFoundation's `_cfinfo` word, at object + 8. Printing it around each
step (`scripts/`-free instrumentation on a copy of the four source files, built with
`xcrun swiftc -O`) gave:

| point | `_cfinfo` | CF retain count |
| --- | --- | --- |
| after `CTFontCreateWithFontDescriptor` | `0x000012dd29004c80` | 1 |
| after storing in the cache | `0x000022dd29004c80` | 2 |
| after the second, cache-hit resolve | `0x00003**2db**29004c80` | 3 |

Bits 44–63 are CF's retain count and step correctly. Bits 24–43 are the PAC
signature CF checks on the dealloc path, and they moved: `0x2dd` → `0x2db`, a
decrement of exactly `1 << 33`.

`1 << 33` is where Swift's *native* strong reference count lives in a Swift object
header. So something called `swift_release` on a CoreFoundation object. That write
lands in the middle of CF's signature, CF only validates the signature when a
release reaches the dealloc path, and the next such release was
`FontResolutionCache.deinit` destroying its dictionary — which is why the crash
appeared thousands of instructions away from its cause, in code that was innocent.

## The instruction

Disassembling the actual crashing binary shows it plainly. Two calls resolve the
font; the second's result is still in `x0`; then:

```
1000013e0  bl  …PenTextMeasurerO11resolveFont…   ; x0 = the CTFont
1000013e4  mov x22, x0
1000013e8  bl  _swift_release                    ; no argument set up: x0 is the CTFont
```

That `swift_release` is the destroy of the *previous* value of the test helper's

```swift
var result: (cache: FontResolutionCache, value: T)   // declared, never assigned
```

On the second and later iterations the compiler emits the destroy correctly and
guards all three fields behind the definite-initialization availability flag:

```
tbz w8, #0, LBB2_25        ; skip if `result` was never assigned
objc_release  … ; value.0
objc_release  … ; value.1
swift_release … ; cache
```

On the *first* iteration the native `swift_release` of the `cache` field escapes
that guard and runs against whatever is in `x0`.

## The reduction

`scripts/swift-di-miscompile` is the case, self-contained, with no Woodcase code in
it: a generic function, a declared-but-unassigned `var` of a tuple mixing a native
class with the generic parameter, assigned inside a `repeat` loop. It dies with
`SIGBUS` in `swift::RefCounts::doDecrementSlow` at `-O` and runs clean at `-Onone`.

```text
$ scripts/swift-di-miscompile
toolchain: Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
STILL BROKEN — the case died with exit 138 (128+signal).
```

It is narrow. Building the same code with `-wmo`, or making `result` an `Optional`,
or dropping the loop, or splitting the tuple so the `var` holds only `T`, all
produce correct code — measured as a five-way matrix against one binary, only the
original shape crashing. That is why the bug had never been seen: SwiftPM builds
library targets with whole-module optimization, and only the release **test** build
compiles this file the way that triggers it.

## The fix

`PenTextMeasurerFontCacheTests.undisturbed` no longer keeps a running answer in a
declared-but-unassigned `var`. Each attempt is built and returned on the spot, with
the last attempt taken unconditionally:

```swift
for _ in 1 ..< attempts {
    let cache = FontResolutionCache()
    let before = PenFontRegistry.generation
    let value = body(cache)
    if PenFontRegistry.generation == before { return (cache, value) }
}
let cache = FontResolutionCache()
return (cache, body(cache))
```

Same retry semantics, same assertions, no unassigned storage for the optimizer to
destroy. A scan of the whole repository found this helper to be the only
declared-but-unassigned local `var` anywhere that is later assigned inside a loop,
so nothing in `Sources` needed changing.

The regression test is the case that was crashing:
`PenTextMeasurerFontCacheTests.resolveFontReturnsCachedInstance` is red in release
before the change (`swift test -c release --filter PenTextMeasurerFontCacheTests`,
`exited with unexpected signal code 5`) and green after, in both configurations.

## What to do when the toolchain updates

Run `scripts/swift-di-miscompile`. When it prints `FIXED`, the helper can go back to
the obvious shape and this note becomes history.

## Why the original diagnosis went the way it did

Everything about the crash pointed at memory management of a `CTFont`: the frame was
`_CFRelease`, the owner was our font cache, and only the one test that let a font
*escape* the helper crashed. All of that was true and none of it was the cause. The
step that broke it open was reading the object rather than the stack — a byte-level
diff of `_cfinfo` across the run, which turned "a font was freed early" into "one
`swift_release` too many, at bit 33" and pointed at the compiler instead of at
CoreText.

Two habits are worth keeping. `MallocStackLogging` answering "allocated here, never
freed" is a *result*, not a dead end: it rules out use-after-free and forces the
question of what else could make a release fail. And a crash that only happens at
`-O` is a compiler suspect from the first minute; the cheapest way to charge or
clear it is a matrix of near-identical variants compiled into one binary, which took
fifteen seconds a round here against four minutes for a release test build.
