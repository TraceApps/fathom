import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fathom/api/arr_client.dart';
import 'package:fathom/models/app_notification.dart';
import 'package:fathom/models/arr.dart';
import 'package:fathom/services/resilient_secure_storage.dart';
import 'package:fathom/state/arr_event_watcher.dart';
import 'package:fathom/state/arr_providers.dart';
import 'package:fathom/state/arr_servers.dart';
import 'package:fathom/state/notifications_controller.dart';
import 'package:fathom/state/preferences.dart';
import 'package:fathom/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Notifications from Sonarr, Radarr and Lidarr without a relay: Fathom reads
// each app's history since its last look, and its health. The answers are
// the apps' own (history/since with its includes), saved from the rig.

List<Map<String, dynamic>> _since(String app) => [
  for (final m
      in jsonDecode(
            File('test/fixtures/arr/${app}_history_since.json').readAsStringSync(),
          )
          as List)
    Map<String, dynamic>.from(m as Map),
];

Map<String, dynamic> _of(String app, String eventType) =>
    _since(app).firstWhere((h) => h['eventType'] == eventType);

class _Storage implements ResilientSecureStorage {
  final Map<String, String> store = {};
  @override
  Future<String?> read({required String key}) async => store[key];
  @override
  Future<void> write({required String key, required String value}) async =>
      store[key] = value;
  @override
  Future<void> delete({required String key}) async => store.remove(key);
}

class _FakePrefs extends PreferencesController {
  _FakePrefs(this.initial);
  final Prefs initial;
  @override
  Future<Prefs> build() async => initial;
  @override
  Future<void> edit(Prefs Function(Prefs) change) async {
    state = AsyncData(change(state.asData?.value ?? initial));
  }
}

