# Library and player

## Your library

- **Movies and TV**: libraries, search, rich detail pages, resume and Next Up, next and previous episode, skip intro, recap, and credits, an Up Next prompt that rolls into the next episode during the credits, chapters, and trickplay thumbnails as you scrub.
- **Browse by anything**: genres, studios, artists, and a page for every person, so a cast member's other work is one tap away. Trailers play in the app rather than sending you to a browser.
- **Extras**: a title's bonus material (behind the scenes, deleted scenes, interviews, featurettes, and trailer files held on your server) appears as its own row on the detail page, and plays in the normal player.
- **Favorites and Watchlist**: two separate personal lists, one for what you love, one for what you still want to watch. Toggle either from an item's detail page or its context menu (long-press, right-click, or the overflow button, they all open the same menu).
- **Continue Watching that follows what you watch**: one card per show, whether you stopped part-way through an episode or finished one and the next is waiting, ordered by what you actually watched most recently. A half-watched episode you abandoned long ago gives way to where you really are in the show, and a new episode of a show you were caught up on goes near the front the day it arrives.
- **Tidy up Continue Watching**: **Remove from Continue Watching** in a card's context menu takes that show or film off the row until you watch it again. If it had a resume point, that is cleared on the server too, so Jellyfin's other apps agree. Nothing is marked watched.
- **Home banner**: the banner at the top of Home mixes a few things you are in the middle of with what was added recently.
- **Movie Night Wheel**: when nobody can decide, spin for it. Fill the wheel from your library or type titles in, then pick a mode: Last One Standing knocks a title out on every spin, Single Spin takes the first result, and Best of 3 wants a title to win twice. It is reachable from the Watchlist, and from a SyncPlay session so a group can decide together.
- **Music**: albums, a play queue, now playing, shuffle and repeat, synced lyrics with an online fallback, and scrobbling. The now-playing screen flips between artwork and lyrics.
- **Live TV and DVR**: a channel list, an EPG guide, recording with series rules, and tuner and guide-provider setup.

## The player

The same player drives Jellyfin and [YouTube](youtube.md): one control bar, one seek bar (with chapter and skip markers), the same speed control, track pickers, and keyboard shortcuts, so nothing feels bolted on.

- **mpv-grade playback** through media_kit and libmpv: direct play with a transcode fallback, hardware decoding, and proper subtitle and audio track selection.
- **Picture in picture**: shrink a video into a floating mini player and keep browsing, or pop it out to a resizable, always-on-top window.
- **Up Next**: for an episode that has a next one, an Up Next card or compact Netflix-style pill appears during the credits and rolls into the next episode. Pick the style, and how long it waits before auto-skipping (the whole credits or a short countdown), under **Settings → Playback**, or leave Autoplay off and use its Play Now button.
- **Audio passthrough (desktop)**: bitstream Dolby Digital, DTS, and Dolby Atmos straight to an AV receiver instead of decoding to stereo.
- **Tune it to taste**: video fit, playback speed, a control bar you can style (glass, dark, or plain), remappable keyboard shortcuts, and scrub-preview thumbnails.
- **Foldable phones**: half-fold the phone with the crease across the screen (tabletop) and the video takes the standing half, with the controls on the flat half. The YouTube player does the same, in its watch page and in fullscreen.

### Subtitles and audio tracks

- **Every kind of subtitle**: text subtitles (SRT, ASS, WebVTT, MP4 text) are drawn by Fathom in the size, colour, and background you set under **Settings → Audio & Subtitles**. Picture-based subtitles from discs (Blu-ray PGS, DVD VobSub, DVB) are drawn by the player itself, since they are images rather than text.
- **Subtitles beside the video**: a subtitle file stored next to the video on your server, including one a subtitle plugin downloaded, shows in the subtitle menu and loads when you pick it.
- **Tracks you can tell apart**: subtitle and audio tracks are named from what the server knows about them, for example **English (Forced, SRT)**, **English (Picture, PGS)**, **English (External, SRT)**, or **English (DTS-HD MA 5.1)**. Tracks that would otherwise look the same are numbered. A forced track only captions foreign-language dialogue, so it stays quiet during the rest.
- **Search Subtitles Online**: the last row of the subtitle menu searches the subtitle provider installed on your Jellyfin server (such as the OpenSubtitles plugin) and adds the one you pick straight to the video. Matches for your exact file come first. It searches your preferred subtitle language, or your device's language if you have not set one, and **Change Language** searches another. It needs a subtitle provider plugin on the server, and is shown to administrators and to accounts allowed to manage subtitles.

### Playback Info

Open the settings gear in the control bar and choose **Playback Info** for a read-only overlay of what is really happening, read live from mpv:

