# Native foundation

Status: DONE

SwiftUI and AppKit own presentation. LauncherCore owns deterministic search and organization.
Native adapters handle application discovery, launch, icons, wallpaper, and local persistence.

The launcher searches apps only, works offline, and uses public macOS APIs.
User layouts and history remain separate from regenerable caches. Failed reads preserve data.

See [the active plan](004-release.md) for current compatibility and release validation.
