# Roadmap

What's done, what's next, and what's parked. The client is feature-complete for day-to-day use; the road to 1.0 is about stability and trust, plus one new feature: managing Sonarr, Radarr and Lidarr and the apps behind them.

## Road to 1.0

- [x] **0.13.1 stable**: released, now getting real use.
- [ ] **Real-server tests**: run the core flows (sign in, browse, play, resume, mark watched, subtitles) in CI against real Jellyfin servers, old and current, so a break is caught by a failing check rather than by a user.
- [x] **Decide 1.0's scope**: Linux, Windows, Android phones and tablets, and Android TV are in.
- [x] **Translations**: open to everyone on Weblate.
- [x] **Sonarr, Radarr and Lidarr in Fathom**: Library, Calendar, Activity (queue, history, blocklist) and Wanted, with detail pages, searches (automatic and interactive), adding, monitoring (with the apps' own options), editing, renaming, deleting, picking several titles to change together, Manual Import, Import Library, Radarr's collections, shortcuts from Jellyfin's own pages, and Seerr requests in Discover. Also Prowlarr's indexers, Bazarr's subtitles, the download clients (qBittorrent and SABnzbd), more than one server of an app, notifications (on Android, while Fathom is closed too), right-click menus and keyboard shortcuts on a desktop, and Android TV.
- [x] **Design pass**: one look and one way of doing things across the app: one Connections screen, one toolbar for every library, the same menus, errors and loading everywhere, readable colors in the light theme, and a remote that reaches everything on Android TV.
- [ ] **1.0.0 release candidate**: bug fixes only, for a few weeks.
- [ ] **1.0.0**

## Done

### Foundation

- [x] Connect to a Jellyfin server, sign in (including Quick Connect), and keep several accounts or servers signed in at once
- [x] Home, libraries, search, and rich detail pages
- [x] Follows current Jellyfin releases, including Jellyfin 12, with fallbacks that keep older servers working

### Movies, TV, and music

- [x] mpv-grade playback: direct play, transcode fallback, hardware decoding, audio passthrough, and a Playback Info overlay
- [x] Resume, Next Up, next and previous episode, skip intro, recap, and credits, an Up Next prompt, chapters, and trickplay previews on the scrubber
- [x] Every kind of subtitle: text, picture-based (PGS, VobSub), and subtitle files beside the video, with readable track names and online subtitle search through the server
- [x] A Continue Watching row that follows what you actually watch, one card per show
- [x] Extras, favorites, a watchlist, person pages, collections, and the Movie Night Wheel
- [x] Music: albums, a play queue, now playing, shuffle and repeat, synced lyrics, ReplayGain, and scrobbling
- [x] Offline downloads that behave like a real library

### Live TV, YouTube, and integrations

- [x] Live TV, an EPG guide, and DVR with series rules
- [x] Built-in ad-free YouTube client: search, subscriptions, playlists, comments, chapters, Shorts, a play queue, background audio, SponsorBlock, DeArrow, and downloads
- [x] Internet radio with live time-shift
- [x] Seerr requests, ratings (Rotten Tomatoes, IMDb, community, and MDBList sources), watch together (SyncPlay), and casting to Chromecast and Google TV
- [x] Server administration: users (every permission the web dashboard offers), libraries, scheduled tasks, sessions, transcoding, networking, branding, Live TV, backups, and plugins

### Player and interface

- [x] One shared player across Jellyfin and YouTube, with a picture-in-picture mini player and a pop-out window
- [x] A control bar you can style, remappable keyboard shortcuts, themes, an Interface Size setting for high-resolution screens, a sleep timer, and a searchable settings screen
- [x] Layouts for foldable phones (tabletop) and screen reader support
- [x] Full interface internationalization (English source of truth, Weblate-ready)

### Release and reach

- [x] Self-contained Linux AppImage (x86_64 and aarch64)
- [x] Windows installer and portable zip
- [x] Android app for phones, tablets, and foldables, with Android Auto
- [x] Nix flake
- [x] In-app updates with a Stable or Dev channel
- [x] Android TV
- [ ] macOS and iOS builds (pending Mac hardware and a paid Apple Developer account)

## Next

- [ ] A listening and watching stats screen for servers with the Playback Reporting plugin
- [ ] Collections you can create and edit, not just browse
- [ ] Styled ASS subtitles (anime fonts, colors, and positioning)
- [ ] YouTube channel video sorting (Latest, Popular, Oldest)

## Parked

- DLNA and AirPlay casting: Chromecast covers most homes, and "Play on device" remote control covers the rest
- YouTube watch-together (SyncPlay for YouTube): tiny audience and fragile against YouTube changes
- Distribution packages (AUR, Flathub, .deb): the AppImage, Windows, Android, and Nix builds cover every supported platform for now
