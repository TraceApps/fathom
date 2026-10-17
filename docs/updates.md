# Updates and channels

Fathom updates itself. On Linux it swaps the AppImage in place and relaunches; on Windows it replaces the install folder and relaunches (this works the same way whether you installed via the `.exe` installer or just extracted the zip, both land in a folder Fathom owns); on Android it downloads the APK and hands it to the system installer (you confirm the prompt, granting "install unknown apps" the first time). You can also just download a newer build from [Releases](https://github.com/TraceApps/fathom/releases) at any time.

Open **Settings → Updates** to check manually, choose a channel, and turn automatic checking on or off. When it is on, pick how often it checks: every launch, daily, or weekly (a daily or weekly check also runs in the background while the app stays open, so you do not have to relaunch to pick it up).

## Channels

| Channel | What you get |
| --- | --- |
| **Stable** | Only full releases (for example `0.13.1`). The default. |
| **Dev** | Full releases plus pre-release test builds, so you get new features and fixes early. |

The updater always offers the newest version for your channel and downloads the build that matches your platform and CPU architecture automatically (x86_64 vs aarch64 on Linux; a universal APK on Android). When a new build is found, Fathom shows a dismissible banner and, on Linux and Android, a native system notification.

## How versions work

- **Stable releases** are plain versions like `0.13.1`.
- **Dev builds** are pre-releases named `0.13.1-dev01`, `0.13.1-dev02`, and so on. The Dev channel tracks these in order and rolls you onto the next stable release when it lands.
- A floating **`dev-latest`** pre-release always points at the newest dev build, as a stable download link. The in-app updater tracks the numbered builds, not this alias.

!!! note "Safe by design"
    Before installing, Fathom verifies the download's size and, on Linux, that the AppImage matches your machine's architecture. If something is wrong (a truncated download, or a mismatched build), it keeps your working version and reports the problem instead of installing a broken file.

## Update did not relaunch, or will not start

Almost always this is a download that was grabbed mid-publish, or a wrong-architecture file from an older build. See [Troubleshooting → Updating](troubleshooting.md#updating) for the fix.
