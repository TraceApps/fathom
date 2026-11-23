import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fathom/api/arr_client.dart';
import 'package:fathom/api/jellyfin_client.dart';
import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/models/arr.dart';
import 'package:fathom/models/base_item.dart';
import 'package:fathom/models/session.dart';
import 'package:fathom/screens/arr_add_screen.dart';
import 'package:fathom/screens/arr_screen.dart';
import 'package:fathom/screens/artists_screen.dart';
import 'package:fathom/state/arr_providers.dart';
import 'package:fathom/state/preferences.dart';
import 'package:fathom/state/providers.dart';
import 'package:fathom/state/session_controller.dart';
import 'package:fathom/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// Adding artists to Lidarr from Fathom: the search, the form with Lidarr's
// own choices, what's sent, what's remembered, and the way in from a
// Jellyfin artist. Lookups are Lidarr 3.1.6's own answers, saved from the
// rig.

Object? _fixture(String name) =>
    jsonDecode(File('test/fixtures/arr/$name.json').readAsStringSync());

List<Map<String, dynamic>> _list(String name) => [
  for (final m in _fixture(name)! as List) Map<String, dynamic>.from(m as Map),
];

typedef _Asked = ({
  String method,
  String path,
  Map<String, String> query,
  Object? body,
});

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
    final q = o.uri.queryParameters;
    asked.add((method: o.method, path: path, query: q, body: o.data));
    final custom = answers[path];
    final Object? data = custom != null
        ? custom()
        : switch ((o.method, path)) {
            ('GET', 'artist/lookup')
                when (q['term'] ?? '').startsWith('lidarr:') =>
              _list('lidarr_lookup_mbid'),
            ('GET', 'artist/lookup') => _list('lidarr_lookup'),
            ('GET', 'artist') when q['mbId'] != null => [
              for (final a in _list('lidarr_artists'))
                if (a['foreignArtistId'] == q['mbId']) a,
            ],
            ('GET', 'artist') => _list('lidarr_artists'),
            ('POST', 'artist') => {
              ...Map<String, dynamic>.from(o.data as Map),
              'id': 42,
            },
            ('GET', 'rootfolder') => [
              {'id': 1, 'path': '/music', 'freeSpace': 1 << 40},
              {'id': 2, 'path': '/music-lossless', 'freeSpace': 1 << 40},
            ],
            ('GET', 'qualityprofile') => [
              {'id': 1, 'name': 'Any'},
              {'id': 2, 'name': 'Lossless'},
            ],
            ('GET', 'metadataprofile') => _list('lidarr_metadataprofile'),
            ('GET', 'tag') => const [],
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
  _FakePrefs(this.initial);
  final Prefs initial;

  @override
  Future<Prefs> build() async => initial;

  @override
  Future<void> edit(Prefs Function(Prefs) change) async {
    state = AsyncData(change(state.asData?.value ?? initial));
  }
}

class _Signed extends SessionController {
  _Signed(this.session);
  final Session? session;

  @override
  Future<Session?> build() async => session;
}

