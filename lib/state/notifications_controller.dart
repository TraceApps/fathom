import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_notification.dart';
import '../services/notifications.dart';
import '../widgets/app_snack.dart';
import 'preferences.dart';
import 'providers.dart';

/// The in-app notification centre: a persisted list of [AppNotif], newest first.
/// The bell in the sidebar reads its unread count; the notifications screen reads
/// the list. System (desktop) toasts are fired separately by [pushAppNotification].
class NotificationsController extends AsyncNotifier<List<AppNotif>> {
  static const _key = 'fathom_notifications';
  static const _max = 100;

  @override
  Future<List<AppNotif>> build() async {
    final raw = await ref.read(secureStorageProvider).read(key: _key);
    if (raw == null) return const [];
    try {
      return [
        for (final e in (jsonDecode(raw) as List).whereType<Map>())
          AppNotif.fromJson(e.cast<String, dynamic>()),
      ]
          // Request notifications from before deep-linking stored the generic
          // '/discover' route; drop those dead links so the re-baselined,
          // title-linked ones stand in their place.
          .where((n) => n.route != '/discover')
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _persist(List<AppNotif> list) async {
    await ref.read(secureStorageProvider).write(
        key: _key, value: jsonEncode([for (final n in list) n.toJson()]));
    state = AsyncData(list);
  }

  Future<void> add(AppNotif n) async {
    // Still loading (just started, or reading again after the background
    // check told some): wait for it, or what's stored would be replaced by
    // this one alone.
    final current = await future;
    final list = <AppNotif>[n, ...current];
    if (list.length > _max) list.removeRange(_max, list.length);
    await _persist(list);
  }

  Future<void> markAllRead() async {
    final cur = state.asData?.value ?? const <AppNotif>[];
    if (cur.every((n) => n.read)) return;
    await _persist([for (final n in cur) n.copyWith(read: true)]);
  }

  Future<void> remove(String id) async => _persist([
        for (final n in (state.asData?.value ?? const <AppNotif>[]))
          if (n.id != id) n
      ]);

  Future<void> clear() async => _persist(const <AppNotif>[]);
}

final notificationsProvider =
    AsyncNotifierProvider<NotificationsController, List<AppNotif>>(
        NotificationsController.new);

/// Unread badge count for the sidebar bell.
final unreadNotifCountProvider = Provider<int>((ref) {
  final list =
      ref.watch(notificationsProvider).asData?.value ?? const <AppNotif>[];
  return list.where((n) => !n.read).length;
});

/// Records an in-app notification and, when [desktopToast] is set and the user
/// hasn't turned desktop popups off, fires an OS toast too. [enabled] gates the
/// whole thing on the relevant per-event setting; a monotonic microsecond id
/// keeps entries unique.
Future<void> pushAppNotification(
  Ref ref, {
  required AppNotifKind kind,
  required String title,
  required String body,
  required bool enabled,
  bool desktopToast = true,
  bool osNotifyMobile = false,
  // Post a real system notification on every supported platform (Linux +
  // Android), regardless of focus, and skip the in-app toast. Updates use this
  // so a new build is a proper native notification, not a fleeting snackbar.
  bool osNotify = false,
  String? route,
  Object? routeExtra,
}) async {
  if (!enabled) return;
  await ref.read(notificationsProvider.notifier).add(AppNotif(
        id: 'n${DateTime.now().microsecondsSinceEpoch}',
        kind: kind,
        title: title,
        body: body,
        time: DateTime.now(),
        route: route,
        routeExtra: routeExtra,
      ));
  if (osNotify) {
    await AppNotifications.show(title, body);
    return;
  }
  // Opt-in per event: post a real system notification on mobile too (updates
  // use this), so it stays in the tray and is visible outside the app, rather
  // than only living in the in-app bell. Desktop's OS toast is handled below.
  if (osNotifyMobile && (Platform.isAndroid || Platform.isIOS)) {
    await AppNotifications.show(title, body);
  }
  if (!desktopToast) return;
  // While Fathom is focused, surface the same in-app snackbar as every other
  // action so notifications look consistent in-app; when it's backgrounded,
  // fall back to a system notification so it still reaches the user.
  final state = WidgetsBinding.instance.lifecycleState;
  final focused =
      (state ?? AppLifecycleState.resumed) == AppLifecycleState.resumed;
  if (focused) {
    showGlobalSnack(body.isEmpty ? title : '$title: $body',
        kind: _snackKindFor(kind));
    return;
  }
  // System (OS) notifications are desktop-only: Android's background delivery
  // proved too unreliable/laggy to be worth it, so on mobile a backgrounded
  // event just waits in the in-app bell. The per-event toggles above still
  // decide whether it's recorded at all.
  if (Platform.isAndroid || Platform.isIOS) return;
  final popups =
      ref.read(preferencesProvider).asData?.value.desktopNotifications ?? true;
  if (popups) await AppNotifications.show(title, body);
}

SnackKind _snackKindFor(AppNotifKind kind) => switch (kind) {
      AppNotifKind.seerrDeclined || AppNotifKind.arrFailed => SnackKind.error,
      AppNotifKind.seerrApproved ||
      AppNotifKind.seerrAvailable ||
      AppNotifKind.downloadComplete ||
      AppNotifKind.arrImported =>
        SnackKind.success,
      _ => SnackKind.info,
    };
