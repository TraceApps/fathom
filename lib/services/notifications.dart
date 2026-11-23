import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Thin wrapper over flutter_local_notifications for system notifications
/// (download complete, a Seerr request becoming available). Best-effort: if the
/// platform can't initialize, every call is a silent no-op. Linux + Android are
/// wired now; Windows is added when that target lands.
class AppNotifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  // Started from the clock, not a fixed number: a background run is a new
  // process each time, and a notification with an id already showing
  // replaces it.
  static int _id = DateTime.now().millisecondsSinceEpoch % 1000000000;

  static Future<void> init() async {
    // On Linux, the plugin subscribes to a D-Bus signal stream as part of
    // initialize(); when there's no session bus reachable at all (Steam Big
    // Picture / gamescope, some minimal window managers — the same class of
    // environment as issue #32), that subscription throws from inside a
    // broadcast stream controller's listen callback, which escapes a normal
    // try/catch around the await entirely. runZonedGuarded is the only way to
    // catch that and keep notification init the best-effort it's meant to be.
    final completer = Completer<void>();
    runZonedGuarded(() async {
      try {
        const settings = InitializationSettings(
          linux: LinuxInitializationSettings(defaultActionName: 'Open'),
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        );
        await _plugin.initialize(settings: settings);
        _ready = true;
      } catch (_) {
        _ready = false;
      } finally {
        if (!completer.isCompleted) completer.complete();
      }
    }, (error, stack) {
      _ready = false;
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }

  /// Ask for the Android 13+ runtime notification permission. Without it, every
  /// notification the app posts — including the media-playback foreground service
  /// notification — is silently suppressed. Best-effort; needs a resumed
  /// Activity, so call it after the first frame, not during startup.
  static Future<void> requestPermission() async {
    if (!_ready) return;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
    } catch (_) {}
  }

  static Future<void> show(String title, String body) async {
    if (!_ready) return;
    try {
      const details = NotificationDetails(
        linux: LinuxNotificationDetails(),
        android: AndroidNotificationDetails(
          'fathom_general',
          'Fathom',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      );
      await _plugin.show(
        id: _id++,
        title: title,
        body: body,
        notificationDetails: details,
      );
    } catch (_) {}
  }
}
