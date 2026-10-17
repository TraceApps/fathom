<h1 align="center">Fathom<br/><sup><sup><sub>from <a href="https://traceapps.github.io/docs/">TraceApps</a></sub></sup></sup></h1>

<p align="center"><b>Dive into your media</b></p>

<p align="center">An all-in-one client for Jellyfin, on desktop and Android.<br/>
Your media, your server, Seerr requests, and YouTube, without leaving the app.</p>

<p align="center">
  <img src="assets/icon/fathom.png" alt="Fathom" width="128" />
</p>

<p align="center">
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-AGPL--3.0-blue"></a>
  <a href="https://github.com/TraceApps/fathom/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/TraceApps/fathom?label=release&color=orange"></a>
  <a href="https://github.com/TraceApps/fathom/releases"><img alt="Downloads" src="https://img.shields.io/github/downloads/TraceApps/fathom/total?label=downloads&color=brightgreen"></a>
  <a href="https://github.com/TraceApps/fathom/stargazers"><img alt="Stars" src="https://img.shields.io/github/stars/TraceApps/fathom?style=social"></a>
  <a href="https://traceapps.github.io/fathom/install/"><img alt="Platform" src="https://img.shields.io/badge/platform-Linux%20%7C%20Windows%20%7C%20Android-lightgrey"></a>
  <br/>
  <a href="https://traceapps.github.io/fathom/"><img alt="Documentation" src="https://img.shields.io/badge/docs-traceapps.github.io-8A2BE2?logo=readthedocs&logoColor=white"></a>
</p>

<p align="center">
  <b>Coming to Apple devices:</b> Fathom has no Mac or iPhone app yet, because building and testing them needs a Mac and an iPhone.
  <a href="https://ko-fi.com/traceapps">Chip in on Ko-fi</a>. Fathom stays free either way.
</p>

---

**Jump to:** [Highlights](#highlights) · [Install](#install) · [Documentation](https://traceapps.github.io/fathom/) · [Releases](https://github.com/TraceApps/fathom/releases/latest)

---

Fathom brings your whole Jellyfin setup into one window: movies, shows, music, and Live TV, plus most of Jellyfin's server-side management, so you rarely need the web dashboard. Two optional integrations, Seerr requests and a full YouTube client, live right inside the app. Everything plays through mpv (via [media_kit](https://github.com/media-kit/media-kit) / libmpv), so you get direct play, hardware decoding, and real subtitle and audio track control.

## Highlights

- **One player for everything.** Jellyfin and YouTube share the same control bar, seek bar, speed control, track pickers, and keyboard shortcuts, plus a **Playback Info** overlay that shows codecs, resolution, and the live hardware-decode path.
- **Run your server from the app**: users, libraries, scheduled tasks, transcoding, Live TV and DVR, and more, without the web dashboard.
- **YouTube, built in** (optional): search, subscriptions, local playlists, SponsorBlock, DeArrow, downloads, theater mode. No account, no ads.
- **Requests and ratings**: Seerr browse-and-request with manage-in-place, plus Rotten Tomatoes, IMDb, and more.
- **Internet radio** with live time-shift, **casting**, **watch together** over SyncPlay, **picture-in-picture**, and light / dark / AMOLED themes.

See the [feature tour](https://traceapps.github.io/fathom/features/) for the full list.

## Install

Fathom runs on **Linux** and **Windows** (self-contained, nothing else to install) and on **Android** phones, tablets, and foldables, with **Android Auto**. **Android TV** is supported but experimental for now. macOS and iOS need Mac hardware.

Grab the latest build from [Releases](https://github.com/TraceApps/fathom/releases/latest). On Linux:

```bash
chmod +x Fathom-x86_64.AppImage
./Fathom-x86_64.AppImage
```

On Android, download the `.apk` and open it to install (allow installs from your browser or file manager if prompted). The same APK covers phones, tablets, and Android TV (Android TV is experimental for now).

Full instructions, first-run setup, and troubleshooting are in the **[documentation](https://traceapps.github.io/fathom/install/)**.

## Documentation

The docs cover installing, connecting your server, every feature, the update channels, and troubleshooting:

**[traceapps.github.io/fathom](https://traceapps.github.io/fathom/)**

## Contributing

[ARCHITECTURE.md](ARCHITECTURE.md) is a tour of the codebase; [ROADMAP.md](ROADMAP.md) tracks what's planned. Build from source, tests, and the translation workflow are in the [contributing guide](https://traceapps.github.io/fathom/contributing/). Translations are welcome by pull request.

## Support

Fathom is free and open source, and always will be. No paid tier, nothing behind a donation, no telemetry. It's built and maintained by one person.

**The current goal is a Mac and an iPhone.** Building Fathom for macOS or iOS needs the Mac, and testing on a real phone needs the iPhone. The same fund covers the Trace apps, which need the same hardware, so it's one goal rather than two. The itemised breakdown is on the [Support page](https://traceapps.github.io/docs/support/).

Helping doesn't have to cost anything: starring the repo, reporting bugs with detail, and translating all count.

[![Ko-fi](https://img.shields.io/badge/Ko--fi-Toward_a_Mac_and_iPhone-FF5E5B?logo=ko-fi&logoColor=white)](https://ko-fi.com/traceapps) [![GitHub Sponsors](https://img.shields.io/badge/GitHub_Sponsors-Sponsor_monthly-EA4AAA?logo=githubsponsors&logoColor=white)](https://github.com/sponsors/TraceApps?metadata_app=fathom&metadata_from=readme)

## License

Fathom is free software, licensed under the [GNU Affero General Public License v3.0](LICENSE). SponsorBlock data, when enabled, comes from the [SponsorBlock](https://sponsor.ajay.app) API under [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/).
