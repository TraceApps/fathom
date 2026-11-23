import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/arr_client.dart';
import '../l10n/l10n.dart';
import '../models/app_notification.dart';
import '../models/arr.dart';
import 'arr_providers.dart';
import 'arr_servers.dart';
import 'notifications_controller.dart';
import 'preferences.dart';
import 'providers.dart';

// Notifications from Sonarr, Radarr and Lidarr without a server of our own
// in between: Fathom asks each app what it did (its history since the last
// look) and what's wrong (its health), while it runs. Often while it shows,
// every few minutes while it's out of sight. What it last saw is kept by
// server address, so a restart catches up and another server starts afresh.

/// What a history entry is, for a notification.
enum ArrEventKind { imported, failed, grabbed }

ArrEventKind? arrEventKind(String? eventType) => switch (eventType) {
  // Lidarr says downloadImported once for an album (its tracks each say
  // trackFileImported: too many to tell one by one).
  'downloadFolderImported' || 'downloadImported' => ArrEventKind.imported,
  'downloadFailed' || 'albumImportIncomplete' => ArrEventKind.failed,
  'grabbed' => ArrEventKind.grabbed,
  _ => null,
};

/// Notifications for what happened, one per title and kind: a season's
/// worth of episodes imported at once is one "Downloaded".
typedef ArrEventNotice = ({
  ArrEventKind kind,
  String title,
  String body,
  String route,
});

List<ArrEventNotice> arrEventNotices(
  ArrKind app,
  List<Map<String, dynamic>> history,
) {
  final groups = <(ArrEventKind, int), List<Map<String, dynamic>>>{};
  for (final h in history) {
    final kind = arrEventKind(h['eventType'] as String?);
    if (kind == null) continue;
    final titleId =
        (switch (app) {
                  ArrKind.sonarr => h['seriesId'],
                  ArrKind.radarr => h['movieId'],
                  ArrKind.lidarr => h['artistId'],
                }
                as num?)
            ?.toInt() ??
        0;
    groups.putIfAbsent((kind, titleId), () => []).add(h);
  }
  return [
    for (final MapEntry(key: (kind, titleId), value: items) in groups.entries)
      _notice(app, kind, titleId, items),
  ];
}

