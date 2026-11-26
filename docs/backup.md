# Backup and restore

Fathom can export its own settings to a portable file and import them on another device, on any platform. Find it under **Settings → Backup & Restore**.

!!! tip "Backing up the Jellyfin server itself"
    This page is about Fathom's own settings. To back up or restore your Jellyfin server (its database, and optionally metadata, subtitles, and trickplay images), use **Backups** in the server administration screens. See [Server administration](features.md#server-administration).

## What's included

Everything is organized into groups, and every group is selected by default. You choose which groups to export or import:

- **Appearance:** theme, accent color, AMOLED, Interface Size, the Home layout, the Discover layout and its custom sliders, the side menu's order, its hidden items and whether it's open or folded, rating badges, and grid or list view.
- **Player:** playback, subtitles, Volume Levelling, Up Next, and keyboard shortcuts.
- **YouTube:** its settings, and your YouTube library on this device: subscriptions, feed groups, the playlists you made, and the playlists you saved.
- **General:** notifications, update channel, the start screen, the Movie Night Wheel's lists, recent searches, the addresses of your Seerr and Manage connections (Sonarr, Radarr, Lidarr, Prowlarr, Bazarr, qBittorrent, SABnzbd), and anything else.
- **Internet radio:** your saved stations, groups, and favorites, and whether Radio is shown.
- **Servers:** the home and remote addresses of each server you're signed in to.

## What's never included

- **Passwords, Jellyfin sign-ins, and API keys.** A backup holds none. Signing in on a new device is done the usual way, and a restore never signs you out.
- **Each connection's key.** On a new device, give Seerr, each Manage app, SABnzbd and MDBList its API key again, and qBittorrent its password. Each says **Needs API key** in **Settings → Connections** until you do. MDBList has no row until its key is entered: add it with **Add Connection**.
- **What belongs to one device:** download folders, downloaded files and their lists, **Force TV Mode**, **Diagnostic Logging**, where the mini player sits, YouTube watch and search history, and the notification list.

On a device that already has keys, an import keeps each key only while its address stays the same. When the backup has a different address for a connection, that connection's key or password is cleared and asked for again, so a key is never sent to a server it wasn't given for. Changing qBittorrent's username clears its password too.

## Export

- **Desktop:** pick the groups, then **Export** saves a `fathom-settings.json` file wherever you choose.
- **Mobile:** **Export** opens the share sheet, so you can send the file by email, Bluetooth, or a cloud drive, or save it to Files.

## Import

Pick a `fathom-settings.json` file. Fathom shows the groups the file contains, all selected, and applies only the ones you keep checked:

- Preferences **merge** over your current ones, so importing a single group leaves the rest untouched.
- The internet radio library is **replaced** with the file's stations.
- YouTube's library is **added to**: what's in the file and not on this device comes back, and nothing already here is changed or removed.
- Server addresses are set only for a server you're signed in to, and only when the file was made from that same server (Fathom knows it by the server's own id, not its name). The addresses that will be set are listed under **Servers** before you import, because they decide where this device sends your sign-in. A backup made before 1.0 doesn't carry that id, so it sets no addresses; set them under **Settings → Server Addresses**.
- A setting the file has in a form this version can't read is skipped, and a number outside its range is brought back into it, so a damaged or hand-edited file can't leave the app unusable. A file made by a newer version of Fathom is refused.
