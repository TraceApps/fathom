# Contributing

Fathom is built with [Flutter](https://flutter.dev). Contributions, bug reports, and translations are all welcome.

## Build from source

```bash
flutter pub get
flutter build linux --release      # or: flutter build windows --release
```

`ffmpeg` is recommended but optional (it merges YouTube's separate video and audio streams for higher-quality downloads).

For the packaged, self-contained AppImage that bundles libmpv, use [`tool/build_appimage.sh`](https://github.com/TraceApps/fathom/blob/main/tool/build_appimage.sh). It takes an `ARCH` of `x86_64` or `aarch64`.

## Run the tests

```bash
flutter test                              # offline, deterministic
flutter test --tags live --run-skipped    # hits real YouTube / network endpoints
```

## Learn the codebase

- **[ARCHITECTURE.md](https://github.com/TraceApps/fathom/blob/main/ARCHITECTURE.md)** is a tour of the code and the design decisions worth knowing before touching things.
- **[ROADMAP.md](https://github.com/TraceApps/fathom/blob/main/ROADMAP.md)** tracks what is planned, done, and parked.

## Translations

Fathom uses Flutter's built-in ARB localization (`gen_l10n`), the same approach the wider Jellyfin ecosystem uses, with one ARB file per language in `lib/l10n/`. The English file, `lib/l10n/app_en.arb`, is the source of truth.

### Two ways to contribute (pick either)

**A. Weblate (preferred, no code required).** Fathom is hosted at [hosted.weblate.org/projects/fathom/](https://hosted.weblate.org/projects/fathom/). Pick a language and translate strings in the web UI; Weblate commits your work to `dev`. If your language isn't in the list, click **Add new translation**. If you already have a completed ARB file, seed the language with **Files → Upload translation → Add as translation** on the language page.

[![Translation status](https://hosted.weblate.org/widget/fathom/multi-auto.svg)](https://hosted.weblate.org/engage/fathom/)

**B. Direct ARB PR.** Follow the steps below. This still works and Weblate will pick up the file on its next sync.

### Adding a new language via direct PR

1. Copy `lib/l10n/app_en.arb` to `lib/l10n/app_<code>.arb` where `<code>` is the language code (`fr`, `de`, `nl`, `es`, `pt_BR`, `ja`, `zh_Hans`, etc.), and set `"@@locale"` at the top to the same code.
2. Translate the values. Leave the keys exactly as they are; the `@key` blocks are notes for translators and can be left out. Keep `{placeholder}` tokens and plural blocks (`{count, plural, =1{1 second} other{{count} seconds}}`) intact, with the placeholders in the right grammatical position for your language.
3. Run `flutter gen-l10n`. It stops on a broken placeholder or plural. There is no list to register the language in: Fathom picks up every ARB file and shows a language when the device or desktop is set to it.
4. Open a PR against `dev`.

### Updating an existing language

If you translated through Weblate: keep using Weblate. Direct edits to a file that Weblate is watching will be overwritten by the next Weblate sync.

If new keys are added to `app_en.arb` between releases, `flutter gen-l10n` lists them for each language in `lib/l10n/untranslated_messages.txt`. Fathom falls back to English for those strings until you translate them. No urgency; translate at your own pace.

The English source text may also change occasionally without renaming the key. There is no automatic stale-translation detection, so a quick diff of `app_en.arb` against the version you originally translated from is the most reliable way to catch these.

### Translation guidance

- **Domain conventions matter.** For Jellyfin's own features (Quick Connect, SyncPlay, Live TV, DVR), use the words Jellyfin's apps use in your language. Jellyfin is translated on Weblate too, so its translations are a good reference.
- **Media words.** For Movies, Shows, Seasons, Episodes, Collections and Playlists, use what streaming apps in your language say, not literal translations.
- **Match the tone.** Fathom's English copy is short and direct ("Stop Recording?", "Move Existing Downloads?"). Try to keep that register rather than translating to a more formal style.
- **Length awareness.** Some buttons are tight on phones and in the player controls. If your translation is significantly longer than the English, check it on a phone-sized window.
- **Do not translate proper nouns or product names.** `Fathom`, `TraceApps`, `Jellyfin`, `Seerr`, `YouTube`, `SponsorBlock`, `DeArrow`, `Return YouTube Dislike`, `Trakt`, `IMDb`, `TMDB`, `GitHub`, `Ko-fi`, `ffmpeg`, `libmpv`, `Dolby Atmos` stay as-is.

### For code contributors: instrumenting new strings

Every user-facing string added to the app goes into `app_en.arb` and is read through `AppLocalizations`. Hardcoded English literals are the reason translation coverage lags the codebase; `tool/i18n_guard.sh` fails CI on new ones.

The pattern:

```dart
final l = AppLocalizations.of(context);

AppBar(title: Text(l.settingsTitle));
Text(l.settingsNoMatch(query));
```

Then in `lib/l10n/app_en.arb`:

```json
"settingsTitle": "Settings",
"@settingsTitle": {
  "description": "App bar title of the Settings screen."
},
"settingsNoMatch": "No settings match “{query}”",
"@settingsNoMatch": {
  "description": "Empty-state shown when a settings search returns nothing.",
  "placeholders": { "query": { "type": "String", "example": "subtitles" } }
}
```

Guidelines:

- **Prefix keys by area** (`common…`, `settings…`, `player…`, `detail…`, `yt…`), so related strings sit together.
- **Describe every key** in its `@key` block: where it shows and what any placeholder holds. Translators see it next to the string.
- **Only add English** in your PR. Do not machine-translate or hand-translate into other languages you don't natively speak; that misrepresents contributor work. The `app_en.arb` addition is enough; translators fill in the other languages through Weblate.
- **Skip developer-facing strings.** Error stacks, log messages, server content (titles, overviews, genres) and technical tokens (1080p, MP4, Mbps). Only pull out what a user reads on screen.
- **Placeholders** go in the `@key` block's `placeholders`. Prefer them over string concatenation so translators can reorder words.
- **A new setting** also needs its entry in the settings search index (`lib/screens/settings_search.dart`), in the same change.
- **Run `flutter gen-l10n` and `./tool/i18n_guard.sh`** before opening the PR.

### On putting words in a contributor's mouth

Do not add translations for locales you don't natively speak, and do not merge machine-translated content into a contributor's locale file. If a section can't be translated at code-write time (nobody on the PR speaks the language), add it to `app_en.arb`, open a follow-up "Translations wanted" issue linking the new keys, and let a native speaker fill them in. The English fallback keeps the app fully usable in the meantime.

### What's translatable today vs not

The whole interface is extracted: navigation, Home, libraries and detail pages, the video and music players, Live TV, YouTube, Seerr requests, downloads, Settings, and sign-in. Any new user-facing string is expected to land as a key in `app_en.arb` in the same commit, and `tool/i18n_guard.sh` flags hardcoded English in CI.

Content from your server (titles, overviews, genres) comes from Jellyfin as it is, and settings-search keywords stay English.

## These docs

The documentation site is built with [MkDocs Material](https://squidfunk.github.io/mkdocs-material/) from the `docs/` folder and deploys automatically when changes reach `main`. To preview locally:

```bash
pip install mkdocs-material
mkdocs serve      # then open http://127.0.0.1:8000
```

Keep the docs in step with the app: when a change alters something a user sees or does, update the relevant page in the same pull request.

## License

Fathom is free software under the [GNU AGPL-3.0](https://github.com/TraceApps/fathom/blob/main/LICENSE) license.
