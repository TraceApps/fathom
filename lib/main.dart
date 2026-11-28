import 'api/jellyfin_client.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:uuid/uuid.dart';
import 'package:window_manager/window_manager.dart';

import 'package:audio_service/audio_service.dart';

import 'app.dart';
import 'services/secure_http.dart';
import 'services/tv_mode.dart';
import 'state/retry.dart';
import 'widgets/tv_focus.dart' show tvPassInertRows;
import 'services/app_installer.dart';
import 'services/desktop_integration.dart';
import 'services/diagnostics.dart';
import 'services/notifications.dart';
import 'services/resilient_secure_storage.dart';
import 'state/audio_handler.dart';
import 'state/interface_scale.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize libmpv-backed playback before the UI starts.
  MediaKit.ensureInitialized();

  // The Inter typeface ships inside the app under the SIL Open Font License,
  // which asks that the license travel with it: list it with the others.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const ['Inter'],
        await rootBundle.loadString('assets/fonts/Inter-OFL.txt'));
  });

  // Trust the bundled CA roots for all HTTPS (Windows only; see the function).
  // Must run before any outbound request (YouTube, update checks).
  await installSecureHttpOverrides();

  // Detect Android TV (leanback) up front so screens can swap the un-drivable
  // system keyboard for the on-screen TvKeyboard.
  await detectTvMode();
  // Honor a manual "Force TV mode" preference (HTPC / desktop-on-a-TV) when
  // the platform didn't report a television.
  await applyForcedTvMode();
  // A TV is driven by its remote, never by touch: show where the remote is
  // on every row and control. Left to itself, Flutter can stay in touch
  // mode on a TV and hide the focus tint of list rows (Settings, menus).
  if (isTvDevice) {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    // And past the rows that only hold a setting's control, onto it.
    tvPassInertRows();
  }
  // Learn which video codecs decode in hardware so the Jellyfin profile can
  // transcode the rest (keeps AV1 off low-power TV sticks that would software
  // decode it and stutter).
  await detectHardwareCodecs();
  // How Fathom names itself to Jellyfin (its Devices and Activity pages).
  try {
    JellyfinClient.appVersion = (await PackageInfo.fromPlatform()).version;
  } catch (_) {}
  JellyfinClient.deviceName = isTvDevice
      ? 'Android TV'
      : Platform.isAndroid
          ? 'Android'
          : Platform.isWindows
              ? 'Windows'
              : Platform.isMacOS
                  ? 'macOS'
                  : Platform.isLinux
                      ? 'Linux'
                      : 'Fathom';

  // App-wide diagnostics capture. These hooks are always installed but only
  // record while the user has Diagnostic Logging on (Diagnostics.add no-ops
  // otherwise), so errors and app logs from anywhere in the app land in the
  // one exportable buffer, not just playback.
  final priorOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    Diagnostics.instance.add('flutter', details.exceptionAsString());
    priorOnError?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    Diagnostics.instance.add('error', '$error');
    return false;
  };
  final priorDebugPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) Diagnostics.instance.add('app', message);
    priorDebugPrint(message, wrapWidth: wrapWidth);
  };

  // The OS title bar is suppressed natively (empty CSD titlebar in the Linux
  // runner). window_manager handles show/min-size + the custom window buttons.
  // On Windows/macOS, hide the title bar the usual way.
  if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
    await windowManager.ensureInitialized();
    final options = WindowOptions(
      minimumSize: const Size(900, 620),
      backgroundColor: Colors.transparent,
      titleBarStyle:
          Platform.isLinux ? TitleBarStyle.normal : TitleBarStyle.hidden,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    // Intercept every close (the custom titlebar button, the compositor, Alt+F4)
    // so mpv players are torn down before the engine shuts down. Without this,
    // closing mid-playback races libmpv's callback teardown and aborts. The
    // FathomApp window listener does the disposal, then destroy()s the window.
    await windowManager.setPreventClose(true);
  }

  // Give AppImage runs a proper launcher entry + icons so the desktop (notably
  // Wayland, which ignores the window's own icon) shows Fathom's icon in the
  // taskbar. Fire-and-forget; no-ops off Linux or outside an AppImage.
  unawaited(integrateAppImageDesktopEntry());

  // The automatic interface size, read before the first frame so the window
  // opens at the right size instead of jumping to it (Linux; 1.0 elsewhere).
  AutoInterfaceScale.initial = await queryAutoInterfaceScale();

  // A generous in-memory image cache so posters/backdrops stay decoded when you
  // revisit a screen instead of re-downloading (the default 100 MB evicts fast
  // with large backdrops).
  PaintingBinding.instance.imageCache.maximumSizeBytes = 512 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 3000;

  // System notifications (download complete, request available). Best-effort.
  await AppNotifications.init();

  // Clear the leftover update APK from a previous in-app update so it doesn't
  // sit in storage. Fire-and-forget — never blocks launch.
  unawaited(cleanUpdateArtifacts());

  const storage = ResilientSecureStorage();
  final deviceId = await _getOrCreateDeviceId(storage);

  // Mobile-only: bring up the OS media session for background music + a
  // lock-screen/notification transport. Guarded so a failure here (or an
  // unsupported platform) never blocks app launch — the app just runs without
  // the media notification.
  FathomAudioHandler? audioHandler;
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    try {
      audioHandler = await AudioService.init(
        builder: () => FathomAudioHandler(),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'app.fathom.player.audio',
          androidNotificationChannelName: 'Playback',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
          // The status/notification small icon (upper-left): the Fathom mark as
          // a white silhouette (res/drawable-*/ic_stat_fathom.png). Without this
          // it falls back to a blank launcher-derived square.
          androidNotificationIcon: 'drawable/ic_stat_fathom',
          // Android Auto: opt into content styling so browse folders/items can
          // ask to render as lists or grids (see AudioController's browse tree),
          // and declare search support on the browsable root — THIS is what makes
          // the car draw the search button. ACTION_PLAY_FROM_SEARCH alone only
          // enables voice; the browser-root SEARCH_SUPPORTED extra renders the UI.
          androidBrowsableRootExtras: {
            AndroidContentStyle.supportedKey: true,
            // Category style so the top-level tabs render with their icons.
            AndroidContentStyle.browsableHintKey:
                AndroidContentStyle.categoryListItemHintValue,
            AndroidContentStyle.playableHintKey:
                AndroidContentStyle.listItemHintValue,
            'android.media.browse.SEARCH_SUPPORTED': true,
          },
        ),
      );
    } catch (_) {
      audioHandler = null;
    }
  }

  runApp(
    ProviderScope(
      retry: fathomRetry,
      overrides: [
        deviceIdProvider.overrideWithValue(deviceId),
        audioHandlerProvider.overrideWithValue(audioHandler),
      ],
      child: const FathomApp(),
    ),
  );
}

Future<String> _getOrCreateDeviceId(ResilientSecureStorage storage) async {
  const key = 'fathom_device_id';
  var id = await storage.read(key: key);
  if (id == null || id.isEmpty) {
    id = const Uuid().v4();
    await storage.write(key: key, value: id);
  }
  return id;
}
