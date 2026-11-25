import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import '../state/arr_event_watcher.dart';
import '../state/retry.dart';
import '../state/notifications_controller.dart';
import '../state/preferences.dart';
import '../state/providers.dart';
import 'notifications.dart';

// Manage's notifications while Fathom is closed, on Android: WorkManager
// runs the same look the app takes (history since the last look, health)
// every so often, at most every 15 minutes, with a network, and posts what
// it finds as system notifications. No server of ours in between.

/// The task's name, and the one periodic work it's registered under.
const arrBackgroundTask = 'fathom.manage.events';
const arrBackgroundWork = 'fathom-manage-events';

/// Android's shortest interval for periodic work.
const arrBackgroundShortest = Duration(minutes: 15);

/// Where WorkManager starts each run: a fresh isolate, no app.
@pragma('vm:entry-point')
void arrBackgroundDispatcher() {
  Workmanager().executeTask((task, input) async {
    if (task != arrBackgroundTask) return true;
    WidgetsFlutterBinding.ensureInitialized();
    await AppNotifications.init();
    final c = ProviderContainer(retry: fathomRetry);
    try {
      await arrBackgroundCheck(c);
    } catch (_) {
      // Nothing reached: the next run tries again.
    } finally {
      c.dispose();
    }
    return true;
  });
}

/// One look from the background, with [c] as the app's settings and
/// storage. Nothing when checking is off, or when Fathom itself looked a
/// moment ago (it's open, or was just now). Returns whether it looked.
Future<bool> arrBackgroundCheck(
  ProviderContainer c, {
  DateTime? now,
  ArrEventWatcher Function(Ref ref)? makeWatcher,
}) async {
  final prefs = await c.read(preferencesProvider.future);
  if (prefs.arrPollMinutes <= 0) return false;
  final at = DateTime.now();
  final live = DateTime.tryParse(
    await c.read(secureStorageProvider).read(key: ArrEventWatcher.liveKey) ??
        '',
  );
  if (live != null && (now ?? at).difference(live) < const Duration(minutes: 5)) {
    return false;
  }
  // The bell as it is, so what's told joins it.
  await c.read(notificationsProvider.future);
  final watcher = Provider<ArrEventWatcher>(
    (ref) =>
        makeWatcher?.call(ref) ??
        ArrEventWatcher(
          ref,
          arrBackgroundShortest,
          start: false,
          background: true,
        ),
  );
  await c.read(watcher).poll();
  return true;
}

/// Registers or cancels the background check as the settings change: an
/// app to watch, and checking on. The shell keeps it alive.
final arrBackgroundScheduleProvider = Provider<void>((ref) {
  final p = ref.watch(
    preferencesProvider.select((p) {
      final v = p.asData?.value;
      if (v == null) return null;
      final watching =
          v.sonarrUrl.isNotEmpty ||
          v.radarrUrl.isNotEmpty ||
          v.lidarrUrl.isNotEmpty ||
          v.arrServers.isNotEmpty;
      return (watching, v.arrPollMinutes);
    }),
  );
  if (p == null) return;
  ArrBackgroundSchedule.apply(wanted: p.$1, minutes: p.$2);
});

/// Keeps the background check registered while it's wanted (on Android,
/// with an app to watch and checking on), at the chosen interval or
/// Android's shortest; cancels it otherwise.
class ArrBackgroundSchedule {
  static bool _initialized = false;

  static bool get supported => !kIsWeb && Platform.isAndroid;

  static Future<void> apply({required bool wanted, required int minutes}) async {
    if (!supported) return;
    try {
      if (!_initialized) {
        await Workmanager().initialize(arrBackgroundDispatcher);
        _initialized = true;
      }
      if (!wanted || minutes <= 0) {
        await Workmanager().cancelByUniqueName(arrBackgroundWork);
        return;
      }
      final every = Duration(minutes: minutes) < arrBackgroundShortest
          ? arrBackgroundShortest
          : Duration(minutes: minutes);
      await Workmanager().registerPeriodicTask(
        arrBackgroundWork,
        arrBackgroundTask,
        frequency: every,
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );
    } catch (_) {
      // Best-effort: Fathom still tells what it sees while it runs.
    }
  }
}
