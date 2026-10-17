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

Point Fathom at your [Jellyseerr / Overseerr](https://docs.jellyseerr.dev) instance to browse and request titles, then approve, decline, or manage requests without leaving the detail page. Download progress shows right on the page. You will need your Seerr URL and API key (or sign in), set in **Settings → Seerr**.

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