/// A Jellyfin server with one music artist, its ids as Jellyfin reads them
/// from the files' tags.
class _Jellyfin implements HttpClientAdapter {
  final String mbId;
  _Jellyfin(this.mbId);
  final List<String> asked = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    asked.add(o.uri.path);
    final Object data = o.uri.path.endsWith('/Items/jf-artist')
        ? {
            'Id': 'jf-artist',
            'Name': 'Someone',
            'Type': 'MusicArtist',
            'ProviderIds': {'MusicBrainzArtist': mbId},
          }
        : {'Items': const []};
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

final _visited = <String>[];
late ProviderContainer _container;

Widget _app(
  _Lidarr? lidarr, {
  required Widget home,
  Prefs prefs = const Prefs(),
  _Jellyfin? jellyfin,
  bool radarr = false,
}) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, _) => home),
      GoRoute(
        path: '/arr/add/:kind',
        builder: (_, s) {
          _visited.add(s.uri.toString());
          return ArrAddScreen(
            kind: s.pathParameters['kind'] == 'artist' ? ArrKind.lidarr : null,
            term: s.uri.queryParameters['term'],
          );
        },
      ),
      GoRoute(
        path: '/arr/artist/:id',
        builder: (_, s) {
          _visited.add(s.uri.toString());
          return Scaffold(body: Text('artist ${s.pathParameters['id']}'));
        },
      ),
    ],
  );
  _container = ProviderContainer(
    overrides: [
      lidarrClientProvider.overrideWithValue(
        lidarr == null ? null : _client(lidarr),
      ),
      sonarrClientProvider.overrideWithValue(null),
      radarrClientProvider.overrideWithValue(
        radarr ? RadarrClient('http://r', 'k', dio: Dio()..httpClientAdapter = _Lidarr()) : null,
      ),
      preferencesProvider.overrideWith(() => _FakePrefs(prefs)),
      sessionControllerProvider.overrideWith(
        () => _Signed(
          jellyfin == null
              ? null
              : const Session(
                  baseUrl: 'http://jf',
                  accessToken: 't',
                  userId: 'u',
                  userName: 'rig',
                ),
        ),
      ),
      if (jellyfin != null)
        jellyfinClientProvider.overrideWithValue(
          JellyfinClient(
            deviceId: 'd',
            httpClient: Dio()..httpClientAdapter = jellyfin,
          ),
        ),
    ],
  );
  addTearDown(_container.dispose);
  return UncontrolledProviderScope(
    container: _container,
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
  Size size = const Size(1000, 1400),
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(app);
  await _settle(t);
}

/// Types [term] into Add's box and lets the search run.
Future<void> _search(WidgetTester t, String term) async {
  await t.enterText(find.byType(TextField).first, term);
  await t.pump(const Duration(milliseconds: 600));
  await _settle(t);
}

