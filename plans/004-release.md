# Release preparation

Status: Version 1.0.0 replaces the initial 1.0 release. Website deployment and manual installation coverage remain open.

## Scope

- Sanitize source, assets, docs, and the source export. Do not publish private Git history.
- Support macOS 26+ on Apple silicon. Keep Xcode 27 as the build toolchain.
- Credit Aleksei Iunes as the project creator. Original Sofla artwork provenance is confirmed.
- Use Sofla branding, bundle ID `app.sofla.launcher`, and the MIT license.
- Add first-run setup with a shortcut and optional Open at Login.
- Request no broad privacy permissions. Recheck pending login approval on activation.
- Package a styled drag-to-Applications disk image. Use ad-hoc signing and disclose the unnotarized release.
- Measure Release size, search, memory, idle CPU, and presentation where desktop access works.
- Publish only measured claims on the website and keep unavailable downloads honest.
- Document classic Launchpad interaction and performance acceptance in `design.md`.

## Validation

- Source and stripped app privacy audits pass. Clean ZIP export excludes private history and metadata.
- Native design guidance is linked from agent and contributor instructions and included in source exports.
- Standard checks pass: formatting, 100 package tests, fourteen tooling tests, and native test compilation.
- All 58 standalone native regressions and both focused onboarding UI tests pass.
- The complete desktop suite with live launch journeys passes: 112 tests, no failures or skips.
- Local disk-image generation, signature validation, checksum, and mounted-content audit pass.
- Website checks, 28 unit tests, SEO environment checks, and asset budgets pass.
- Browser checks pass at desktop and mobile widths. No accessibility violations in the audited state.
- Cached search meets the 16 ms p95 gate. Size and idle fixture measurements are recorded locally.
- Release p95: cached search at most 12.09 ms, warm invocation 71.80 ms, native search-field update
  acknowledgement 9.96 ms. All six benchmark budgets pass. First presentation was 323.61 ms.
  These timings exclude GPU presentation and target-app startup; first presentation excludes process startup.
- The separate global-shortcut diagnostic requires event-posting access for the test runner.
  It is skipped when that access is unavailable. Physical shortcut verification remains a release check.
- Xcode reports an internal QoS warning also present before these changes; it causes no test failures.

The setup uses optional startup approval with refresh on activation, explicit retry, and opt-out.
Basic launching needs no broad privacy permissions. Research: [Raycast settings](https://manual.raycast.com/settings)
and [Apple login service](https://developer.apple.com/documentation/servicemanagement/smappservice).

## Release status

The owner selected distribution without an Apple Developer subscription. Developer ID signing
and notarization are optional for a future release. The compiled app passed macOS 26 runtime
checks. Public downloads and their SHA-256 checksum are verified. The browser-download/Open Anyway
flow on a clean Mac has not been independently verified.
Physical shortcut and optional login-startup acceptance remain manual checks.
The source repository is public. The website needs its deployment account linked.

## Native acceptance follow-up

The old query-change observer missed benchmark acknowledgements while the window remained active
and focused. Sampling now occurs when the native search field applies the query. A UI regression
covers all 100 search transitions and 20 warm invocations, including no results and clearing search.

Live tests now use Sofla's bundle name and completed setup in disposable state. Element-scoped
key synthesis failed for the shortcut diagnostic, including a timeout after an ordinary-key probe
reached the handler. The diagnostic now uses global events with a permission preflight. No system
permissions or installed-app settings were changed.

## Unnotarized release

The packaging command now supports `--unnotarized`, includes first-launch approval guidance,
and produces a versioned disk image, checksums, source archive, and explicit release manifest.
Metadata checks reject a mismatched app, architecture, or binary deployment target.
The cross-runner CI check passed on macOS 26.6.2: startup, 20 warm invocations, and
100 native search updates. The release packages that tested app without recompiling it.
The website has a dedicated installation guide and a release configuration gate.

## README preview

The README includes a capture of the native launcher with curated system apps and its neutral
background. It contains no personal app inventory, wallpaper, menu bar, or desktop. The image
is documentation only, excluded from the app bundle, and included in clean source exports.

## Installer layout correction

Version 1.0 shipped without Finder's saved layout. Finder-driven styling was not reliably
persisted, and multiple mounted Sofla volumes made disk references ambiguous. Packaging now
writes the layout directly with pinned build-only tools and validates the final read-only
image after remounting it. Missing backgrounds or incorrect icon positions fail packaging.
The actual Finder window is visually checked. The corrected 1.0.0 release changes packaging and version metadata; the app implementation
is unchanged. It replaces the withdrawn 1.0 release at the owner's request.

## Automatic updates

Integrate pinned Sparkle 2 with an optional automatic-check permission prompt, an Updates
settings pane, and a manual menu action. Host the signed feed on GitHub Releases so updates
do not depend on the marketing deployment. Keep the private signing key in Keychain.
Disable networking for test fixtures. Verify a real update and rejection of invalid signatures
using disposable copies, then remeasure size and performance. The owner requested replacing
release 1.0.0 and force-pushing the public source as one initial commit again.

Update verification passes for signed installation, an unavailable feed followed by retry,
rejection of a modified feed and archive, and data outside the app remaining intact. Tests
use temporary app identities and signing keys. The native regression suite passes all 58 tests.
The desktop suite recorded 109 passes and four live-test skips. One initial launcher-accessibility
failure in the folder-drag test passed on a focused retry; the new update settings test also passes.
Sparkle system-profile keys are explicitly excluded and profiling is disabled in bundle metadata.

Release benchmarks with Sparkle pass all six budgets: cached search p95 at most 12.42 ms,
warm invocation 67.57 ms, and native search-view acknowledgement 9.93 ms. These use the same
1,000-record fixture and exclude rendered GPU frames and target-app startup.