ArrEventNotice _notice(
  ArrKind app,
  ArrEventKind kind,
  int titleId,
  List<Map<String, dynamic>> items,
) {
  final first = items.first;
  Map<String, dynamic> part(String k) => first[k] is Map
      ? Map<String, dynamic>.from(first[k] as Map)
      : const <String, dynamic>{};
  final quality = (part('quality')['quality'] as Map?)?['name'] as String?;
  final source = first['sourceTitle'] as String? ?? '';
  // Lidarr's albums of one artist, Sonarr's episodes of one show.
  final what = switch (app) {
    ArrKind.sonarr => () {
      final show = part('series')['title'] as String? ?? source;
      if (items.length > 1) return tr.arrNotifEpisodes(show, items.length);
      final e = part('episode');
      final s = (e['seasonNumber'] as num?)?.toInt();
      final n = (e['episodeNumber'] as num?)?.toInt();
      return s == null || n == null
          ? show
          : '$show S${'$s'.padLeft(2, '0')}E${'$n'.padLeft(2, '0')}';
    }(),
    ArrKind.radarr => () {
      final m = part('movie');
      final title = m['title'] as String? ?? source;
      final year = (m['year'] as num?)?.toInt();
      return year == null || year == 0 ? title : '$title ($year)';
    }(),
    ArrKind.lidarr => () {
      final artist = part('artist')['artistName'] as String?;
      final albums = {
        for (final i in items)
          if (i['album'] is Map) (i['album'] as Map)['title'] as String?,
      }.whereType<String>().toList();
      final album = albums.length == 1 ? albums.single : null;
      return [?artist, ?album].join(': ').ifEmpty(source);
    }(),
  };
  // The reason from whichever has one (Lidarr's partly imported album has
  // none; its failed download beside it does).
  final message = items
      .map((i) => ((i['data'] as Map?)?['message'] as String?)?.trim())
      .firstWhere((m) => m != null && m.isNotEmpty, orElse: () => null);
  final route = switch (app) {
    ArrKind.sonarr => '/arr/series/$titleId',
    ArrKind.radarr => '/arr/movie/$titleId',
    ArrKind.lidarr => '/arr/artist/$titleId',
  };
  return switch (kind) {
    ArrEventKind.imported => (
      kind: kind,
      title: tr.arrNotifDownloaded,
      body: [what, if (items.length == 1) ?quality].join(' · '),
      route: route,
    ),
    ArrEventKind.failed => (
      kind: kind,
      title: tr.arrNotifFailed,
      body: message == null || message.isEmpty ? what : '$what: $message',
      route: route,
    ),
    ArrEventKind.grabbed => (
      kind: kind,
      title: tr.arrNotifGrabbed,
      body: [what, if (items.length == 1) ?quality].join(' · '),
      route: route,
    ),
  };
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// A health problem, as told apart from the others: the check that found
/// it and how bad. Not its text, which can list what's affected and change
/// as that does ("Indexers unavailable: A, B").
String arrHealthKey(ArrHealth h) => '${h.source}|${h.type}';

/// What the watcher last saw of one server.
class _Seen {
  int lastId;
  DateTime at;
  Set<String> health;
  _Seen(this.lastId, this.at, this.health);

  Map<String, dynamic> toJson() => {
    'lastId': lastId,
    'at': at.toUtc().toIso8601String(),
    'health': health.toList(),
  };

  static _Seen? fromJson(Object? j) {
    if (j is! Map) return null;
    return _Seen(
      (j['lastId'] as num?)?.toInt() ?? 0,
      DateTime.tryParse('${j['at']}') ?? DateTime.now(),
      {for (final h in (j['health'] as List?) ?? const []) '$h'},
    );
  }
}

/// Watches the connected apps and notifies (in the bell, and as a system
/// notification where Fathom posts those) what they did.
class ArrEventWatcher with WidgetsBindingObserver {
  ArrEventWatcher(
    this.ref,
    this._interval, {
    bool start = true,
    this.makeClient,
    this.background = false,
  }) {
    if (start) _start();
  }

  final Ref ref;
  final Duration _interval;

  /// Makes the client for a saved server not in use (tests give their own).
  final ArrClient Function(ArrKind, ArrServer)? makeClient;

  /// Running while Fathom is closed (Android's WorkManager): each is a real
  /// system notification, there being no app to show it in.
  final bool background;

  /// When Fathom itself last looked, kept for the background check: it
  /// leaves alone what Fathom has just seen to.
  static const liveKey = 'fathom_arr_events_live';

  /// While Fathom shows: soon enough to hear of a download as it lands.
  static const _liveInterval = Duration(seconds: 60);
  static const storageKey = 'fathom_arr_events_v1';

  Timer? _timer;
  bool _polling = false;
  bool _disposed = false;
  Map<String, _Seen> _seen = {};
  bool _loaded = false;

  Future<void> _start() async {
    WidgetsBinding.instance.addObserver(this);
    // The first look of the session: into the bell, without a burst of
    // system pop-ups after a long time away.
    await poll(firstRun: true);
    // Disposed meanwhile (new settings, another server): no timer for it.
    if (_disposed) return;
    _restart(_activeInterval());
  }

  Duration _activeInterval() {
    final resumed =
        (WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed) ==
        AppLifecycleState.resumed;
    return resumed && _liveInterval < _interval ? _liveInterval : _interval;
  }

  void _restart(Duration d) {
    _timer?.cancel();
    if (_disposed) return;
    _timer = Timer.periodic(d, (_) => poll());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // The background check may have looked and told meanwhile: what it
      // saw and what it put in the bell are read again first.
      _loaded = false;
      ref.invalidate(notificationsProvider);
      ref.read(notificationsProvider.future).whenComplete(poll);
      _restart(_activeInterval());
    } else {
      _restart(_interval);
    }
  }

  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await ref.read(secureStorageProvider).read(key: storageKey);
      if (raw == null) return;
      final m = jsonDecode(raw);
      if (m is! Map) return;
      _seen = {
        for (final e in m.entries)
          '${e.key}': ?_Seen.fromJson(e.value),
      };
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      await ref
          .read(secureStorageProvider)
          .write(
            key: storageKey,
            value: jsonEncode(_seen.map((k, v) => MapEntry(k, v.toJson()))),
          );
    } catch (_) {}
  }

  /// Asks each connected app once. Public for tests.
  Future<void> poll({bool firstRun = false}) async {
    if (_polling || _disposed) return;
    _polling = true;
    try {
      await _load();
      if (!background) {
        try {
          await ref
              .read(secureStorageProvider)
              .write(
                key: liveKey,
                value: DateTime.now().toUtc().toIso8601String(),
              );
        } catch (_) {}
      }
      final prefs = ref.read(preferencesProvider).asData?.value ?? const Prefs();
      for (final app in ArrKind.values) {
        final inUse = switch (app) {
          ArrKind.sonarr => ref.read(sonarrClientProvider),
          ArrKind.radarr => ref.read(radarrClientProvider),
          ArrKind.lidarr => ref.read(lidarrClientProvider),
        };
        // Every server of the app, the one in use first: a 4K Radarr's
        // downloads are told too. Each by name once there's more than one.
        final servers = arrServersOf(prefs, app);
        String? label(ArrServer s) => servers.length < 2
            ? null
            : (s.name.trim().isEmpty ? tr.arrServerMain : s.name.trim());
        final active = servers.where((s) => s.active).firstOrNull;
        final looks = <(ArrClient, String?, bool)>[
          if (inUse != null)
            (inUse, active == null ? null : label(active), true),
          for (final s in servers)
            if (!s.active && s.ready && s.url != inUse?.baseUrl)
              (_clientFor(app, s), label(s), false),
        ];
        for (final (client, name, isInUse) in looks) {
          if (_disposed) return;
          try {
            await _pollOne(
              app,
              client,
              prefs,
              firstRun: firstRun,
              server: name,
              inUse: isInUse,
            );
          } catch (_) {
            // That server didn't answer: the next look catches up.
          }
        }
      }
    } catch (_) {
      // Torn down mid-look: the next watcher carries on from what was saved.
    } finally {
      _polling = false;
    }
  }

  /// A client for a saved server that isn't in use, kept while its address
  /// and key stay the same.
  final Map<String, ArrClient> _clients = {};
  ArrClient _clientFor(ArrKind app, ArrServer s) => _clients.putIfAbsent(
    '${s.url}|${s.apiKey}',
    () =>
        makeClient?.call(app, s) ??
        switch (app) {
      ArrKind.sonarr => SonarrClient(s.url, s.apiKey),
      ArrKind.radarr => RadarrClient(s.url, s.apiKey),
      ArrKind.lidarr => LidarrClient(s.url, s.apiKey),
    },
  );

  /// [server]: the server's name, once the app has more than one. A title
  /// opens only from the server in use ([inUse]): another's numbers mean
  /// other titles there.
  Future<void> _pollOne(
    ArrKind app,
    ArrClient client,
    Prefs prefs, {
    required bool firstRun,
    String? server,
    bool inUse = true,
  }) async {
    String named(String title) => server == null ? title : '$title · $server';
    final url = client.baseUrl;
    final seen = _seen[url];
    if (seen == null) {
      // A server not seen before: what's there already is where it starts,
      // in silence.
      final recent = await client.historySince(
        DateTime.now().subtract(const Duration(days: 1)),
      );
      final health = await client.health();
      _seen[url] = _Seen(
        recent.fold<int>(0, (m, h) => _max(m, h['id'])),
        _newest(recent) ?? DateTime.now(),
        {for (final h in health) arrHealthKey(h)},
      );
      await _save();
      return;
    }
    // From the newest entry seen, by the server's own clock (this device's
    // may be off), less an hour: an entry dated a moment before it but
    // written after it isn't missed. The id says which are new.
    final history = await client.historySince(
      seen.at.subtract(const Duration(hours: 1)),
    );
    final top = history.fold<int>(0, (m, h) => _max(m, h['id']));
    if (history.isNotEmpty && top < seen.lastId) {
      // Numbered afresh (its database restored or started over): start
      // again from here, in silence, rather than wait to pass the old count.
      seen.lastId = top;
      seen.at = _newest(history) ?? seen.at;
      await _save();
      return;
    }
    final fresh = [
      for (final h in history)
        if (((h['id'] as num?)?.toInt() ?? 0) > seen.lastId) h,
    ]..sort((a, b) => _id(a).compareTo(_id(b)));
    final health = await client.health();
    final newHealth = [
      for (final h in health)
        if (!seen.health.contains(arrHealthKey(h))) h,
    ];
    // Seen (and kept) before told: a notification that can't be shown
    // isn't tried again and again, and a watcher taking over meanwhile
    // doesn't tell it twice.
    if (fresh.isNotEmpty) {
      seen.lastId = _id(fresh.last);
      seen.at = _newest(fresh) ?? seen.at;
    }
    // A problem that clears and comes back is told again.
    seen.health = {for (final h in health) arrHealthKey(h)};
    await _save();

    var notices = arrEventNotices(app, fresh);
    // Back after a long time: the newest few, and how many more.
    const most = 10;
    final more = notices.length - most;
    if (more > 0) notices = notices.sublist(more);
    if (more > 0) {
      await _tell(
        kind: AppNotifKind.info,
        title: named(app.appName),
        body: tr.arrNotifMore(more),
        enabled:
            prefs.notifArrImported ||
            prefs.notifArrFailed ||
            prefs.notifArrGrabbed,
        toast: false,
        route: '/arr',
      );
    }

    for (final n in notices) {
      final enabled = switch (n.kind) {
        ArrEventKind.imported => prefs.notifArrImported,
        ArrEventKind.failed => prefs.notifArrFailed,
        ArrEventKind.grabbed => prefs.notifArrGrabbed,
      };
      await _tell(
        kind: switch (n.kind) {
          ArrEventKind.imported => AppNotifKind.arrImported,
          ArrEventKind.failed => AppNotifKind.arrFailed,
          ArrEventKind.grabbed => AppNotifKind.arrGrabbed,
        },
        title: named(n.title),
        body: n.body,
        enabled: enabled,
        toast: !firstRun,
        route: inUse ? n.route : '/arr',
      );
    }
    for (final h in newHealth) {
      await _tell(
        kind: AppNotifKind.arrHealth,
        title: tr.arrNotifHealth(
          server == null ? app.appName : '${app.appName} $server',
        ),
        body: h.message,
        enabled: prefs.notifArrHealth,
        toast: !firstRun,
        route: inUse ? '/arr/health' : '/arr',
      );
    }
  }

  /// One notification; one that fails doesn't keep the rest from being told.
  Future<void> _tell({
    required AppNotifKind kind,
    required String title,
    required String body,
    required bool enabled,
    required bool toast,
    required String route,
  }) async {
    try {
      await pushAppNotification(
        ref,
        kind: kind,
        title: title,
        body: body,
        enabled: enabled,
        desktopToast: toast,
        osNotify: background,
        route: route,
      );
    } catch (_) {}
  }

  static int _id(Map<String, dynamic> h) => (h['id'] as num?)?.toInt() ?? 0;

  /// The newest date among [history], as the server wrote it.
  static DateTime? _newest(List<Map<String, dynamic>> history) {
    DateTime? newest;
    for (final h in history) {
      final d = DateTime.tryParse('${h['date']}');
      if (d != null && (newest == null || d.isAfter(newest))) newest = d;
    }
    return newest;
  }
  static int _max(int m, Object? id) {
    final v = id is num ? id.toInt() : 0;
    return v > m ? v : m;
  }
}

/// Live while an app is connected in Manage and checking is on; the shell
/// keeps it alive. Rebuilds when the interval changes.
final arrEventWatcherProvider = Provider<ArrEventWatcher?>((ref) {
  final configured =
      ref.watch(sonarrClientProvider) != null ||
      ref.watch(radarrClientProvider) != null ||
      ref.watch(lidarrClientProvider) != null ||
      // Servers saved but none in use: still watched.
      ref.watch(
        preferencesProvider.select(
          (p) => p.asData?.value.arrServers.isNotEmpty ?? false,
        ),
      );
  final minutes = ref.watch(
    preferencesProvider.select((p) => p.asData?.value.arrPollMinutes ?? 5),
  );
  if (!configured || minutes <= 0) return null;
  final w = ArrEventWatcher(ref, Duration(minutes: minutes));
  ref.onDispose(w.dispose);
  return w;
});