void main() {
  setUp(_visited.clear);

  group('which apps a search goes to', () {
    const all = [ArrKind.radarr, ArrKind.sonarr, ArrKind.lidarr];
    test('a name to every app', () {
      expect(arrAddKindsFor('Portishead', all), all);
    });
    test('an id to the app it belongs to', () {
      expect(arrAddKindsFor('lidarr:8f6bd1e4', all), [ArrKind.lidarr]);
      expect(arrAddKindsFor('tmdb:603', all), [ArrKind.radarr]);
      expect(arrAddKindsFor('tvdb:81189', all), [ArrKind.sonarr]);
      expect(arrAddKindsFor('imdb:tt0133093', all), [
        ArrKind.radarr,
        ArrKind.sonarr,
      ]);
    });
    test('an id none of them takes goes to them all', () {
      expect(arrAddKindsFor('tmdb:603', const [ArrKind.sonarr, ArrKind.lidarr]), [
        ArrKind.sonarr,
        ArrKind.lidarr,
      ]);
    });

    test('one app on its own gets every search', () {
      expect(arrAddKindsFor('tmdb:603', const [ArrKind.lidarr]), [
        ArrKind.lidarr,
      ]);
    });
  });

  group('what Add starts with', () {
    ArrAddedWith artist(String path, int profile, int metadata) => (
      path: path,
      qualityProfileId: profile,
      minimumAvailability: null,
      seriesType: null,
      seasonFolder: null,
      metadataProfileId: metadata,
    );

    test('the metadata profile most of the artists use', () {
      final c = arrStartingChoice(
        kind: ArrKind.lidarr,
        saved: const ArrAddDefaults(),
        roots: const ['/music', '/music-lossless'],
        profiles: const [1, 2],
        metadataProfiles: const [1, 2],
        library: [
          artist('/music-lossless/A', 2, 2),
          artist('/music-lossless/B', 2, 2),
          artist('/music/C', 1, 1),
        ],
      );
      expect(c.rootFolder, '/music-lossless');
      expect(c.qualityProfileId, 2);
      expect(c.metadataProfileId, 2);
      expect(c.monitor, 'all');
      expect(c.monitorNewItems, 'all');
      expect(c.profileSource, ArrChoiceSource.library);
    });

    test('saved choices first, while the server still has them', () {
      final c = arrStartingChoice(
        kind: ArrKind.lidarr,
        saved: const ArrAddDefaults(
          metadataProfileId: 1,
          monitor: 'latest',
          monitorNewItems: 'new',
          search: false,
        ),
        roots: const ['/music'],
        profiles: const [1],
        metadataProfiles: const [1, 2],
        library: [artist('/music/A', 1, 2)],
      );
      expect(c.metadataProfileId, 1);
      expect(c.monitor, 'latest');
      expect(c.monitorNewItems, 'new');
      expect(c.search, isFalse);
      // A profile since deleted: what the library uses.
      final gone = arrStartingChoice(
        kind: ArrKind.lidarr,
        saved: const ArrAddDefaults(metadataProfileId: 9),
        roots: const ['/music'],
        profiles: const [1],
        metadataProfiles: const [1, 2],
        library: [artist('/music/A', 1, 2)],
      );
      expect(gone.metadataProfileId, 2);
      // Nothing to go on: Lidarr's first.
      final first = arrStartingChoice(
        kind: ArrKind.lidarr,
        saved: const ArrAddDefaults(),
        roots: const ['/music'],
        profiles: const [1],
        metadataProfiles: const [2, 1],
        library: const [],
      );
      expect(first.metadataProfileId, 2);
    });

    test('Lidarr\'s choices are kept with the rest', () {
      const d = ArrAddDefaults(metadataProfileId: 2, monitorNewItems: 'none');
      expect(ArrAddDefaults.fromJson(d.toJson()), d);
      expect(d.isEmpty, isFalse);
      final p = Prefs.fromJson(
        Prefs(lidarrAddDefaults: d.toJson()).toJson(),
      );
      expect(ArrAddDefaults.fromJson(p.lidarrAddDefaults), d);
    });
  });

  group('what Lidarr is asked', () {
    test('a lookup, and an artist added with every choice', () async {
      final s = _Lidarr();
      final c = _client(s);
      final found = await c.lookup('portishead');
      expect(s.sent('GET', 'artist/lookup').single.query, {'term': 'portishead'});
      expect(found.first.inLibrary, isTrue);
      expect(found[1].inLibrary, isFalse);
      final added = await c.addArtist(
        found[1].raw,
        qualityProfileId: 2,
        metadataProfileId: 1,
        rootFolderPath: '/music',
        monitor: 'latest',
        monitorNewItems: 'new',
        search: true,
        tags: const [3],
      );
      expect(added.id, 42);
      final body = Map<String, dynamic>.from(
        s.sent('POST', 'artist').single.body! as Map,
      );
      expect(body['foreignArtistId'], found[1].raw['foreignArtistId']);
      expect(body['qualityProfileId'], 2);
      expect(body['metadataProfileId'], 1);
      expect(body['rootFolderPath'], '/music');
      expect(body['monitored'], isTrue);
      expect(body['monitorNewItems'], 'new');
      expect(body['tags'], [3]);
      expect(body['addOptions'], {
        'monitor': 'latest',
        'searchForMissingAlbums': true,
      });
      expect(body.containsKey('id'), isFalse);
    });

    test('a lookup\'s own id is never sent back', () async {
      final s = _Lidarr();
      final found = await _client(s).lookup('portishead');
      expect(found.first.raw['id'], 1);
      await _client(s).addArtist(
        found.first.raw,
        qualityProfileId: 1,
        metadataProfileId: 1,
        rootFolderPath: '/music',
        monitor: 'all',
        monitorNewItems: 'all',
        search: false,
      );
      expect((s.sent('POST', 'artist').single.body! as Map).containsKey('id'), isFalse);
    });

    test('None leaves the artist unmonitored', () async {
      final s = _Lidarr();
      final found = await _client(s).lookup('portishead');
      await _client(s).addArtist(
        found[1].raw,
        qualityProfileId: 1,
        metadataProfileId: 1,
        rootFolderPath: '/music',
        monitor: 'none',
        monitorNewItems: 'none',
        search: false,
      );
      final body = s.sent('POST', 'artist').single.body! as Map;
      expect(body['monitored'], isFalse);
    });
  });

  group('Add Artist', () {
    testWidgets('results say which are in the library, and tell artists apart', (
      t,
    ) async {
      final s = _Lidarr();
      await _open(t, _app(s, home: const ArrAddScreen(kind: ArrKind.lidarr)));
      // In the bar, and on the page under it.
      expect(find.text('Add Artist'), findsNWidgets(2));
      expect(find.text('Search for an artist'), findsOneWidget);
      await _search(t, 'portishead');
      expect(find.text('Portishead'), findsOneWidget);
      expect(find.text('In Library'), findsOneWidget);
      expect(
        find.text('Group · Industrial, thrash, groove and sludge'),
        findsOneWidget,
      );
      // Already there: its page.
      await t.tap(find.text('Portishead'));
      await _settle(t);
      expect(_visited.last, '/arr/artist/1');
    });

    testWidgets('the form: Lidarr\'s choices, sent, remembered, then its page', (
      t,
    ) async {
      final s = _Lidarr();
      await _open(t, _app(s, home: const ArrAddScreen(kind: ArrKind.lidarr)));
      await _search(t, 'portishead');
      await t.tap(find.text('Mortishead'));
      await _settle(t);
      for (final field in [
        'Root Folder',
        'Quality Profile',
        'Metadata Profile',
        'Albums to Monitor',
        'Monitor New Albums',
        'Start Search for Missing Albums',
      ]) {
        expect(find.text(field), findsOneWidget, reason: field);
      }
      // Neither a show's nor a movie's own.
      expect(find.text('Series Type'), findsNothing);
      expect(find.text('Minimum Availability'), findsNothing);
      // What most of the artists use: Portishead's profiles.
      expect(find.text('What most of your artists use'), findsOneWidget);
      await t.tap(find.text('All Albums').first);
      await _settle(t);
      await t.tap(find.text('Latest Album').last);
      await _settle(t);
      await t.tap(find.widgetWithText(FilledButton, 'Add'));
      await _settle(t);
      final body = s.sent('POST', 'artist').single.body! as Map;
      expect(body['artistName'], 'Mortishead');
      expect(body['metadataProfileId'], 1);
      expect(body['addOptions'], {
        'monitor': 'latest',
        'searchForMissingAlbums': true,
      });
      expect(_visited.last, '/arr/artist/42');
      final saved = ArrAddDefaults.fromJson(
        _container.read(preferencesProvider).requireValue.lidarrAddDefaults,
      );
      expect(saved.monitor, 'latest');
      expect(saved.metadataProfileId, 1);
      expect(saved.monitorNewItems, 'all');
      // A movie's and a show's own choices aren't kept for artists.
      expect(saved.minimumAvailability, isNull);
      expect(saved.seriesType, isNull);
    });

    testWidgets('the form starts on what was saved', (t) async {
      final s = _Lidarr();
      await _open(
        t,
        _app(
          s,
          home: const ArrAddScreen(kind: ArrKind.lidarr),
          prefs: const Prefs(
            lidarrAddDefaults: {
              'monitor': 'latest',
              'metadataProfileId': 2,
              'monitorNewItems': 'none',
            },
          ),
        ),
      );
      await _search(t, 'portishead');
      await t.tap(find.text('Mortishead'));
      await _settle(t);
      expect(find.text('Latest Album'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, 'Add'));
      await _settle(t);
      final body = s.sent('POST', 'artist').single.body! as Map;
      expect(body['metadataProfileId'], 2);
      expect(body['monitorNewItems'], 'none');
      expect((body['addOptions'] as Map)['monitor'], 'latest');
    });

    testWidgets('else the metadata profile most of the artists use', (t) async {
      final s = _Lidarr({
        'artist': () => [
          for (final a in _list('lidarr_artists')) {...a, 'metadataProfileId': 2},
        ],
      });
      await _open(t, _app(s, home: const ArrAddScreen(kind: ArrKind.lidarr)));
      await _search(t, 'portishead');
      await t.tap(find.text('Mortishead'));
      await _settle(t);
      await t.tap(find.widgetWithText(FilledButton, 'Add'));
      await _settle(t);
      expect((s.sent('POST', 'artist').single.body! as Map)['metadataProfileId'], 2);
    });

    testWidgets('by MusicBrainz id, the form opens on its own', (t) async {
      final s = _Lidarr();
      await _open(
        t,
        _app(
          s,
          home: const ArrAddScreen(
            kind: ArrKind.lidarr,
            term: 'lidarr:10adbe5e-a2c0-4bf3-8249-2b4cbf6e6ca8',
          ),
        ),
      );
      expect(find.text('Metadata Profile'), findsOneWidget);
      expect(find.text('Massive Attack'), findsWidgets);
    });

    testWidgets('beside Radarr: Music among the choices, a name to both', (
      t,
    ) async {
      final s = _Lidarr();
      await _open(t, _app(s, home: const ArrAddScreen(), radarr: true));
      expect(find.text('Music'), findsOneWidget);
      expect(find.text('Movies'), findsOneWidget);
      expect(find.text('Shows'), findsNothing);
      expect(find.text('Add a Title'), findsNWidgets(2));
      await _search(t, 'portishead');
      expect(s.sent('GET', 'artist/lookup'), hasLength(1));
      await _search(t, 'tmdb:603');
      expect(s.sent('GET', 'artist/lookup'), hasLength(1));
    });
  });

  group('the Music library', () {
    testWidgets('an empty one offers Add Artist; Add opens on artists', (t) async {
      final s = _Lidarr({'artist': () => const []});
      await _open(t, _app(s, home: const ArrScreen()));
      await t.tap(find.widgetWithText(FilledButton, 'Add Artist'));
      await _settle(t);
      expect(_visited.last, '/arr/add/artist');
      // The section's own Add, from the Music library.
      _visited.clear();
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(_app(s, home: const ArrScreen()));
      await _settle(t);
      await t.tap(find.text('Add').first);
      await _settle(t);
      expect(_visited.last, '/arr/add/artist');
    });

    testWidgets('a search offers to look the name up in Lidarr', (t) async {
      final s = _Lidarr();
      await _open(t, _app(s, home: const ArrScreen()));
      await t.enterText(find.byType(TextField).first, 'radio');
      await _settle(t);
      expect(find.text('Look it up in Lidarr'), findsOneWidget);
      await t.tap(find.text('Look it up in Lidarr'));
      await _settle(t);
      expect(_visited.last, '/arr/add/artist?term=radio');
    });
  });

  group('from a Jellyfin artist', () {
    testWidgets('Manage in Lidarr, for an artist Lidarr has', (t) async {
      final s = _Lidarr();
      await _open(
        t,
        _app(
          s,
          home: const ArtistAlbumsScreen(
            artistId: 'jf-artist',
            artistName: 'Portishead',
          ),
          jellyfin: _Jellyfin('8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11'),
        ),
      );
      expect(s.sent('GET', 'artist').single.query, {
        'mbId': '8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11',
      });
      await t.tap(find.byTooltip('Manage in Lidarr'));
      await _settle(t);
      expect(_visited.last, '/arr/artist/1');
    });

    testWidgets('Add to Lidarr, by its id, for one it hasn\'t', (t) async {
      final s = _Lidarr();
      await _open(
        t,
        _app(
          s,
          home: const ArtistAlbumsScreen(
            artistId: 'jf-artist',
            artistName: 'Massive Attack',
          ),
          jellyfin: _Jellyfin('10adbe5e-a2c0-4bf3-8249-2b4cbf6e6ca8'),
        ),
      );
      expect(find.byTooltip('Manage in Lidarr'), findsNothing);
      await t.tap(find.byTooltip('Add to Lidarr'));
      await _settle(t);
      expect(
        _visited.first,
        '/arr/add/artist?term=lidarr%3A10adbe5e-a2c0-4bf3-8249-2b4cbf6e6ca8',
      );
    });

    testWidgets('once added, the page links to it in Lidarr', (t) async {
      var added = false;
      late final _Lidarr s;
      s = _Lidarr({
        'artist': () {
          // Before the add Lidarr has no such artist; after, it has.
          final mb = s.asked.last.query['mbId'];
          if (s.asked.last.method == 'POST') {
            added = true;
            return {
              ...Map<String, dynamic>.from(s.asked.last.body! as Map),
              'id': 42,
            };
          }
          if (mb == null) return _list('lidarr_artists');
          return [
            if (added)
              {..._list('lidarr_lookup_mbid').single, 'id': 42},
          ];
        },
      });
      await _open(
        t,
        _app(
          s,
          home: const ArtistAlbumsScreen(
            artistId: 'jf-artist',
            artistName: 'Massive Attack',
          ),
          jellyfin: _Jellyfin('10adbe5e-a2c0-4bf3-8249-2b4cbf6e6ca8'),
        ),
      );
      await t.tap(find.byTooltip('Add to Lidarr'));
      await _settle(t);
      await t.tap(find.widgetWithText(FilledButton, 'Add'));
      await _settle(t);
      expect(added, isTrue);
      expect(_visited.last, '/arr/artist/42');
      // Back on Jellyfin's page: it says the artist is in Lidarr now.
      Navigator.of(t.element(find.text('artist 42'))).pop();
      await _settle(t);
      await t.pump(const Duration(milliseconds: 400));
      await _settle(t);
      expect(find.byTooltip('Manage in Lidarr'), findsOneWidget);
      expect(find.byTooltip('Add to Lidarr'), findsNothing);
    });

    testWidgets('nothing, and nothing asked, without Lidarr', (t) async {
      final jf = _Jellyfin('8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11');
      await _open(
        t,
        _app(
          null,
          home: const ArtistAlbumsScreen(
            artistId: 'jf-artist',
            artistName: 'Portishead',
          ),
          jellyfin: jf,
        ),
      );
      expect(find.byTooltip('Manage in Lidarr'), findsNothing);
      expect(find.byTooltip('Add to Lidarr'), findsNothing);
      // Jellyfin isn't asked for the artist's ids with nothing to use them.
      expect(jf.asked.where((p) => p.endsWith('/Items/jf-artist')), isEmpty);
    });

    testWidgets('nothing for an artist with no id', (
      t,
    ) async {
      final s = _Lidarr();
      await _open(
        t,
        _app(
          s,
          home: const ArtistAlbumsScreen(
            artistId: 'jf-artist',
            artistName: 'Someone',
          ),
          jellyfin: _Jellyfin(''),
        ),
      );
      expect(find.byTooltip('Add to Lidarr'), findsNothing);
      expect(s.sent('GET', 'artist'), isEmpty);
    });
  });

  test('Jellyfin\'s MusicBrainz artist id is read', () {
    final item = BaseItemDto.fromJson({
      'Id': 'a',
      'Name': 'Portishead',
      'Type': 'MusicArtist',
      'ProviderIds': {'MusicBrainzArtist': 'abc'},
    });
    expect(item.musicBrainzArtistId, 'abc');
  });
}
