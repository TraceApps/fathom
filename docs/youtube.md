# YouTube

Fathom includes a complete YouTube client, off by default. Turn it on in **Settings**. It uses no account and shows no ads, and your subscriptions, playlists, and history stay on your device. Nothing is sent to YouTube.

## What it includes

- **Search** across videos, channels, and playlists.
- **Subscriptions and feed groups**, plus your own **local playlists**.
- **Comments, captions**, a play queue, and **theater mode**.
- **Chapters, the way YouTube shows them**: the current chapter's title sits in a pill beside the volume control and opens the chapter list, the seek bar splits into a segment per chapter, and hovering or dragging along the bar names the chapter you would land in.
- **Foldable phones**: in tabletop (half-folded with the crease across the screen) the video takes the standing half, with the details, comments, and Up Next on the flat half. Fullscreen splits the same way.
- **Shorts**: a vertical swipe pager through a channel's Shorts, with comments, a scrubbable progress bar, and portrait fullscreen.
- **Background audio**: keep listening with the screen off, with lock-screen and Android Auto controls, a queue, shuffle, and repeat.
- The same player as the rest of Fathom: one control bar, seek bar, speed control, and keyboard shortcuts.

## Cleaner viewing

- **[SponsorBlock](https://sponsor.ajay.app)** skips sponsor, intro, and self-promo segments.
- **DeArrow** replaces clickbait titles and thumbnails with community-sourced ones.
- **Return YouTube Dislike** brings back the dislike count.

Each is toggled in Settings.

## Downloads

Download videos for offline viewing:

- **Video** as MP4 or MKV.
- **Audio** as M4A or MP3.
- At a **quality** and to a **folder** you choose.

On Android 11 and newer, finished downloads go to **Movies/Fathom** (video) and **Music/Fathom** (audio) unless you pick another folder, so they show up in the Files app, your gallery and other players. Long-press a download for **Open With** and **Share**. A folder outside the phone's main storage, such as an SD card, falls back to those defaults.

!!! tip "Install ffmpeg on Linux"
    YouTube serves anything above 360p, and for more and more videos everything, as separate video and audio streams, which `ffmpeg` merges. Without it you can download audio, and a 360p MP4 only where YouTube still offers one. Android has ffmpeg built in, and the Windows download includes it from 0.13.1 on.

## Playback details

If your connection changes in the middle of a video (moving between Wi-Fi and mobile data, say), YouTube refuses the old stream, so Fathom fetches a fresh one and carries on from the same spot, at the same quality and with the same captions, instead of skipping to the next video. The same goes for the mini player and for YouTube music. If the connection is still down after a few tries, the video ends as it would at its end (so autoplay moves on); in the mini player it stops where it is, and reopening it tries again. For music, pressing Play tries again from that spot.

The [Playback Info](features.md#playback-info) overlay works here too. On YouTube its **Play method** line shows whether you are getting a high-quality **adaptive (DASH)** stream (separate video and audio) or the **muxed** fallback.