- **Play method**: direct play vs transcode (or, on YouTube, adaptive vs muxed).
- **Video and audio**: codecs, resolution, frame rate, bitrates.
- **Decoder**: whether hardware decoding actually engaged (for example `Hardware (vaapi)` vs `Software`), and dropped-frame counts.
- **General**: container, buffer, and A/V sync.

It works in both the Jellyfin and YouTube players, and stays put when you enter fullscreen.

## Offline downloads

Download a movie, an episode, a whole season or series, a Live TV recording, a track, or an entire album, and watch or listen with the server out of reach.

- **Downloads is a real library**, not a list of files: Movies, TV Shows, Recordings, and Music sections with the same artwork and rating badges as your online library.
- **Detail pages work offline** too, scoped to what you actually have: only the episodes on the device, with local Play, Mark Watched, and Remove that never touch the server.
- **Pick a scope** when downloading a series (everything, or a single season), and watch progress on a floating pill with a Cancel All action.
- **Choose where it lands** under **Settings → Downloads**.

## Sleep timer

Every player has one, from the gear menu or the moon button in the top bar: music, video, YouTube, and radio. Pick anything from 15 minutes to 2 hours, or have it stop at the end of the current track or episode. The sound fades out over the last 15 seconds rather than cutting off, and the button shows the time left while it runs.

## Internet radio

