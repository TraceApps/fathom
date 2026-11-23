# First-run setup

## Connect to Jellyfin

On first launch, Fathom asks for your Jellyfin server:

1. Enter your **server address**, for example `http://192.168.1.10:8096` or `https://jellyfin.example.com`.
2. Sign in with your **Jellyfin username and password**.

That is all that is required. Everything else, including the optional integrations below, is off until you turn it on.

!!! note "Server versions"
    Fathom follows current Jellyfin releases, including Jellyfin 12, and uses the API routes each release documents. Where an older server does not have one of those routes, Fathom falls back to the route that server does have, so older servers keep working.

!!! tip "Quick Connect"
    If your server has Jellyfin Quick Connect enabled, you can authorize Fathom from another signed-in device instead of typing a password.

Once connected, your libraries, Home layout, resume list, and Next Up appear straight away.

## Optional integrations

Each of these lives in **Settings** and is off by default. Turn on only what you use.

### Seerr (requests)

Point Fathom at your [Jellyseerr / Overseerr](https://docs.jellyseerr.dev) instance to browse and request titles, then approve, decline, or manage requests without leaving the detail page. Download progress shows right on the page. You will need your Seerr URL and API key (or sign in), set in **Settings → Seerr**. Once connected, a **Discover** section appears in the navigation, under the Seerr logo.

Discover follows your Seerr server's own display settings: with **Hide Available**, **Hide Already Requested** (Seerr 3.5 and later), or **Hide Blocklisted** turned on in Seerr, those titles stay out of Fathom's Discover rows too, just as on Seerr's web page. Search still finds them.

### Sonarr, Radarr and Lidarr

Connect [Sonarr](https://sonarr.tv) for shows, [Radarr](https://radarr.video) for movies and [Lidarr](https://lidarr.audio) for music, any of them, in **Settings → Manage Connections**. Each needs the server address (for example `http://192.168.1.10:8989` for Sonarr, `:7878` for Radarr, `:8686` for Lidarr, plus any URL base you set, such as `/sonarr`) and its API key, found in that app under **Settings → General → Security**. **Save & Test** checks the address really is that app and shows its version.

[Prowlarr](https://prowlarr.com), the indexer manager behind them, connects the same way below them (`:9696`). It adds an **Indexers** page to the Manage section; with only Prowlarr connected, Manage opens straight on it.

[Bazarr](https://www.bazarr.media), the subtitles app beside them, connects the same way below Prowlarr (`:6767`, with the API key from Bazarr's **Settings → General → Security**). It adds a **Subtitles** page to the Manage section. Bazarr itself keeps the languages you want and the providers it asks; set those up in Bazarr.

[qBittorrent](https://www.qbittorrent.org) and [SABnzbd](https://sabnzbd.org), the download clients behind them, connect under **Download Clients** on the same page. qBittorrent needs its Web UI address (`:8080`) and its username and password; leave both blank if qBittorrent lets your network in without a sign-in (**Bypass authentication for clients in whitelisted IP subnets** under its **Options → WebUI**). SABnzbd needs its address (`:8085`) and its API key, found under **Config → General → Security**.

More than one server of an app, such as a 4K Radarr beside the usual one, goes under **Servers** on that app's card: **Add Server** takes a name (such as 4K), the address and the API key, and checks them before saving. One server of each app is in use at a time; pick it with **Use This One** there, or with **Switch Server** at the top of the Manage section. Each server keeps its own Defaults for New Titles, and an app's other servers keep their API keys on this device too (out of backups: after a restore, give each one its key again under **Servers**). Each server needs a name of its own. Typing another saved server's address on the card puts that one in use, and disconnecting the one in use puts the next one that has its key in use. They add a **Download Clients** page to the Manage section; with only a download client connected, Manage opens straight on it.

Once connected, a **Manage** section appears in the navigation. The API keys and the qBittorrent password stay on this device and are never included in [Backup & Restore](backup.md).

### YouTube

A complete YouTube client with no account and no ads. Turn it on in **Settings**, and see the [YouTube](youtube.md) page for what it includes.

### Internet radio

Add stations by URL or search the built-in [radio-browser.info](https://www.radio-browser.info) directory, organize them into groups and favorites, and play them with live time-shift (pause and rewind a live stream). See [Features → Internet radio](features.md#internet-radio).

### Ratings

Optionally enrich detail pages with Rotten Tomatoes, IMDb, and community scores, plus Letterboxd, Metacritic, Trakt, and others through [MDBList](https://mdblist.com). Configure the sources you want in **Settings**.

## Make it yours

- **Themes**: light, dark, and AMOLED, with a custom accent color.
- **Interface Size** (Linux and Windows): make everything bigger or smaller. **Automatic** follows your display, and on Linux it also sizes up on a dense screen, such as a 4K monitor, when your desktop's scaling is left at 100%.
- **Home**: rearrange the rows to taste.
- **Player**: video fit, default playback speed, a control bar you can style (glass, dark, or plain), and remappable keyboard shortcuts.
- **Search your settings**: the Settings screen has its own search, so you do not have to hunt for an option.
- **Language**: Fathom follows your device's or desktop's language. Every language translated so far is used automatically; anything not yet translated shows in English. To add or improve a language, see [Translations](contributing.md#translations).
