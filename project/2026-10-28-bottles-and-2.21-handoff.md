# Handoff: Homebrew bottles and the 2.21 work (2026-10-28)

## Done

- **Homebrew bottles.** `../homebrew-tap/scripts/release` now builds, signs (Developer ID), notarizes (`notary_profile=woodcase-notary`), uploads and pours a bottle when a tool's `scripts/release.conf` says `bottle=yes`; `scripts/test-release` covers it. The bottle is tagged for the formula's `depends_on macos:` (`arm64_sequoia`), so one build serves Sequoia and later. Woodcase 0.1.4's bottle is live and verified (`spctl`: Notarized Developer ID). Once a version is tagged, the release only reads the tool's checkout, so another session's uncommitted files there no longer block it.
- **Pen 1.2.16 / format 2.21** (root `yikOf8`): current format 2.21 and the typed shader effect (`febc3a2b`), fileToken pinned on every write verb (`aaee6ca0`), outer shadows cast from painted content per pen CLI 0.3.13 (`254effe0`), RapidPro `0ebcd8d` and Penumbra `8646a21` handle `PenEffect.shader`. Woodcase still runs no shaders (backlog, 2026-09-27).

## Next

0.1.5 is released (signed, notarized `arm64_sequoia` bottle, verified poured). It went out with `--skip-tests` on Ben's approval: the release check runs the full suite, and two timing tests fail under the suite's own load (load average 20–30) in every full run, while passing alone.

1. **Fix the two load flakes first**, so the next `scripts/release` check can pass: `4yZOHq` (FigmaImageFetcherTests' `timeout` test asserts under 10 s of wall clock; the fetcher's task-group race is correct, the cancelled child just waits for a thread) and `1nZPfP` (SwiftUIRenderBatchRunAsyncTests times out under load). Make each assert something scheduler delay can't break, not a wall-clock bound.
2. Under `yikOf8`: `q1ffR7` (SwiftUI/React/SVG shadows from content; their gates hold the measured gap) and `391iRf` (RapidPro mirrors the CG shadow rule, spelled out in the leaf).
3. Issues filed this session: `b2qfxi` (merge-fuzz divergence at seed 65536), `kIssG7` (import prefixing skips effects), `D2dkrh` (sampler2D shader uniforms).
4. `KT1PbK` waits on Ben. Recommended: Duplicate mints a fresh fileToken (a new design, as Pen does for a new file); Save As keeps it (the design and its comments move to the new file, as Penumbra's history already treats Save As). Worth a 30-second check in Pen.app first: do two files sharing a token both show the comments?

## Notes

- RapidPro and Penumbra are committed and pushed, along with earlier sessions' commits they were holding.
- `scripts/release` needs a clean tree before it bumps the version, and every `job` write changes the tracked `.jobs/log/*.jsonl`. Commit the log right before releasing, and don't run `job` while a release is bumping.
- The full suite's only failures under load were timing tests (PenFileTransactionTests lock timeout, FigmaImageFetcherTests, ViewerBrowserTests scroll); all pass alone.
- Killing `brew install` with SIGTERM leaves its `swift-build` child holding the Cellar lock, plus an empty keg that `brew list` counts as installed. Kill the whole process tree, then remove the empty keg.