Add stations by URL or search the built-in [radio-browser.info](https://www.radio-browser.info) directory. Organize them into groups and favorites, and reorder them by drag.

- **Live time-shift**: pause and rewind a live station within a buffered window, then hit **LIVE** to jump back to the edge.
- **Switch stations**: previous/next-station controls on the Now Playing screen, and on the OS media session too (the notification, Android Auto, and Linux/Windows media controls), so a keyboard media key or steering-wheel button skips to another saved station.
- **Now playing**: station art (with album-art lookup for stations that report track info), an inline volume control, and background playback.
- Radio can be cast to a speaker or TV alongside your music.

## Casting

Fathom casts to Chromecast and Google TV devices (on Android). Video direct-plays when the target supports the codecs, or falls back to a transcode for audio-only speakers, with a queue and skip that advance on the device.

## Android Auto

On Android, Fathom offers an audio-only Android Auto experience: browse your Jellyfin music, internet radio, and YouTube in tabs, search (including by voice) to play a song or playlist, and control playback, shuffle, repeat, favorites, and the up-next queue from the car's screen.

Because Fathom is sideloaded rather than installed from the Play Store, the first time you use it you need to allow apps from unknown sources in Android Auto's developer settings. See [Fathom does not appear in Android Auto](troubleshooting.md#fathom-does-not-appear-in-android-auto) if it is not listed.

## Requests, ratings, and watch together

- **Seerr (optional)**: browse and request titles, then approve, decline, or manage requests without leaving the page, with download progress shown right on the detail view. Set it up in [First-run setup](setup.md#seerr-requests).
- **Ratings that matter to you**: Rotten Tomatoes, IMDb, and community scores, plus Letterboxd, Metacritic, Trakt, and others through MDBList.
- **Watch together**: SyncPlay-based shared playback that interoperates with the official Jellyfin apps and other clients, not only with other Fathom users.

## Sonarr and Radarr

With Sonarr or Radarr connected (see [First-run setup](setup.md#sonarr-and-radarr)), the **Arr** section brings them into Fathom:

- **Calendar**: episodes airing and movie releases (in cinemas, digital, disc) from both apps, from yesterday through the next four weeks, grouped by day, each marked Downloaded, Missing, Unaired, or Not Released.
- **Queue**: everything downloading in either app, with progress, time left, quality, and the download client. Imports that need help (blocked or failed) come first, with the app's own explanation. It refreshes every few seconds while it's open. The **×** on a download removes it, with the choice to also remove it from the download client, blocklist the release so it's never grabbed again, and search for another right away.
- **Wanted**: monitored episodes and movies that are **Missing**, or whose file is below the quality profile's cutoff (**Cutoff Unmet**, with the quality you have now for episodes), newest first. The search button on each searches for that one, and **Search All** searches for everything on the list. Radarr also lists monitored movies that aren't out yet; they're marked Not Released and come last.
- **History**: everything both apps have done lately (grabs, imports, failed downloads, deletions, renames), newest first, with the release name, quality, and indexer or reason. A grab's **⋮** menu has **Mark as Failed**, which blocklists that release and, if the app is set to, searches for another.
- **Movies** and **Shows**: your Radarr and Sonarr libraries as poster grids, with the same colored status bar the apps use. Search, filter (monitored, missing, downloaded, continuing, ended), and sort by title, date added, year, or size.
- **Detail pages**: a movie's or show's quality profile, path, size, release dates, every season and episode with its file and quality, the file's video, audio, and subtitle details, and its history.

What you can do from a movie or show:

- **Search**: **Search Movie**, or **Search Monitored** for a show, has the app search your indexers and grab the best release it finds. Each season has its own search button, and so does each episode (tap the episode).
- **Interactive Search**: lists every release your indexers offer for a movie, a season, or an episode, the way the apps' own Interactive Search does: quality, size, age, indexer, Usenet or torrent (with seeders and leechers), custom format score, and the app's verdict. Releases the app rejected say why, and **Grab** still lets you take one after confirming. Sort by Best Match (the app's own ranking), Quality, Size, Age, or Seeders, and hide rejected releases if you like.
- **Monitor** or **Unmonitor** a movie, a whole show, a season (its bookmark), or an episode.
- **Edit**: the quality profile and monitoring, plus Minimum Availability for a movie, or Series Type and Season Folders for a show.
- Under **More**: **Refresh & Scan**, **Rename Files** (shows each file's current and new name first; it needs renaming turned on in the app's Settings, Media Management), **Open in Sonarr** or **Open in Radarr**, and **Delete**, with the choice to delete the files too and to keep import lists from adding it again.
- **Delete File** under a file removes just that file from disk.

**Add Movie** and **Add Show** (the **+** next to the search box) search online by name, or exactly by `tmdb:`, `imdb:` or `tvdb:` id. Titles the app already has say **In Library** and open their page. Adding asks for the root folder (with its free space), what to monitor, the quality profile, and Minimum Availability for a movie or Series Type and Season Folders for a show, and can start a search right away. Fathom remembers your choices for the next one while it's open.

**Health**, the shield at the top of the Arr section, shows each app's version and what its own health check has found, such as an indexer that keeps failing or a missing root folder, with **Learn More** linking to the app's wiki page about it. A badge counts the warnings and errors.

**From a Jellyfin movie or show**: when Radarr (movies) or Sonarr (shows) is connected, the **⋮** menu on the title's page finds it there by its TMDB or TVDB id. If the app has it, **Manage in Radarr** or **Manage in Sonarr** opens its page in the Arr section, and **Search Movie** (or **Search Monitored**, for missing episodes) and, for a movie, **Interactive Search**, for a better copy, start right there. If the app doesn't have it, **Add to Radarr** or **Add to Sonarr** opens Add Movie or Add Show with that title already found. Jellyfin titles without the id don't show these.

The apps' one-time setup (indexers, download clients, custom formats, and media management rules) stays in their own web pages.

## Server administration

Run most of Jellyfin from the app, without opening the web dashboard: manage users, libraries, scheduled tasks, active sessions, playback and transcoding, networking, branding, Live TV and DVR, backups, and plugins. Each plugin's configuration is an in-app form (toggles, fields, and add/remove lists), with a raw-JSON option if you prefer, and plugin logos show in the list.

**Backups** (on servers that offer them): create a backup of the server, choosing whether to include metadata, subtitles, and trickplay images alongside the database, see what each backup holds and the server version it was made on, and restore one. Backups are stored on the server itself. Restoring restarts the server and replaces everything changed since the backup was made, and should only be done onto the same Jellyfin version the backup came from.

## Personalization

Light, dark, and AMOLED themes with a custom accent color, an Interface Size setting for high-resolution screens (desktop), a Home layout you can rearrange, a sidebar whose items you can reorder or hide, in-app updates with a Stable or Dev channel, system and in-app notifications, a Settings screen you can search, and a fully translatable interface.

- **Several accounts**: keep more than one Jellyfin account (or server) signed in and switch between them without re-entering anything.
- **Screen readers**: cards announce themselves as a single item with their title and year, every icon-only button carries a label, and the Movie Night Wheel names its titles and reads out each result.

## Notifications

Fathom keeps an in-app notification centre (the bell), and shows an in-app toast while you're using the app. Choose which events you care about under **Settings → Notifications**:

- **Seerr requests**: a new request (pending approval), or one of yours being approved, declined, or becoming available.
- **Download complete**: when a download to this device finishes.
- **Update available**: when a new version of Fathom is released.

While the app is open, Fathom checks Seerr for status changes every minute or so, so updates surface almost immediately as a toast and land in the bell. On **desktop**, when Fathom is in the background these also appear as system (OS) pop-ups, toggled by the master switch at the top of the section. On **mobile**, backgrounded events wait quietly in the bell rather than raising a system notification. Either way, the per-event toggles decide what gets recorded in the first place.
