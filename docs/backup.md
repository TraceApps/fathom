# Backup and restore

Fathom can export its own settings to a portable file and import them on another device, on any platform. Find it under **Settings → Backup & Restore**.

!!! tip "Backing up the Jellyfin server itself"
    This page is about Fathom's own settings. To back up or restore your Jellyfin server (its database, and optionally metadata, subtitles, and trickplay images), use **Backups** in the server administration screens. See [Server administration](features.md#server-administration).

## What's included

Everything is organized into groups, and every group is selected by default. You choose which groups to export or import:

- **Appearance:** theme, accent color, AMOLED, Interface Size, and Home layout.
- **Player:** playback, subtitles, and keyboard shortcuts.
- **YouTube:** client toggles and download preferences.
- **General:** notifications, update channel, language, the addresses of your Seerr and Manage connections (Sonarr, Radarr, Lidarr, Prowlarr, Bazarr, qBittorrent, SABnzbd), and anything else.
- **Internet radio:** your saved stations, groups, and favorites.
- **Servers:** your home and remote server addresses, and username.

Passwords, Jellyfin tokens, and API keys are **never** exported, so after importing you sign in to your server again (your address and username are already filled in from the Servers group).

The same goes for every connection: on a new device, give Seerr, each Manage app, SABnzbd and MDBList its API key again, and qBittorrent its password. Each one says **Needs API key** in **Settings → Connections** until you do.

On a device that already has those keys, an import keeps each key only while its address stays the same. When the backup has a different address for a connection, that connection's key or password is cleared and asked for again, so a key is never sent to a server it wasn't given for.

## Export

- **Desktop:** pick the groups, then **Export** saves a `fathom-settings.json` file wherever you choose.
- **Mobile:** **Export** opens the share sheet, so you can send the file by email, Bluetooth, or a cloud drive, or save it to Files.

## Import

Pick a `fathom-settings.json` file. Fathom shows the groups the file contains, all selected, and applies only the ones you keep checked:

- Preferences **merge** over your current ones, so importing a single group leaves the rest untouched.
- The internet radio library is **replaced** with the file's stations.
- Server addresses are re-applied if you're signed into the same server.
