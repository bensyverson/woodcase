# Handoff: Homebrew bottles and the 2.21 work (2026-10-28)

## Done

- **Homebrew bottles.** `../homebrew-tap/scripts/release` now builds, signs (Developer ID), notarizes (`notary_profile=woodcase-notary`), uploads and pours a bottle when a tool's `scripts/release.conf` says `bottle=yes`; `scripts/test-release` covers it. The bottle is tagged for the formula's `depends_on macos:` (`arm64_sequoia`), so one build serves Sequoia and later. Woodcase 0.1.4's bottle is live and verified (`spctl`: Notarized Developer ID). Once a version is tagged, the release only reads the tool's checkout, so another session's uncommitted files there no longer block it.
- **Pen 1.2.16 / format 2.21** (root `yikOf8`): current format 2.21 and the typed shader effect (`febc3a2b`), fileToken pinned on every write verb (`aaee6ca0`), outer shadows cast from painted content per pen CLI 0.3.13 (`254effe0`), RapidPro `0ebcd8d` and Penumbra `8646a21` handle `PenEffect.shader`. Woodcase still runs no shaders (backlog, 2026-09-27).

## Next

1. **Release 0.1.5** from Woodcase: `scripts/release 0.1.5`. It bumps, runs the suite, tags, bottles and pours.
2. Under `yikOf8`: `q1ffR7` (SwiftUI/React/SVG shadows from content; their gates hold the measured gap) and `391iRf` (RapidPro mirrors the CG shadow rule, spelled out in the leaf).
3. Issues filed this session: `KT1PbK` (decision: should Penumbra's Duplicate mint a fresh fileToken?), `b2qfxi` (merge-fuzz divergence at seed 65536), `kIssG7` (import prefixing skips effects), `D2dkrh` (sampler2D shader uniforms), `gmJZcW` (`mae-check` divides by a zero baseline).

## Notes

- RapidPro and Penumbra are committed locally but not pushed. Both also hold other sessions' unpushed commits.
- The full suite's only failures under load were timing tests (PenFileTransactionTests lock timeout, FigmaImageFetcherTests, ViewerBrowserTests scroll); all pass alone.
- Killing `brew install` with SIGTERM leaves its `swift-build` child holding the Cellar lock, plus an empty keg that `brew list` counts as installed. Kill the whole process tree, then remove the empty keg.
