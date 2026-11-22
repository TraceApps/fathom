import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fathom/api/arr_client.dart';
import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/models/arr.dart';
import 'package:fathom/models/session.dart';
import 'package:fathom/screens/arr_activity_screens.dart';
import 'package:fathom/screens/arr_detail_screens.dart';
import 'package:fathom/screens/arr_releases_screen.dart';
import 'package:fathom/screens/arr_screen.dart';
import 'package:fathom/state/arr_providers.dart';
import 'package:fathom/state/preferences.dart';
import 'package:fathom/state/session_controller.dart';
import 'package:fathom/theme/app_theme.dart';
import 'package:fathom/widgets/arr_home_rows.dart';
import 'package:fathom/widgets/media_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// Lidarr's albums in the Manage section's shared lists (Calendar, Queue,
// History, Blocklist, Wanted, Health) and on Home's rows. The answers are
// Lidarr 3.1.6's own, saved from the rig: a download it couldn't import, a
// release marked failed, and the history around them.

Object? _fixture(String name) =>
    jsonDecode(File('test/fixtures/arr/$name.json').readAsStringSync());

Map<String, dynamic> _map(String name) =>
    Map<String, dynamic>.from(_fixture(name)! as Map);

List<Map<String, dynamic>> _list(String name) => [
  for (final m in _fixture(name)! as List) Map<String, dynamic>.from(m as Map),
];

List<Map<String, dynamic>> _records(String name) => [
  for (final m in _map(name)['records'] as List)
    Map<String, dynamic>.from(m as Map),
];

typedef _Asked = ({
  String method,
  String path,
  Map<String, List<String>> query,
  Object? body,
});

/// A Lidarr answering from what the rig said, keeping what was asked.
class _Lidarr implements HttpClientAdapter {
  final List<_Asked> asked = [];
  final Map<String, Object? Function()> answers;
  _Lidarr([this.answers = const {}]);

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    final path = o.uri.path.replaceFirst(RegExp(r'^.*/api/v1/'), '');
    asked.add((
      method: o.method,
      path: path,
      query: o.uri.queryParametersAll,
      body: o.data,
    ));
    final custom = answers[path];
    final Object? data = custom != null
        ? custom()
        : o.method != 'GET'
        ? const {}
        : switch (path) {
            'queue' => _map('lidarr_queue'),
            'queue/status' => {'totalCount': 1, 'warnings': true},
            'calendar' => const [],
            'wanted/missing' => _map('lidarr_wanted_missing'),
            'wanted/cutoff' => {'totalRecords': 0, 'records': const []},
            'history' => _map('lidarr_recent_history'),
            'blocklist' => _map('lidarr_blocklist'),
            'health' => [
              {
                'source': 'IndexerStatusCheck',
                'type': 'warning',
                'message': 'Indexers unavailable due to failures: Rig',
              },
            ],
            'system/status' => {'appName': 'Lidarr', 'version': '3.1.6.5079'},
            'artist' => _list('lidarr_artists'),
            'release' => _list('lidarr_releases'),
            _ => const [],
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

  List<_Asked> sent(String method, String path) => [
    for (final a in asked)
      if (a.method == method && a.path == path) a,
  ];
}

LidarrClient _client(_Lidarr s) =>
    LidarrClient('http://lidarr:8686', 'k', dio: Dio()..httpClientAdapter = s);

class _FakePrefs extends PreferencesController {
  @override
  Future<Prefs> build() async => const Prefs();