/// A Radarr whose history and health the test writes.
class _Radarr implements HttpClientAdapter {
  List<Map<String, dynamic>> history = [];
  List<Map<String, dynamic>> health = [];
  final List<Map<String, List<String>>> asked = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    final path = o.uri.path.replaceFirst(RegExp(r'^.*/api/v3/'), '');
    if (path == 'history/since') asked.add(o.uri.queryParametersAll);
    final data = switch (path) {
      'history/since' => history,
      'health' => health,
      _ => const <Object>[],
    };
    return ResponseBody.fromString(
      jsonEncode(data),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// A bell that can't take the first notification it's given.
class _FlakyBell extends NotificationsController {
  int calls = 0;
  @override
  Future<void> add(AppNotif n) async {
    if (calls++ == 0) throw StateError('storage full');
    return super.add(n);
  }
}

Map<String, dynamic> _withId(Map<String, dynamic> h, int id) => {
  ...h,
  'id': id,
};

void main() {
  // The snackbar shown while Fathom is in front needs the binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('what a notification says', () {
    test('Sonarr: the show and episode, and the quality', () {
      final h = _of('sonarr', 'downloadFolderImported');
      final n = arrEventNotices(ArrKind.sonarr, [h]).single;
      final e = h['episode'] as Map;
      final code =
          'S${'${e['seasonNumber']}'.padLeft(2, '0')}'
          'E${'${e['episodeNumber']}'.padLeft(2, '0')}';
      expect(n.kind, ArrEventKind.imported);
      expect(n.title, 'Downloaded');
      expect(
        n.body,
        '${(h['series'] as Map)['title']} $code · '
        '${((h['quality'] as Map)['quality'] as Map)['name']}',
      );
      expect(n.route, '/arr/series/${h['seriesId']}');
    });

    test('a season at once is one notification', () {
      final h = _of('sonarr', 'downloadFolderImported');
      final ns = arrEventNotices(ArrKind.sonarr, [
        _withId(h, 1),
        _withId(h, 2),
        _withId(h, 3),
      ]);
      expect(ns, hasLength(1));
      expect(ns.single.body, '${(h['series'] as Map)['title']}: 3 episodes');
    });

    test('Radarr: the movie and year; a failure says why', () {
      final failed = _of('radarr', 'downloadFailed');
      final n = arrEventNotices(ArrKind.radarr, [failed]).single;
      final m = failed['movie'] as Map;
      expect(n.title, 'Download failed');
      expect(
        n.body,
        '${m['title']} (${m['year']}): ${(failed['data'] as Map)['message']}',
      );
      expect(n.route, '/arr/movie/${failed['movieId']}');
      final grab = arrEventNotices(ArrKind.radarr, [
        _of('radarr', 'grabbed'),
      ]).single;
      expect(grab.kind, ArrEventKind.grabbed);
      expect(grab.title, 'Grabbed');
    });

    test('Lidarr: the artist and album; not each track', () {
      final album = _of('lidarr', 'downloadImported');
      final n = arrEventNotices(ArrKind.lidarr, [
        album,
        _of('lidarr', 'trackFileImported'),
        _of('lidarr', 'trackFileRenamed'),
      ]).single;
      expect(
        n.body,
        '${(album['artist'] as Map)['artistName']}: '
        '${(album['album'] as Map)['title']} · '
        '${((album['quality'] as Map)['quality'] as Map)['name']}',
      );
      expect(n.route, '/arr/artist/${album['artistId']}');
      // An album that only partly imported is told as a failure.
      expect(
        arrEventNotices(ArrKind.lidarr, [
          _of('lidarr', 'albumImportIncomplete'),
        ]).single.kind,
        ArrEventKind.failed,
      );
    });

    test('a failure\'s reason from whichever entry has one', () {
      final incomplete = _of('lidarr', 'albumImportIncomplete');
      final failed = {
        ..._of('lidarr', 'downloadFailed'),
        'artistId': incomplete['artistId'],
      };
      final n = arrEventNotices(ArrKind.lidarr, [incomplete, failed]).single;
      expect(n.body, endsWith(': ${(failed['data'] as Map)['message']}'));
    });

    test('deletes, renames and ignores aren\'t told', () {
      for (final t in [
        'episodeFileDeleted',
        'downloadIgnored',
      ]) {
        expect(arrEventNotices(ArrKind.sonarr, [_of('sonarr', t)]), isEmpty);
      }
      expect(
        arrEventNotices(ArrKind.radarr, [_of('radarr', 'movieFileDeleted')]),
        isEmpty,
      );
    });
  });

  group('the watcher', () {
    late _Radarr radarr;
    late _Storage storage;
    late ProviderContainer c;
    late String url;

    ProviderContainer make({Prefs prefs = const Prefs()}) {
      final pc = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          preferencesProvider.overrideWith(() => _FakePrefs(prefs)),
          sonarrClientProvider.overrideWithValue(null),
          lidarrClientProvider.overrideWithValue(null),
          radarrClientProvider.overrideWith(
            (ref) => RadarrClient(
              url,
              'k',
              dio: Dio()..httpClientAdapter = radarr,
            ),
          ),
          arrEventWatcherProvider.overrideWith(
            (ref) => ArrEventWatcher(ref, const Duration(minutes: 5), start: false),
          ),
        ],
      );
      addTearDown(pc.dispose);
      return pc;
    }

    Future<List<AppNotif>> bell() => c.read(notificationsProvider.future);

    setUp(() async {
      radarr = _Radarr();
      storage = _Storage();
      url = 'http://radarr:7878';
      c = make();
      await c.read(preferencesProvider.future);
      // The bell is loaded long before anything rings, as in the app.
      await c.read(notificationsProvider.future);
    });

    test('first look: what\'s there is where it starts, in silence', () async {
      radarr.history = [_withId(_of('radarr', 'downloadFailed'), 10)];
      radarr.health = [
        {'source': 'IndexerCheck', 'type': 'warning', 'message': 'No indexers'},
      ];
      await c.read(arrEventWatcherProvider)!.poll(firstRun: true);
      expect(await bell(), isEmpty);
      // It's remembered across restarts.
      expect(storage.store[ArrEventWatcher.storageKey], contains(url));
    });

