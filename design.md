# Native Sofla design

## Familiar by default

Use the Launchpad experience from macOS Sequoia 15 and earlier as the interaction reference:
a full-screen app grid, immediate typing, pages, and folders. See
[Apple's classic Launchpad guide](https://support.apple.com/en-ie/guide/mac-mini/aside/apd2d2a58738/2024/mac/15).
Keep that familiar structure while using current public macOS APIs and system materials.

## Layout and interaction

- Make apps the focus: large icons, readable labels, balanced spacing, and search at the top.
- Preserve spatial memory. Keep positions and page order stable unless the user changes them.
- Support clicking, immediate typing, arrow selection, Return to launch, and page gestures.
  All four plain arrows select results while typing; modified text-editing shortcuts stay native.
- Drag to rearrange or create folders. Keep folder opening, closing, and drag feedback clear.
- Escape backs out of the current folder or search before dismissing. Background clicks dismiss.
  Launching hands focus to the selected app; dismissing restores the previous app.
- Reopening an already focused launcher preserves its page, query, and selection.
- Keep Favorites and Recents secondary to the main grid. Put configuration in native Settings.
- Keep setup short. Open at Login is optional; explain and recheck any selected approval.

## Native appearance

- Use the user's wallpaper through supported APIs, with a neutral fallback when unavailable.
- Follow system fonts, appearance, accent, contrast, transparency, and Reduce Motion.
- Let macOS own the Dock and system chrome. Use native controls and materials for Sofla's UI.
- Keep motion brief and purposeful. Input and focus must not wait for animations.
- Check keyboard focus, VoiceOver labels, small displays, and both light and dark appearances.

## Performance comes first

Responsiveness, low idle cost, and a small app are product requirements. Treat regressions as
part of the change to fix, not future cleanup. Preserve correctness, accessibility, and polish.

- Keep scanning, disk access, icon decoding, and wallpaper processing off the input path and
  Main Actor. Reuse the search index; never perform network work for typing or presentation.
- Show a prepared current page. Avoid wallpaper and icon pop-in; use a bounded, explicit fallback
  for unavailable resources. A complete cold frame matters more than an empty frame shown sooner.
- Reuse warm resources. Do not delay opening for a full rescan or adjacent-page preparation.
- Bound cache size, queues, and workers. Prioritize visible icons, then adjacent pages; cancel
  stale work. Hidden windows should do almost no work. Prefer events over polling.
- Prefer native facilities and existing dependencies. Measure any new dependency, asset, blur,
  or animation against launch time, frame smoothness, memory, idle CPU, and installed size.

## Measure before accepting

Use Release builds and the same workload for before/after comparisons. Existing p95 budgets
are below 16 ms for cached search across 1,000 synthetic apps, below 100 ms for warm invocation,
and below 16 ms for the search view-update acknowledgement. These are targets, not guarantees.
An acknowledgement does not measure a rendered frame or the target app's startup.

Run `./scripts/benchmark.py --invocation` and `./scripts/measure-footprint.py` for relevant changes.
Record cold and warm behavior separately, plus workload and measurement limits. Keep machine
details in local output. Report unavailable checks honestly; do not raise budgets to hide a regression.
