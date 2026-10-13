# Engineering guide

Read [the active plan](plans/README.md) before changing code. Record decisions and validation there.
Read [design.md](design.md) before changing UI, interaction, animation, or performance behavior.
Keep documentation brief, human-readable, and free of em dashes.

## Product

Sofla is a native macOS 26+ app for Apple silicon, built with SwiftUI and AppKit.
Preserve the full-screen Launchpad experience from macOS Sequoia 15 and earlier.
It searches installed apps only. No accounts, telemetry, remote search, or embedded web UI.
Follow system appearance, accessibility, materials, and Reduce Motion.
Use public wallpaper APIs, never screen capture or private system databases.

## Code

Keep LauncherCore independent of AppKit and the filesystem. Native adapters own side effects.
Use Swift 6 concurrency, Main Actor UI, bounded caches, and explicit cancellation.
Keep files focused. Prefer concrete types and inject real system boundaries for tests.
Preserve user data and errors. Do not replace unreadable documents with defaults.

## Performance priorities

Treat responsiveness, near-zero idle work, bounded memory, and small size as acceptance criteria.
Keep expensive work off the input path and Main Actor. Reuse prepared resources and search indexes.
Preserve a complete first frame with bounded fallbacks; never hide latency with visible asset pop-in.
Measure relevant changes before and after in Release. Fix regressions within the change.
Follow the budgets and validation rules in [design.md](design.md); do not relax them to pass checks.

## Checks

Run `./scripts/check.sh` and `./scripts/test-native-regressions.py` for native changes.
Use `./scripts/test-ui.sh` in a logged-in desktop session for UI changes.
Add behavior-focused regression tests. Fixtures must not use private data or installed apps.
Measure performance in Release. Separate computation, presentation, and target-app startup.
Report failed and unavailable checks honestly.

## Safety and delivery

Never commit personal paths, inventories, history, credentials, signing keys, or wallpaper.
Do not alter system settings, login items, installed apps, or developer tools during tests.
Do not accept tool licenses automatically or bypass macOS security.
Publish, sign for distribution, or change repository visibility only when requested.
Use [RELEASING.md](RELEASING.md) for source export and release gates.
