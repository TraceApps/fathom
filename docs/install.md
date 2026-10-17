# Install

Fathom runs on **Linux**, **Windows**, and **Android** (phones and tablets, with Android Auto, and Android TV as an experimental option). Each download is self-contained: libmpv and the media codecs are bundled, so there is nothing else to install.

Grab the newest build from the [Releases page](https://github.com/TraceApps/fathom/releases/latest).

## Linux (AppImage)

Fathom ships two Linux AppImages. Pick the one matching your CPU:

- **`Fathom-x86_64.AppImage`** for a normal PC (Intel / AMD).
- **`Fathom-aarch64.AppImage`** for ARM64 machines (Asahi Linux on Apple silicon, Raspberry Pi, and similar).

Download it, make it executable, and run it:

```bash
chmod +x Fathom-x86_64.AppImage
./Fathom-x86_64.AppImage
```

!!! warning "Run it with `./`, not `.\`"
    That is a forward slash. `.\Fathom-x86_64.AppImage` is Windows/PowerShell syntax and will fail in a Linux shell with `command not found`.

!!! tip "If it will not launch"
    An AppImage needs FUSE. On distributions that ship only fuse3 (Arch, for example), either install the compatibility library or run without FUSE:

    ```bash
    sudo pacman -S fuse2                     # or your distro's equivalent
    ./Fathom-x86_64.AppImage --appimage-extract-and-run
    ```

    See [Troubleshooting](troubleshooting.md) for the full list of launch fixes.

Once it runs, Fathom can keep itself up to date. See [Updates and channels](updates.md).

## Windows

Two options, same build either way:

- **`Fathom-Setup-x64.exe`**: a real installer with a Start Menu entry and uninstaller. Installs per-user (no admin prompt), so it stays fully compatible with Fathom's own in-app updater.
- **`Fathom-windows-x64.zip`**: extract it and run `fathom.exe` directly, no install step at all.

Windows will likely warn that the app is from an unrecognized publisher the first time (it is not code-signed); choose "More info" then "Run anyway."

## Nix

Fathom ships a flake, so on NixOS (or anywhere with Nix and flakes enabled) you can run it without downloading a release:

```bash
nix run github:TraceApps/fathom
```

Or build it and keep the result:

```bash
nix build github:TraceApps/fathom
./result/bin/fathom
```

It builds for `x86_64-linux` and `aarch64-linux`, pulls in mpv itself, and installs the desktop entry and icons like any other package. There is a dev shell too (`nix develop`) with the right Flutter and Dart for building from source.

## Android

Download the APK from [Releases](https://github.com/TraceApps/fathom/releases) (named like `Fathom-0.13.1.apk`) and open it. Android asks you to allow installing unknown apps the first time; grant it and confirm. Fathom runs on phones and tablets, and on Android TV, where the interface is D-pad friendly. Android TV support is experimental for now and still being refined.

After that, Fathom keeps itself up to date from **Settings → Updates**: it downloads the new APK and hands it to the system installer for you to confirm. Pick the **Dev** channel there if you want the pre-release test builds.

## macOS and iOS

Not available yet. Building for either needs Mac hardware (and, for iOS, a paid Apple Developer account). If you would like to see Fathom on Apple platforms, a [Ko-fi](https://ko-fi.com/traceapps) toward that hardware helps.

## Build from source

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install). Then:

```bash
flutter pub get
flutter build linux --release      # or: flutter build windows --release
```

`ffmpeg` is recommended but optional: it merges YouTube's separate video and audio streams when you download in higher quality. Everything else works without it.

For the packaged, self-contained AppImage (libmpv bundled), see [`tool/build_appimage.sh`](https://github.com/TraceApps/fathom/blob/main/tool/build_appimage.sh) and the [Contributing](contributing.md) guide.