  @override
  Future<void> edit(Prefs Function(Prefs) change) async {
    state = AsyncData(change(state.asData?.value ?? const Prefs()));
  }
}

class _SignedOut extends SessionController {
  @override
  Future<Session?> build() async => null;
}

final _visited = <String>[];

Widget _app(_Lidarr lidarr, {Widget home = const ArrScreen()}) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, _) => home),
      GoRoute(
        path: '/arr',
        builder: (_, s) {
          _visited.add(s.uri.toString());
          return const Scaffold(body: Text('manage'));
        },
      ),
      GoRoute(
        path: '/arr/artist/:id',
        builder: (_, s) {
          _visited.add(s.uri.toString());
          return ArrArtistScreen(id: int.parse(s.pathParameters['id']!));
        },
      ),
      GoRoute(
        path: '/arr/releases',
        builder: (_, s) {
          _visited.add(s.uri.toString());
          return ArrReleasesScreen(
            target: ArrReleaseTarget.fromQuery(s.uri.queryParameters),
          );
        },
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      lidarrClientProvider.overrideWithValue(_client(lidarr)),
      sonarrClientProvider.overrideWithValue(null),
      radarrClientProvider.overrideWithValue(null),
      preferencesProvider.overrideWith(_FakePrefs.new),
      sessionControllerProvider.overrideWith(_SignedOut.new),
    ],
    child: MaterialApp.router(
      theme: AppTheme.dark(const Color(0xFF8AB4F8)),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _open(
  WidgetTester t,
  Widget app, {
  Size size = const Size(1200, 1000),
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(app);
  await _settle(t);
}

Future<void> _tab(WidgetTester t, String name) async {
  await t.tap(find.widgetWithText(Tab, name));
  await _settle(t);
  await t.pump(const Duration(milliseconds: 400));
  await _settle(t);
}

void main() {
  setUp(_visited.clear);

  group('Lidarr\'s lists, read', () {
    test('a download it couldn\'t import: the artist, the album, the state', () {
      final q = ArrQueueItem.fromJson(
        ArrKind.lidarr,
        _records('lidarr_queue').single,
      );
      expect(q.mediaTitle, 'Portishead');
      expect(q.albumTitle, 'Dummy');
      expect(q.titleId, 1);
      expect(q.albumId, 2);
      // Lidarr's own word for usenet.
      expect(_records('lidarr_queue').single['protocol'], 'UsenetDownloadProtocol');
      expect(q.protocol, 'usenet');
      expect(q.state, ArrQueueState.importFailed);
      expect(q.state.needsHelp, isTrue);
      expect(q.canIgnore, isTrue);
      expect(q.images, isNotEmpty);
    });

    test('Lidarr\'s names for a failed download', () {
      ArrQueueState of(String state) => ArrQueueItem.fromJson(ArrKind.lidarr, {
        'id': 1,
        'title': 'x',
        'status': 'completed',
        'trackedDownloadState': state,
      }).state;
      expect(of('downloadFailed'), ArrQueueState.failed);
      expect(of('downloadFailedPending'), ArrQueueState.failed);
      expect(of('importBlocked'), ArrQueueState.importBlocked);
      expect(of('importPending'), ArrQueueState.waitingToImport);
    });

    test('a calendar album: the artist, the album, its day', () {
      final m = _list('lidarr_calendar').first;
      final e = ArrCalendarEntry.fromAlbum(m)!;
      expect(e.kind, ArrKind.lidarr);
      expect(e.title, (m['artist'] as Map)['artistName']);
      expect(e.albumTitle, m['title']);
      final day = DateTime.parse(m['releaseDate'] as String);
      expect(e.date, DateTime(day.year, day.month, day.day));
      expect(e.titleId, m['artistId']);
      expect(e.albumId, m['id']);
    });

    test('the artist\'s pictures, else the album\'s cover as the poster', () {
      final bare = ArrQueueItem.fromJson(
        ArrKind.lidarr,
        _records('lidarr_queue').single,
      );
      // Lidarr's lists send the artist with no pictures.
      expect(bare.images.map((i) => i.coverType), ['poster']);
      expect(bare.images.single.remoteUrl, contains('coverartarchive.org'));
      final own = ArrQueueItem.fromJson(ArrKind.lidarr, {
        ..._records('lidarr_queue').single,
        'artist': {
          'artistName': 'Portishead',
          'images': [
            {'coverType': 'poster', 'url': '/MediaCover/1/poster.jpg'},
          ],
        },
      });
      expect(own.images.single.url, '/MediaCover/1/poster.jpg');
    });

    test('downloaded once every track is there', () {
      final m = {
        ..._list('lidarr_calendar').first,
        'statistics': {'trackFileCount': 11, 'totalTrackCount': 11},
      };
      expect(ArrCalendarEntry.fromAlbum(m)!.hasFile, isTrue);
      final part = {
        ...m,
        'statistics': {'trackFileCount': 3, 'totalTrackCount': 11},
      };
      expect(ArrCalendarEntry.fromAlbum(part)!.hasFile, isFalse);
    });

    test('a wanted album, searched for by its own id', () {
      final w = ArrWantedItem.fromAlbum(_records('lidarr_wanted_missing').first);
      expect(w.title, 'Radiohead');
      expect(w.albumTitle, 'A Moon Shaped Pool');
      expect(w.itemId, w.albumId);
      expect(w.titleId, 2);
      expect(w.available, isTrue);
      final soon = ArrWantedItem.fromAlbum({
        ..._records('lidarr_wanted_missing').first,
        'releaseDate': '2099-01-01T00:00:00Z',
      });
      expect(soon.available, isFalse);
    });

    test('history: the artist, the album and the track', () {
      final items = [
        for (final m in _records('lidarr_recent_history'))
          ArrHistoryItem.fromJson(m, ArrKind.lidarr),
      ];
      final imported = items.firstWhere(
        (h) => h.eventType == 'trackFileImported',
      );
      expect(imported.title, 'Portishead');
      expect(imported.albumTitle, isNotNull);
      expect(imported.trackTitle, isNotNull);
      expect(imported.titleId, 1);
      expect(imported.images, isNotEmpty);
    });

    test('the blocklist: the artist the release was for', () {
      final b = ArrBlocklistItem.fromJson(
        ArrKind.lidarr,
        _records('lidarr_blocklist').single,
      );
      expect(b.title, 'Portishead');
      expect(b.titleId, 1);
      expect(b.protocol, 'usenet');
      expect(b.quality, 'MP3-320');
    });

    test('a release is usenet or torrent, however the app writes it', () {
      final r = ArrSearchResult.fromJson(_list('lidarr_releases').first);
      expect(r.protocol, 'usenet');
      expect(r.isTorrent, isFalse);
      final t = ArrSearchResult.fromJson({
        ..._list('lidarr_releases').first,
        'protocol': 'TorrentDownloadProtocol',
      });
      expect(t.isTorrent, isTrue);
      // Sonarr's and Radarr's words stay as they are.
      expect(ArrSearchResult.fromJson({'protocol': 'torrent'}).isTorrent, isTrue);
    });

    test('History\'s filters, by Lidarr\'s numbers', () {
      List<int> of(ArrHistoryFilter f) => arrHistoryEventTypes(ArrKind.lidarr, f);
      expect(of(ArrHistoryFilter.all), isEmpty);
      expect(of(ArrHistoryFilter.grabbed), [1]);
      expect(of(ArrHistoryFilter.imported), [2, 3]);
      expect(of(ArrHistoryFilter.failed), [4, 7]);
      expect(of(ArrHistoryFilter.deleted), [5]);
      expect(of(ArrHistoryFilter.renamed), [6]);
      expect(of(ArrHistoryFilter.ignored), [10]);
    });
  });

  group('what Lidarr is asked for the lists', () {
    test('the calendar by whole UTC days, what falls outside dropped', () async {
      final s = _Lidarr({
        'calendar': () => [
          {..._list('lidarr_calendar')[0], 'releaseDate': '2026-03-01T00:00:00Z'},
          {..._list('lidarr_calendar')[1], 'releaseDate': '2026-03-10T00:00:00Z'},
          // The end day comes back too: not in the window.
          {..._list('lidarr_calendar')[2], 'releaseDate': '2026-03-29T00:00:00Z'},
        ],
      });
      final got = await _client(s).calendar(
        DateTime(2026, 3, 1),
        DateTime(2026, 3, 29),
        unmonitored: true,
      );
      expect([for (final e in got) e.date.day], [1, 10]);
      expect(s.sent('GET', 'calendar').single.query, {
        'start': ['2026-03-01T00:00:00.000Z'],
        'end': ['2026-03-29T00:00:00.000Z'],
        'unmonitored': ['true'],
        'includeArtist': ['true'],
      });
    });

    test('Wanted with the artist, newest first; search all by Lidarr\'s names', () async {
      final s = _Lidarr();
      final c = _client(s);
      final page = await c.missing(pageSize: 25, monitored: false);
      expect(page.total, 3);
      expect(s.sent('GET', 'wanted/missing').single.query, {
        'page': ['1'],
        'pageSize': ['25'],
        'sortKey': ['releaseDate'],
        'sortDirection': ['descending'],
        'includeArtist': ['true'],
        'monitored': ['false'],
      });
      await c.cutoffUnmet();
      expect(s.sent('GET', 'wanted/cutoff'), hasLength(1));
      await c.searchAllMissing();
      await c.searchAllCutoffUnmet();
      expect([for (final a in s.sent('POST', 'command')) (a.body! as Map)['name']], [
        'MissingAlbumSearch',
        'CutoffUnmetAlbumSearch',
      ]);
    });

    test('the queue and the history with the artist and the album', () async {
      final s = _Lidarr();
      final c = _client(s);
      await c.queue();
      expect(s.sent('GET', 'queue').single.query, containsPair('includeArtist', ['true']));
      expect(s.sent('GET', 'queue').single.query, containsPair('includeAlbum', ['true']));
      expect(
        s.sent('GET', 'queue').single.query,
        containsPair('includeUnknownArtistItems', ['true']),
      );
      await c.recentHistory(only: ArrHistoryFilter.imported);
      final h = s.sent('GET', 'history').single.query;
      expect(h['eventType'], ['2', '3']);
      expect(h['includeArtist'], ['true']);
      expect(h['includeAlbum'], ['true']);
      expect(h['includeTrack'], ['true']);
    });
  });

  group('merged with the others', () {
    test('Lidarr\'s queue last, after Sonarr\'s and Radarr\'s', () async {
      final c = ProviderContainer(
        overrides: [
          sonarrClientProvider.overrideWithValue(null),
          radarrClientProvider.overrideWithValue(null),
          lidarrClientProvider.overrideWithValue(_client(_Lidarr())),
        ],
      );
      addTearDown(c.dispose);
      final sub = c.listen(arrQueueProvider, (_, _) {});
      addTearDown(sub.close);
      final q = await c.read(arrQueueProvider.future);
      expect(q.items.single.kind, ArrKind.lidarr);
      final status = await c.read(arrQueueStatusProvider.future);
      expect(status.count, 1);
      expect(status.problem, isTrue);
      final health = await c.read(arrHealthProvider.future);
      expect(health.single.kind, ArrKind.lidarr);
      expect(health.single.version, '3.1.6.5079');
      expect(health.single.problems, 1);
    });

    test('an app that didn\'t answer is said, Lidarr too', () async {
      final down = _Lidarr({'queue': () => throw const SocketException('down')});
      final c = ProviderContainer(
        overrides: [
          sonarrClientProvider.overrideWithValue(null),
          radarrClientProvider.overrideWithValue(null),
          lidarrClientProvider.overrideWithValue(_client(down)),
        ],
      );
      addTearDown(c.dispose);
      final sub = c.listen(arrQueueProvider, (_, _) {});
      addTearDown(sub.close);
      final q = await c.read(arrQueueProvider.future);
      expect(q.errors.keys, [ArrKind.lidarr]);
    });

    test('Home: one card for an artist, with its albums counted', () {
      ArrQueueItem dl(int id, int album, String title) =>
          ArrQueueItem.fromJson(ArrKind.lidarr, {
            ..._records('lidarr_queue').single,
            'id': id,
            'albumId': album,
            'album': {'id': album, 'title': title},
          });
      final cards = arrHomeDownloads([dl(1, 2, 'Dummy'), dl(2, 3, 'Third')]);
      expect(cards.single.title, 'Portishead');
      expect(cards.single.items, hasLength(2));
    });

    test('Home: an artist\'s later albums in the week are counted', () {
      final week = (start: DateTime(2026, 3, 2), end: DateTime(2026, 3, 9));
      ArrCalendarEntry e(int album, int day) => ArrCalendarEntry.fromAlbum({
        ..._list('lidarr_calendar').first,
        'id': album,
        'artistId': 1,
        'monitored': true,
        'releaseDate': '2026-03-0${day}T00:00:00Z',
        'statistics': {'trackFileCount': 0, 'totalTrackCount': 10},
      })!;
      final got = arrHomeComingUp([e(5, 4), e(6, 3)], week);
      expect(got.single.first.albumId, 6);
      expect(got.single.more, 1);
    });
  });

  group('on screen', () {
    testWidgets('the queue: the artist and album, and why it needs help', (
      t,
    ) async {
      final s = _Lidarr();
      await _open(t, _app(s));
      await _tab(t, 'Activity');
      expect(find.text('Portishead · Dummy'), findsOneWidget);
      expect(find.text('Import Failed'), findsOneWidget);
      // It tried and couldn't: Manual Import finishes it.
      expect(find.text('Manual Import'), findsOneWidget);
      // The tab counts it.
      expect(
        find.descendant(of: find.byType(TabBar), matching: find.text('1')),
        findsOneWidget,
      );
    });

    testWidgets('a queue card opens the artist', (t) async {
      await _open(t, _app(_Lidarr()), size: const Size(500, 1000));
      await _tab(t, 'Activity');
      await t.tap(find.text('Portishead · Dummy'));
      await _settle(t);
      expect(_visited.last, '/arr/artist/1');
    });

    testWidgets('History: the album and track; Imported asks Lidarr\'s numbers', (
      t,
    ) async {
      final s = _Lidarr();
      await _open(t, _app(s));
      await _tab(t, 'Activity');
      await t.tap(find.text('History'));
      await _settle(t);
      final rows = _records('lidarr_recent_history');
      final imported = rows.firstWhere((r) => r['eventType'] == 'trackFileImported');
      final line = [
        (imported['album'] as Map)['title'],
        (imported['track'] as Map)['title'],
      ].join(' · ');
      // Imported, deleted and renamed, the same track each time.
      expect(find.text(line), findsWidgets);
      await t.tap(find.byTooltip('Filter'));
      await _settle(t);
      await t.tap(find.text('Imported').last);
      await _settle(t);
      expect(s.sent('GET', 'history').last.query['eventType'], ['2', '3']);
    });

    testWidgets('Blocklist: the release, under its artist', (t) async {
      await _open(t, _app(_Lidarr()));
      await _tab(t, 'Activity');
      await t.tap(find.text('Blocklist'));
      await _settle(t);
      expect(find.text('Portishead'), findsOneWidget);
      expect(find.text('Portishead-Dummy-1994-WEB-MP3-320-GRP'), findsOneWidget);
    });

    testWidgets('Wanted: albums, each searched and picked by its own id', (
      t,
    ) async {
      final s = _Lidarr();
      await _open(t, _app(s));
      await _tab(t, 'Wanted');
      final first = _records('lidarr_wanted_missing').first;
      expect(find.text('A Moon Shaped Pool'), findsOneWidget);
      await t.tap(find.byTooltip('Search Album').first);
      await _settle(t);
      expect(s.sent('POST', 'command').single.body, {
        'name': 'AlbumSearch',
        'albumIds': [first['id']],
      });
      // Picked, they're searched and unmonitored as albums too.
      await t.tap(find.byTooltip('Select'));
      await _settle(t);
      await t.tap(find.text('A Moon Shaped Pool'));
      await _settle(t);
      await t.tap(find.byTooltip('Unmonitor'));
      await _settle(t);
      expect(s.sent('PUT', 'album/monitor').single.body, {
        'albumIds': [first['id']],
        'monitored': false,
      });
    });

    testWidgets('Wanted: picked albums searched as albums; Search All too', (
      t,
    ) async {
      final s = _Lidarr();
      await _open(t, _app(s));
      await _tab(t, 'Wanted');
      final ids = [for (final r in _records('lidarr_wanted_missing')) r['id']];
      await t.tap(find.byTooltip('Select'));
      await _settle(t);
      await t.tap(find.text('Select All'));
      await _settle(t);
      await t.tap(find.byTooltip('Search'));
      await _settle(t);
      final sent = s.sent('POST', 'command').single.body! as Map;
      expect(sent['name'], 'AlbumSearch');
      expect((sent['albumIds'] as List).toSet(), ids.toSet());
      await t.tap(find.byTooltip('Cancel'));
      await _settle(t);
      await t.tap(find.text('Search All'));
      await _settle(t);
      await t.tap(find.widgetWithText(FilledButton, 'Search All'));
      await _settle(t);
      expect(
        (s.sent('POST', 'command').last.body! as Map)['name'],
        'MissingAlbumSearch',
      );
    });

    testWidgets('Wanted\'s Interactive Search is the album\'s', (t) async {
      final s = _Lidarr();
      await _open(t, _app(s));
      await _tab(t, 'Wanted');
      final first = _records('lidarr_wanted_missing').first;
      await t.longPress(find.text('A Moon Shaped Pool'));
      await _settle(t);
      await t.tap(find.text('Interactive Search'));
      await _settle(t);
      expect(_visited.last, '/arr/releases?album=${first['id']}');
    });

    testWidgets('the Calendar: an album due, by its artist', (t) async {
      final now = DateTime.now();
      String day(int d) =>
          DateTime.utc(now.year, now.month, now.day + d).toIso8601String();
      final s = _Lidarr({
        'calendar': () => [
          {
            ..._list('lidarr_calendar').first,
            'title': 'New Album',
            'artistId': 1,
            'monitored': true,
            'releaseDate': day(2),
            'artist': {'artistName': 'Portishead', 'id': 1, 'images': []},
          },
        ],
      });
      // The day-by-day list: a wide window opens on the month.
      await _open(t, _app(s), size: const Size(500, 1000));
      await _tab(t, 'Calendar');
      expect(find.text('Portishead'), findsOneWidget);
      expect(find.text('New Album'), findsOneWidget);
      expect(find.text('Not Released'), findsOneWidget);
      await t.longPress(find.text('New Album'));
      await _settle(t);
      await t.tap(find.text('Search Album'));
      await _settle(t);
      expect(
        (s.sent('POST', 'command').single.body! as Map)['name'],
        'AlbumSearch',
      );
    });

    testWidgets('Health: Lidarr\'s version and what it found', (t) async {
      await _open(t, _app(_Lidarr(), home: const ArrHealthScreen()));
      expect(find.text('Lidarr 3.1.6.5079'), findsOneWidget);
      expect(find.text('Indexers unavailable due to failures: Rig'), findsOneWidget);
    });

    testWidgets('Home: Downloading Now names the album', (t) async {
      await _open(
        t,
        _app(
          _Lidarr(),
          home: const Scaffold(
            body: Column(children: [ArrDownloadingRow(height: 238)]),
          ),
        ),
      );
      expect(find.text('Portishead'), findsOneWidget);
      expect(find.textContaining('Dummy · Import Failed'), findsOneWidget);
      // The card's picture is what's pressed.
      await t.tap(find.byType(HoverPosterArt));
      await _settle(t);
      expect(_visited.last, '/arr/artist/1');
    });
  });
}
