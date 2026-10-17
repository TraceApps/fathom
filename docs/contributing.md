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

Fathom's interface is internationalized with Flutter's built-in ARB localization, the same approach the wider Jellyfin ecosystem uses.

- English, [`lib/l10n/app_en.arb`](https://github.com/TraceApps/fathom/blob/main/lib/l10n/app_en.arb), is the source of truth. Every other language is an `app_<lang>.arb` beside it.
- Only English is edited in-repo; other locales flow in from translators, and the setup is Weblate-ready.
- After editing an ARB file, regenerate the bindings with `flutter gen-l10n`.

Translations are welcome by pull request.

## These docs

The documentation site is built with [MkDocs Material](https://squidfunk.github.io/mkdocs-material/) from the `docs/` folder and deploys automatically when changes reach `main`. To preview locally:

```bash
pip install mkdocs-material
mkdocs serve      # then open http://127.0.0.1:8000
```

Keep the docs in step with the app: when a change alters something a user sees or does, update the relevant page in the same pull request.

## License

Fathom is free software under the [GNU AGPL-3.0](https://github.com/TraceApps/fathom/blob/main/LICENSE) license.
