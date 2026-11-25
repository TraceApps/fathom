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

Everything Fathom connects to besides your Jellyfin server is in one place, **Settings → Connections**: Seerr, the Manage apps (Sonarr, Radarr, Lidarr, Prowlarr, Bazarr), the download clients and MDBList. **Add Connection** lists them all with what each is for, and they all work the same way: **Save & Test** tries a connection before saving it, the list says how each one is doing, and **Disconnect** asks first.

### Seerr (requests)

Point Fathom at your [Jellyseerr / Overseerr](https://docs.jellyseerr.dev) instance to browse and request titles, then approve, decline, or manage requests without leaving the detail page. Download progress shows right on the page. In **Settings → Connections**, press **Add Connection** and pick **Seerr**. Give its address (for example `http://192.168.1.10:5055`), then either its API key (in Seerr under **Settings → General**; requests are then made as the admin) or switch to **Sign In** and use your Jellyfin or Seerr account, so requests are made as you. **Save & Test** checks the address really is Seerr and that it takes the key before saving; when it doesn't, the page says why and nothing is saved, and **Save Anyway** keeps it all the same. Once connected, a **Discover** section appears in the navigation, under the Seerr logo.

Discover follows your Seerr server's own display settings: with **Hide Available**, **Hide Already Requested** (Seerr 3.5 and later), or **Hide Blocklisted** turned on in Seerr, those titles stay out of Fathom's Discover rows too, just as on Seerr's web page. Search still finds them.

### Sonarr, Radarr and Lidarr

Connect [Sonarr](https://sonarr.tv) for shows, [Radarr](https://radarr.video) for movies and [Lidarr](https://lidarr.audio) for music, any of them, in **Settings → Connections**. Press **Add Connection** and pick the app. Each needs the server address (for example `http://192.168.1.10:8989` for Sonarr, `:7878` for Radarr, `:8686` for Lidarr, plus any URL base you set, such as `/sonarr`) and its API key, found in that app under **Settings → General → Security**. Once one app is connected, the next one's address starts on the same computer at that app's usual port, so often only the key is left to paste (not when the address you gave has a URL base: behind a reverse proxy the next app's place can't be guessed).

**Save & Test** checks the address really is that app before saving and shows its version. When it can't connect, the page says why (the app refused the API key, nothing answered, or the address is another app) and nothing is saved; **Save Anyway** keeps it all the same, for a server that's off right now.

Connections then lists what's connected, by kind (Requests, Apps, Download Clients, Ratings), each with its address, its version and how it's doing: **Connected**, **Can't connect**, or **Needs API key** (after a restore, see below). Pick one for its page: its address and key, **Defaults for New Titles** for Sonarr, Radarr and Lidarr, and **Disconnect**, which asks first. In a wide window the page opens beside the list. Under **Settings**, Connections says how many are connected.

[Prowlarr](https://prowlarr.com), the indexer manager behind them, is under **Add Connection** too (`:9696`). It adds an **Indexers** page to the Manage section; with only Prowlarr connected, Manage opens straight on it.

[Bazarr](https://www.bazarr.media), the subtitles app beside them, connects the same way (`:6767`, with the API key from Bazarr's **Settings → General → Security**). It adds a **Subtitles** page to the Manage section. Bazarr itself keeps the languages you want and the providers it asks; set those up in Bazarr.

[qBittorrent](https://www.qbittorrent.org) and [SABnzbd](https://sabnzbd.org), the download clients behind them, are under **Download Clients** in **Add Connection**. qBittorrent needs its Web UI address (`:8080`) and its username and password; leave both blank if qBittorrent lets your network in without a sign-in (**Bypass authentication for clients in whitelisted IP subnets** under its **Options → WebUI**). SABnzbd needs its address (`:8085`) and its API key, found under **Config → General → Security**. They add a **Download Clients** page to the Manage section; with only a download client connected, Manage opens straight on it.

More than one server of an app, such as a 4K Radarr beside the usual one: **Add Connection**, pick the app again, and give the new server a name (such as 4K) with its address and API key. Each server is a row of its own, named after the app and the server (the first one is **Main** until you name it). One server of each app is in use at a time, marked **In use**; put another in use with **Use This One** on its page, or with **Switch Server** at the top of the Manage section. Each server keeps its own Defaults for New Titles, set while it's in use. Each needs a name and an address of its own. Disconnecting the one in use puts the next one that has its key in use. An app's other servers keep their API keys on this device too, out of backups: after a restore, each one says **Needs API key** until you give it its key again on its page.

Once connected, a **Manage** section appears in the navigation. The API keys and the qBittorrent password stay on this device and are never included in [Backup & Restore](backup.md).

### YouTube

A complete YouTube client with no account and no ads. Turn it on in **Settings**, and see the [YouTube](youtube.md) page for what it includes.

### Internet radio

Add stations by URL or search the built-in [radio-browser.info](https://www.radio-browser.info) directory, organize them into groups and favorites, and play them with live time-shift (pause and rewind a live stream). See [Features → Internet radio](features.md#internet-radio).

### Ratings

Optionally enrich detail pages with Rotten Tomatoes, IMDb, and community scores, plus Letterboxd, Metacritic, Trakt, and others through [MDBList](https://mdblist.com). Choose the sources you want in **Settings → Ratings**. The MDBList ones need MDBList connected: **Settings → Connections → Add Connection → MDBList** (the Ratings page links there too), with the free API key from your Preferences on mdblist.com. **Save & Test** checks that MDBList takes the key.

## Make it yours

- **Themes**: light, dark, and AMOLED, with a custom accent color.
- **Interface Size** (Linux and Windows): make everything bigger or smaller. **Automatic** follows your display, and on Linux it also sizes up on a dense screen, such as a 4K monitor, when your desktop's scaling is left at 100%.
- **Home**: rearrange the rows to taste.
- **Player**: video fit, default playback speed, a control bar you can style (glass, dark, or plain), and remappable keyboard shortcuts.
- **Search your settings**: the Settings screen has its own search, so you do not have to hunt for an option.
- **Language**: Fathom follows your device's or desktop's language. Every language translated so far is used automatically; anything not yet translated shows in English. To add or improve a language, see [Translations](contributing.md#translations).