    test('then what\'s new, once; asked a little before the last look', () async {
      final w = c.read(arrEventWatcherProvider)!;
      radarr.history = [_withId(_of('radarr', 'grabbed'), 10)];
      await w.poll(firstRun: true);
      radarr.history = [
        _withId(_of('radarr', 'grabbed'), 10),
        _withId(_of('radarr', 'downloadFolderImported'), 11),
        _withId(_of('radarr', 'downloadFailed'), 12),
      ];
      await w.poll();
      final got = await bell();
      expect(
        [for (final n in got) n.kind],
        // Newest first in the bell.
        [AppNotifKind.arrFailed, AppNotifKind.arrImported],
      );
      expect(got.last.route, startsWith('/arr/movie/'));
      // Asked again: nothing twice.
      await w.poll();
      expect(await bell(), hasLength(2));
      // From the newest entry by the server's clock, less an hour: this
      // device's clock can be off.
      final date = DateTime.parse(radarr.asked.last['date']!.single);
      final newest = DateTime.parse(
        _of('radarr', 'downloadFolderImported')['date'] as String,
      );
      expect(date, newest.subtract(const Duration(hours: 1)));
    });

    test('a restart catches up on what happened meanwhile', () async {
      radarr.history = [_withId(_of('radarr', 'grabbed'), 10)];
      await c.read(arrEventWatcherProvider)!.poll(firstRun: true);
      radarr.history.add(_withId(_of('radarr', 'downloadFolderImported'), 11));
      // Fathom again, with what it kept.
      c = make();
      await c.read(preferencesProvider.future);
      await c.read(notificationsProvider.future);
      await c.read(arrEventWatcherProvider)!.poll(firstRun: true);
      expect([for (final n in await bell()) n.kind], [AppNotifKind.arrImported]);
    });

    test('told once across a restart too', () async {
      final w = c.read(arrEventWatcherProvider)!;
      radarr.history = [_withId(_of('radarr', 'grabbed'), 10)];
      await w.poll(firstRun: true);
      radarr.history.add(_withId(_of('radarr', 'downloadFolderImported'), 11));
      await w.poll();
      expect(await bell(), hasLength(1));
      // Fathom again: the bell kept, and nothing told twice.
      c = make();
      await c.read(preferencesProvider.future);
      await c.read(notificationsProvider.future);
      await c.read(arrEventWatcherProvider)!.poll(firstRun: true);
      expect(await bell(), hasLength(1));
    });

    test('each kind follows its switch; grabs are off at first', () async {
      final w = c.read(arrEventWatcherProvider)!;
      await w.poll(firstRun: true);
      radarr.history = [_withId(_of('radarr', 'grabbed'), 20)];
      await w.poll();
      expect(await bell(), isEmpty);
      await c
          .read(preferencesProvider.notifier)
          .edit(
            (p) => p.copyWith(notifArrGrabbed: true, notifArrFailed: false),
          );
      radarr.history = [
        _withId(_of('radarr', 'grabbed'), 21),
        _withId(_of('radarr', 'downloadFailed'), 22),
      ];
      await w.poll();
      expect([for (final n in await bell()) n.kind], [AppNotifKind.arrGrabbed]);
    });

    test('a new health problem, once; again if it comes back', () async {
      final w = c.read(arrEventWatcherProvider)!;
      final problem = {
        'source': 'DownloadClientCheck',
        'type': 'error',
        'message': 'Unable to communicate with qBittorrent',
      };
      await w.poll(firstRun: true);
      radarr.health = [problem];
      await w.poll();
      await w.poll();
      var got = await bell();
      expect(got, hasLength(1));
      expect(got.single.kind, AppNotifKind.arrHealth);
      expect(got.single.title, 'Radarr needs attention');
      expect(got.single.body, problem['message']);
      expect(got.single.route, '/arr/health');
      radarr.health = [];
      await w.poll();
      radarr.health = [problem];
      await w.poll();
      got = await bell();
      expect(got, hasLength(2));
    });

