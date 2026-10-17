# Architecture

Orientation for new contributors. Covers the shape of the codebase, the design decisions worth knowing before touching things, and the house conventions that aren't obvious from reading the source.

## Stack

- **Framework:** Flutter (Dart), desktop-first.
- **Playback:** media_kit / libmpv (mpv-grade decoding and rendering).
- **State:** Riverpod (notifiers and providers).
- **Routing:** go_router, inside a persistent app shell (nav rail).
- **Networking:** dio.
- **Secure storage:** flutter_secure_storage.
- **YouTube:** youtube_explode_dart plus a hand-rolled InnerTube client.
- **Localization:** Flutter ARB via gen_l10n.
- **Targets:** Linux first (built and tested on Arch/KDE); Windows and macOS planned.

## Layout

The reads that actually matter:

- `lib/main.dart` — startup: window setup, and AppImage desktop-entry self-integration.
- `lib/app.dart` — the root `MaterialApp`, theming from prefs, window-close teardown, and the pop-out overlay.
- `lib/routing/` — the go_router config and the app shell (nav rail, offline banner).
- `lib/screens/` — one file per screen.
- `lib/state/` — the app's brain: Riverpod providers and notifiers.
- `lib/services/` — the InnerTube client, downloads, MPRIS, desktop integration, and similar.
- `lib/widgets/player_controls.dart` — the player chrome shared by both players.
- `lib/l10n/app_en.arb` — the English string source of truth.

Everything else is discoverable with `grep` and `ls`.

## Key Design Decisions

### One shared player, settings passed in

`FathomPlayerControls` is used by both the Jellyfin player and the YouTube player. It must never read preferences itself: a YouTube-only setting read inside the shared widget would silently change Jellyfin playback too. Callers pass values in as parameters, and a test (`test/youtube_settings_scope_test.dart`) fails the build if the shared controls reference prefs.

### mpv is torn down before the engine

Closing the window mid-playback races libmpv's callback teardown against the Flutter engine and crashes. So the custom close button and the compositor route through `preventClose`, `app.dart` disposes players first, then destroys the window. The Linux runner also `_exit()`s once the main loop returns, to skip a crashy GTK/GObject teardown on exit.

### InnerTube, with a known wall

The YouTube client pairs youtube_explode_dart with a small InnerTube client for search and channels. The InnerTube `/player` endpoint is bot-gated (needs a po_token), so features that depend on it (storyboards, for example) are deliberately not built on it.

### Unexplained UI bugs are usually layout assertions

A recurring class of bug, builds fine, correct data, never paints, no red error box, was always a RenderFlex assertion (a bare button in a `Row` given unbounded width by the theme's full-width `minimumSize`). It's fixed app-wide by a shared button style and pinned by `test/modal_blank_regression_test.dart`. The tell is "builds but doesn't paint"; reproduce with a widget test that measures the container, not a child.

### The pop-out is one window, not two

Pop-out-to-desktop shrinks the whole app window into a small, always-on-top, 16:9 frame rather than opening a second window. A true second window needs Flutter multi-window plus a second mpv instance, which is heavy and fragile on Linux.

### Strings and the search index move together

Every user-facing string lives in `lib/l10n/app_en.arb`. A CI guard fails on new hardcoded UI strings, and the in-app settings-search index (`lib/screens/settings_search.dart`) must be updated in the same change as any setting.

## Conventions

- **App ID:** `app.fathom.player`. On Linux this is the storage scope, changing it logs users out and resets prefs, so don't.
- **Strings:** add to `app_en.arb` and keep the settings-search index in sync; run `flutter gen-l10n` after editing ARB. The generated bindings in `lib/l10n/generated/` aren't committed: `flutter pub get` and every build write them, so Weblate's commits only touch ARB files.
- **Branches:** `dev` is the daily driver (direct commits fine); `main` is release-only.
- **Comments:** explain the non-obvious "why", not the "what". Match the surrounding density.

## Build & Release

```
flutter build linux --release          # desktop bundle
./tool/build_appimage.sh               # local AppImage (uses the host libmpv)
BUNDLE_MPV=1 ./tool/build_appimage.sh  # portable AppImage (bundles libmpv; how CI builds it)
flutter test                           # offline tests
```

CI runs analyze, the i18n guard, and tests on every push; the AppImage workflow builds a self-contained binary on Ubuntu 24.04.

## Related Docs

- [ROADMAP.md](ROADMAP.md) — what's planned, what's done, what's parked.
- [README.md](README.md) — features, install, and translations.