    test('another server starts afresh, in silence', () async {
      final w = c.read(arrEventWatcherProvider)!;
      radarr.history = [_withId(_of('radarr', 'grabbed'), 10)];
      await w.poll(firstRun: true);
      // The 4K Radarr, with its own numbering and its own past.
      url = 'http://radarr4k:7878';
      c.invalidate(radarrClientProvider);
      radarr.history = [_withId(_of('radarr', 'downloadFailed'), 3)];
      await w.poll();
      expect(await bell(), isEmpty);
      radarr.history.add(_withId(_of('radarr', 'downloadFolderImported'), 4));
      await w.poll();
      expect([for (final n in await bell()) n.kind], [AppNotifKind.arrImported]);
    });

    test('one that can\'t be told doesn\'t stop the rest, or repeat', () async {
      final flaky = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          preferencesProvider.overrideWith(() => _FakePrefs(const Prefs())),
          notificationsProvider.overrideWith(_FlakyBell.new),
          sonarrClientProvider.overrideWithValue(null),
          lidarrClientProvider.overrideWithValue(null),
          radarrClientProvider.overrideWith(
            (ref) => RadarrClient(
              url,
              'k',
              dio: Dio()..httpClientAdapter = radarr,
            ),
          ),
          arrEventWatcherProvider.overrideWith(
            (ref) =>
                ArrEventWatcher(ref, const Duration(minutes: 5), start: false),
          ),
        ],
      );
      addTearDown(flaky.dispose);
      await flaky.read(preferencesProvider.future);
      await flaky.read(notificationsProvider.future);
      final w = flaky.read(arrEventWatcherProvider)!;
      await w.poll(firstRun: true);
      radarr.history = [
        _withId(_of('radarr', 'downloadFolderImported'), 11),
        _withId(_of('radarr', 'downloadFailed'), 12),
      ];
      await w.poll();
      await w.poll();
      expect(
        [for (final n in await flaky.read(notificationsProvider.future)) n.kind],
        [AppNotifKind.arrFailed],
      );
    });

    test('numbered afresh (a restored database): starts again, quietly', () async {
      final w = c.read(arrEventWatcherProvider)!;
      radarr.history = [_withId(_of('radarr', 'grabbed'), 500)];
      await w.poll(firstRun: true);
      radarr.history = [
        _withId(_of('radarr', 'grabbed'), 1),
        _withId(_of('radarr', 'downloadFailed'), 2),
      ];
      await w.poll();
      expect(await bell(), isEmpty);
      // Then what's new under the new numbering.
      radarr.history.add(_withId(_of('radarr', 'downloadFolderImported'), 3));
      await w.poll();
      expect([for (final n in await bell()) n.kind], [AppNotifKind.arrImported]);
    });

    test('a long time away: the newest ten, and how many more', () async {
      final w = c.read(arrEventWatcherProvider)!;
      await w.poll(firstRun: true);
      final imported = _of('radarr', 'downloadFolderImported');
      radarr.history = [
        for (var i = 1; i <= 13; i++)
          {
            ..._withId(imported, 100 + i),
            'movieId': i,
            'movie': {'id': i, 'title': 'Movie $i', 'year': 2000 + i},
          },
      ];
      await w.poll();
      final got = await bell();
      expect(got, hasLength(11));
      // Newest first: Movie 13 down to Movie 4, after the count.
      expect(got.first.body, startsWith('Movie 13 (2013)'));
      expect(got.last.kind, AppNotifKind.info);
      expect(got.last.body, '3 more while Fathom was away');
      expect(got.where((n) => n.body.startsWith('Movie 3 ')), isEmpty);
    });

    test('a problem whose wording changes isn\'t told again', () async {
      final w = c.read(arrEventWatcherProvider)!;
      await w.poll(firstRun: true);
      radarr.health = [
        {'source': 'IndexerStatusCheck', 'type': 'warning', 'message': 'Unavailable: A'},
      ];
      await w.poll();
      radarr.health = [
        {'source': 'IndexerStatusCheck', 'type': 'warning', 'message': 'Unavailable: A, B'},
      ];
      await w.poll();
      expect(await bell(), hasLength(1));
      // Worse (a warning become an error) is told.
      radarr.health = [
        {'source': 'IndexerStatusCheck', 'type': 'error', 'message': 'All unavailable'},
      ];
      await w.poll();
      expect(await bell(), hasLength(2));
    });

    test('once disposed, it asks nothing', () async {
      final w = c.read(arrEventWatcherProvider)!;
      w.dispose();
      await w.poll(firstRun: true);
      expect(radarr.asked, isEmpty);
    });

    test('every server of an app is watched, each by name', () async {
      final fourK = _Radarr();
      final pc = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          preferencesProvider.overrideWith(
            () => _FakePrefs(
              arrAddServer(
                const Prefs(radarrUrl: 'http://radarr:7878', radarrApiKey: 'k'),
                ArrKind.radarr,
                name: '4K',
                url: 'http://radarr4k:7878',
                apiKey: 'k4',
              ),
            ),
          ),
          sonarrClientProvider.overrideWithValue(null),
          lidarrClientProvider.overrideWithValue(null),
          radarrClientProvider.overrideWith(
            (ref) => RadarrClient(
              'http://radarr:7878',
              'k',
              dio: Dio()..httpClientAdapter = radarr,
            ),
          ),
          arrEventWatcherProvider.overrideWith(
            (ref) => ArrEventWatcher(
              ref,
              const Duration(minutes: 5),
              start: false,
              makeClient: (kind, s) => RadarrClient(
                s.url,
                s.apiKey,
                dio: Dio()..httpClientAdapter = fourK,
              ),
            ),
          ),
        ],
      );
      addTearDown(pc.dispose);
      await pc.read(preferencesProvider.future);
      await pc.read(notificationsProvider.future);
      final w = pc.read(arrEventWatcherProvider)!;
      await w.poll(firstRun: true);
      radarr.history = [_withId(_of('radarr', 'downloadFolderImported'), 5)];
      fourK.history = [_withId(_of('radarr', 'downloadFailed'), 9)];
      fourK.health = [
        {'source': 'DiskSpaceCheck', 'type': 'warning', 'message': 'Low space'},
      ];
      await w.poll();
      final got = await pc.read(notificationsProvider.future);
      final byTitle = {for (final n in got) n.title: n};
      // The one in use: named, and its title opens.
      expect(byTitle['Downloaded · Main']!.route, startsWith('/arr/movie/'));
      // The 4K one: named; its numbers are another server's, so Manage.
      expect(byTitle['Download failed · 4K']!.route, '/arr');
      expect(byTitle['Radarr 4K needs attention']!.route, '/arr');
      expect(fourK.asked, isNotEmpty);
    });

    test('off (never checks) when the interval is 0, or nothing connected', () {
      final off = ProviderContainer(
        overrides: [
          preferencesProvider.overrideWith(
            () => _FakePrefs(const Prefs(arrPollMinutes: 0)),
          ),
          radarrClientProvider.overrideWithValue(
            RadarrClient('http://r', 'k', dio: Dio()..httpClientAdapter = radarr),
          ),
        ],
      );
      addTearDown(off.dispose);
      off.listen(preferencesProvider, (_, _) {});
      return off.read(preferencesProvider.future).then((_) {
        expect(off.read(arrEventWatcherProvider), isNull);
      });
    });
  });
}
