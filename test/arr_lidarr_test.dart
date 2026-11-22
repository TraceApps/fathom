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
import 'package:fathom/screens/arr_detail_screens.dart';
import 'package:fathom/screens/arr_releases_screen.dart';
import 'package:fathom/screens/arr_screen.dart';
import 'package:fathom/screens/arr_settings_screen.dart';
import 'package:fathom/services/settings_backup.dart';
import 'package:fathom/services/tv_mode.dart';
import 'package:fathom/state/arr_providers.dart';
import 'package:fathom/state/preferences.dart';
import 'package:fathom/state/providers.dart';
import 'package:fathom/state/session_controller.dart';
import 'package:fathom/theme/app_theme.dart';
import 'package:fathom/widgets/arr_widgets.dart';
import 'package:fathom/widgets/detail_header.dart';
import 'package:fathom/widgets/media_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// Lidarr in the Manage section: its artists in the Library, an artist's
// page with its albums and their tracks, and what each action asks Lidarr
// for. The answers are Lidarr 3.1.6's own, saved from a real server.

Object? _fixture(String name) =>
    jsonDecode(File('test/fixtures/arr/$name.json').readAsStringSync());

Map<String, dynamic> _map(String name) =>
    Map<String, dynamic>.from(_fixture(name)! as Map);

List<Map<String, dynamic>> _list(String name) => [
  for (final m in _fixture(name)! as List) Map<String, dynamic>.from(m as Map),
];

/// One request: its method, where it went (after /api/v1/), its query and
/// its body.
typedef _Asked = ({
  String method,
  String path,
  Map<String, String> query,
  Object? body,
});

/// A Lidarr that answers from the saved answers and keeps what was asked.
class _Lidarr implements HttpClientAdapter {
  final List<_Asked> asked = [];

  /// Replaces an answer: by path, what to send back.
  final Map<String, Object? Function()> answers;

  /// How long the answer to a path takes; none by default.
  final Map<String, Duration> slow;
  _Lidarr([this.answers = const {}, this.slow = const {}]);

  /// Paths that came in without the v1 API in them.
  final List<String> wrong = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    final full = o.uri.path;
    if (!full.contains('/api/v1/')) wrong.add(full);
    final path = full.replaceFirst(RegExp(r'^.*/api/v1/'), '');
    final q = o.uri.queryParameters;
    asked.add((method: o.method, path: path, query: q, body: o.data));
    final wait = slow[path];
    if (wait != null) await Future<void>.delayed(wait);
    final custom = answers[path];
    final Object? data = custom != null
        ? custom()
        : o.method != 'GET'
        ? const {}
        : switch (path) {
            'artist' => _list('lidarr_artists'),
            'artist/1' => _map('lidarr_artist1'),
            'album' => _list('lidarr_albums'),
            final p when p.startsWith('album/') => _list(
              'lidarr_albums',
            ).firstWhere((a) => 'album/${a['id']}' == p),
            'track' when q['albumId'] == '3' => _list('lidarr_tracks_album3'),
            'track' when q['albumId'] == '1' => _list('lidarr_tracks_album1'),
            'track' => const [],
            'trackfile' => _list('lidarr_trackfiles'),
            'history' => _map('lidarr_history'),
            'metadataprofile' => _list('lidarr_metadataprofile'),
            'qualityprofile' => [
              {'id': 1, 'name': 'Any'},
              {'id': 2, 'name': 'Lossless'},
              {'id': 3, 'name': 'Standard'},
            ],
            'tag' => const [],
            'rootfolder' => [
              {'id': 1, 'path': '/music', 'freeSpace': 1000},
            ],
            'system/status' => {'appName': 'Lidarr', 'version': '3.1.6.5079'},
            'release' => const [],
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

  Map<String, dynamic> body(String method, String path) =>
      Map<String, dynamic>.from(sent(method, path).single.body! as Map);
}

LidarrClient _client(_Lidarr server) =>
    LidarrClient('http://lidarr:8686', 'k', dio: Dio()..httpClientAdapter = server);

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

/// A Jellyfin library with one music artist, found by name as a real one
/// finds it (checked against Jellyfin's /Items on the rig).
class _Jellyfin implements HttpClientAdapter {
  final List<Map<String, String>> asked = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    final q = o.uri.queryParameters;
    asked.add(q);
    final match =
        q['IncludeItemTypes'] == 'MusicArtist' &&
        (q['SearchTerm'] ?? '').toLowerCase() == 'portishead';
    return ResponseBody.fromString(
      jsonEncode({
        'Items': [
          if (match)
            {
              'Id': 'jf-portishead',
              'Name': 'Portishead',
              'Type': 'MusicArtist',
              'ProviderIds': {
                'AudioDbArtist': '111957',
                'MusicBrainzArtist': '8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11',
              },
            },
        ],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Pages reached from the one under test, by name, so a test can see where
/// a tap went.
final _visited = <String>[];

/// The router of the app last built.
late GoRouter _router;

Widget _app({
  required Widget home,
  _Lidarr? lidarr,
  bool radarr = false,
  Prefs prefs = const Prefs(),
  Session? session,
  _Jellyfin? jellyfin,
}) {
  final router = _router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, _) => home),
      GoRoute(
        path: '/arr/artist/:id',
        builder: (_, s) => ArrArtistScreen(
          id: int.parse(s.pathParameters['id']!),
        ),
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
      GoRoute(
        path: '/item',
        builder: (_, s) {
          _visited.add('/item');
          return const Scaffold(body: Text('jellyfin item'));
        },
      ),
      GoRoute(
        path: '/artist',
        builder: (_, s) {
          _visited.add('/artist ${(s.extra! as BaseItemDto).id}');
          return const Scaffold(body: Text('jellyfin artist'));
        },
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      lidarrClientProvider.overrideWithValue(
        lidarr == null ? null : _client(lidarr),
      ),
      sonarrClientProvider.overrideWithValue(null),
      radarrClientProvider.overrideWithValue(
        radarr
            ? RadarrClient(
                'http://r',
                'k',
                dio: Dio()..httpClientAdapter = (_Lidarr()),
              )
            : null,
      ),
      preferencesProvider.overrideWith(() => _FakePrefs(prefs)),
      sessionControllerProvider.overrideWith(() => _Signed(session)),
      if (jellyfin != null)
        jellyfinClientProvider.overrideWithValue(
          JellyfinClient(
            deviceId: 'd',
            httpClient: Dio()..httpClientAdapter = jellyfin,
          ),
        ),
    ],
    child: MaterialApp.router(
      theme: AppTheme.dark(const Color(0xFF8AB4F8)),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

/// The poster above [name] in the library's grid: the part that's pressed.
Finder _poster(String name) => find.descendant(
  of: find.byWidgetPredicate(
    (w) => w is Column && w.children.any((c) => c is Text && c.data == name),
  ),
  matching: find.byType(HoverPosterArt),
);

/// A round button in an artist's header, by its name.
Finder _button(String name) => find.byWidgetPredicate(
  (w) => w is HeaderActionButton && w.tooltip == name,
);

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _open(
  WidgetTester t,
  Widget app, {
  // Tall enough for an artist's albums under its header and facts: a list
  // builds only the rows in sight.
  Size size = const Size(1200, 2400),
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(app);
  await _settle(t);
}

void main() {
  setUp(_visited.clear);

  group('Lidarr\'s answers, read', () {
    test('an artist: counts, profiles, its MusicBrainz id', () {
      final a = ArrArtist.fromJson(_map('lidarr_artist1'));
      expect(a.id, 1);
      expect(a.name, 'Portishead');
      expect(a.foreignArtistId, '8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11');
      expect(a.artistType, 'Group');
      expect(a.monitored, isTrue);
      expect(a.monitorNewItems, 'all');
      expect(a.qualityProfileId, 1);
      expect(a.metadataProfileId, 1);
      expect(a.path, '/music/Portishead');
      expect(a.trackFileCount, 11);
      expect(a.trackCount, 46);
      expect(a.missingTracks, 35);
      expect(a.progress, closeTo(11 / 46, 1e-9));
      expect(a.sizeOnDisk, 2159968);
      expect(a.lastAlbum?.title, 'Third');
      expect(a.lastAlbum?.releaseDate, DateTime(2008, 4, 8));
      expect(a.images.map((i) => i.coverType), contains('poster'));
      // Radiohead: one album monitored, so 24 tracks wanted of 302.
      final r = ArrArtist.fromJson(
        _list('lidarr_artists').firstWhere((x) => x['artistName'] == 'Radiohead'),
      );
      expect(r.totalTrackCount, greaterThan(r.trackCount));
      expect(
        ArrArtist.fromJson({
          ..._list('lidarr_artists').last,
          'statistics': {'trackFileCount': 12, 'trackCount': 24, 'totalTrackCount': 302},
        }).progress,
        0.5,
      );
    });

    test('albums: kind, release day, track counts', () {
      final albums = [
        for (final m in _list('lidarr_albums')) ArrAlbum.fromJson(m),
      ];
      final first = albums.firstWhere((a) => a.id == 1);
      expect(first.title, 'Portishead');
      expect(first.albumType, 'Album');
      // A release date is a day, not a moment: it stays the 29th anywhere.
      expect(first.releaseDate, DateTime(1997, 9, 29));
      expect(first.trackFileCount, 11);
      expect(first.totalTrackCount, 11);
      expect(first.complete, isTrue);
      expect(first.artistName, 'Portishead');
      expect(first.foreignAlbumId, '46b38f09-e90b-39eb-b04f-002da20f7f96');
      expect(first.images.map((i) => i.coverType), contains('cover'));
      final third = albums.firstWhere((a) => a.id == 3);
      expect(third.complete, isFalse);
      expect(third.progress, 0);
      expect(third.released(DateTime(2008, 4, 8)), isTrue);
      expect(third.released(DateTime(2008, 4, 7)), isFalse);
    });

    test('tracks: vinyl sides, discs, and no file as none', () {
      final vinyl = [
        for (final m in _list('lidarr_tracks_album1')) ArrTrack.fromJson(m),
      ];
      expect(vinyl.first.trackNumber, 'A1');
      expect(vinyl.first.title, 'Cowboys');
      expect(vinyl.first.duration, const Duration(seconds: 282));
      final boxed = [
        for (final m in _list('lidarr_tracks_album3')) ArrTrack.fromJson(m),
      ];
      expect({for (final t in boxed) t.mediumNumber}, {1, 2, 3, 4});
      final missing = ArrTrack.fromJson({
        ..._list('lidarr_tracks_album3').first,
        'trackFileId': 0,
        'hasFile': false,
      });
      expect(missing.trackFileId, isNull);
      expect(missing.hasFile, isFalse);
    });

    test('a track file: quality, album, and the audio as Lidarr words it', () {
      final f = ArrFile.fromJson(_list('lidarr_trackfiles').first);
      expect(f.quality, 'FLAC');
      expect(f.albumId, 1);
      expect(f.path, startsWith('/music/Portishead/'));
      expect(f.mediaInfo?.audioCodec, 'FLAC');
      expect(f.mediaInfo?.audioBits, '16bit');
      expect(f.mediaInfo?.audioSampleRate, '44.1kHz');
      expect(f.mediaInfo?.audioBitRate, isNotNull);
    });

    test('history: imports by track, under their own name', () {
      final h = ArrHistoryItem.fromJson(
        Map<String, dynamic>.from(
          (_map('lidarr_history')['records'] as List).first as Map,
        ),
        ArrKind.lidarr,
      );
      expect(h.trackTitle, 'Cowboys');
      expect(h.eventType, 'trackFileImported');
      expect(h.quality, 'FLAC');
      expect(h.date, isNotNull);
    });

    test('a rename preview names its track file', () {
      final r = ArrRename.fromJson({
        'artistId': 1,
        'albumId': 1,
        'trackNumbers': [1],
        'trackFileId': 7,
        'existingPath': 'Portishead/01 - Cowboys.flac',
        'newPath': 'Portishead/Portishead (1997)/01 - Cowboys.flac',
      });
      expect(r.fileId, 7);
    });

    test('the API key is kept out of backups, as the others are', () {
      expect(secretPrefKeys, contains('lidarrApiKey'));
      final json = const Prefs(lidarrUrl: 'http://l', lidarrApiKey: 'x').toJson();
      expect(Prefs.fromJson(json).lidarrApiKey, 'x');
      expect(Prefs.fromJson(json).lidarrUrl, 'http://l');
    });
  });

  group('what Lidarr is asked', () {
    test('every call goes to the v1 API', () async {
      final s = _Lidarr();
      final c = _client(s);
      await c.artists();
      await c.artist(1);
      await c.albums(1);
      await c.tracks(1);
      await c.trackFiles(1);
      await c.history(1);
      await c.metadataProfiles();
      await c.qualityProfiles();
      await c.status();
      expect(s.wrong, isEmpty);
      expect(s.sent('GET', 'album').single.query, {'artistId': '1'});
      expect(s.sent('GET', 'track').single.query, {'albumId': '1'});
      expect(s.sent('GET', 'trackfile').single.query, {'artistId': '1'});
      // From the whole history, by artist: Lidarr's per-artist list leaves
      // the tracks out.
      expect(s.sent('GET', 'history').single.query, {
        'page': '1',
        'pageSize': '100',
        'sortKey': 'date',
        'sortDirection': 'descending',
        'artistIds': '1',
        'includeAlbum': 'true',
        'includeTrack': 'true',
      });
    });

    test('Sonarr and Radarr stay on v3', () async {
      expect(
        SonarrClient('http://s', 'k').webUrl('x'),
        'http://s/series/x',
      );
      // The path is built the same way for every request; v3 for these two.
      final asked = <String>[];
      final dio = Dio()
        ..httpClientAdapter = _Capture((o) => asked.add(o.uri.path));
      await RadarrClient('http://r', 'k', dio: dio).status();
      await SonarrClient('http://s', 'k', dio: dio).status();
      await LidarrClient('http://l', 'k', dio: dio).status();
      expect(asked, [
        '/api/v3/system/status',
        '/api/v3/system/status',
        '/api/v1/system/status',
      ]);
    });

    test('another app at Lidarr\'s address is caught on Save & Test', () async {
      final s = _Lidarr({
        'system/status': () => {'appName': 'Radarr', 'version': '6.0'},
      });
      await expectLater(
        _client(s).status(),
        throwsA(
          isA<ArrException>().having(
            (e) => e.message,
            'message',
            'This address is Radarr, not Lidarr.',
          ),
        ),
      );
    });

    test('monitoring: one call, with the choice or without it', () async {
      final s = _Lidarr();
      final c = _client(s);
      await c.applyMonitoring(1, monitor: 'latest', monitored: true, newItems: 'new');
      expect(s.body('POST', 'albumstudio'), {
        'artist': [
          {'id': 1, 'monitored': true},
        ],
        'monitoringOptions': {'monitor': 'latest'},
        'monitorNewItems': 'new',
      });
      s.asked.clear();
      // Albums left as they are: Lidarr then only saves the artist.
      await c.applyMonitoring(1, monitor: null, monitored: false, newItems: 'none');
      expect(s.body('POST', 'albumstudio'), {
        'artist': [
          {'id': 1, 'monitored': false},
        ],
        'monitorNewItems': 'none',
      });
    });

    test('albums, searches, deletes and the editor', () async {
      final s = _Lidarr();
      final c = _client(s);
      await c.setAlbumsMonitored([3], false);
      expect(s.body('PUT', 'album/monitor'), {
        'albumIds': [3],
        'monitored': false,
      });
      await c.searchAlbums([1, 3]);
      await c.searchArtist(2);
      await c.refreshArtist(2);
      expect([for (final a in s.sent('POST', 'command')) a.body], [
        {'name': 'AlbumSearch', 'albumIds': [1, 3]},
        {'name': 'ArtistSearch', 'artistId': 2},
        {'name': 'RefreshArtist', 'artistId': 2},
      ]);
      await c.deleteTitle(2, deleteFiles: true, addExclusion: true);
      expect(s.sent('DELETE', 'artist/2').single.query, {
        'deleteFiles': 'true',
        'addImportListExclusion': 'true',
      });
      await c.deleteTrackFiles([4, 5]);
      expect(s.body('DELETE', 'trackfile/bulk'), {
        'trackFileIds': [4, 5],
      });
      await c.editMany([1, 2], {'metadataProfileId': 2, 'monitorNewItems': 'new'});
      expect(s.body('PUT', 'artist/editor'), {
        'artistIds': [1, 2],
        'metadataProfileId': 2,
        'monitorNewItems': 'new',
      });
      await c.deleteMany([1], deleteFiles: false, addExclusion: true);
      expect(s.body('DELETE', 'artist/editor'), {
        'artistIds': [1],
        'deleteFiles': false,
        'addImportListExclusion': true,
      });
      await c.releasesForAlbum(3);
      expect(s.sent('GET', 'release').single.query, {'albumId': '3'});
      await c.renamePreview(1);
      expect(s.sent('GET', 'rename').single.query, {'artistId': '1'});
    });

    test('an edit sends the artist back whole, moving its files if asked', () async {
      final s = _Lidarr();
      final c = _client(s);
      final raw = await c.titleRaw(1);
      raw['metadataProfileId'] = 2;
      await c.updateTitle(raw, moveFiles: true);
      final put = s.sent('PUT', 'artist/1').single;
      expect(put.query, {'moveFiles': 'true'});
      expect((put.body! as Map)['metadataProfileId'], 2);
      expect((put.body! as Map)['artistName'], 'Portishead');
    });

    test('a saved artist\'s pictures come from Lidarr, an album\'s from the web', () {
      final c = _client(_Lidarr());
      final a = ArrArtist.fromJson(_map('lidarr_artist1'));
      // Lidarr's "remote" link here is a path on its own disk.
      expect(
        a.images.firstWhere((i) => i.coverType == 'poster').remoteUrl,
        startsWith('/config/'),
      );
      expect(
        c.imageUrl(a.images, 'poster', width: 900),
        startsWith('http://lidarr:8686/MediaCover/1/poster.jpg'),
      );
      final album = ArrAlbum.fromJson(_list('lidarr_albums').first);
      expect(c.imageUrl(album.images, 'cover'), startsWith('https://'));
      expect(c.webUrl(a.foreignArtistId), 'http://lidarr:8686/artist/${a.foreignArtistId}');
    });

    test('pictures at the size they are drawn, as the apps\' own pages ask', () {
      // The app's copies: posters at 250 and 500, backdrops at 180 and 360.
      const poster = '/sonarr/MediaCover/12/poster.jpg?lastWrite=6393';
      expect(sizedLocalImageUrl(poster, 'poster', 120),
          '/sonarr/MediaCover/12/poster-250.jpg?lastWrite=6393');
      expect(sizedLocalImageUrl(poster, 'poster', 342),
          '/sonarr/MediaCover/12/poster-500.jpg?lastWrite=6393');
      expect(sizedLocalImageUrl(poster, 'poster', 780), poster);
      expect(sizedLocalImageUrl('/MediaCover/1/fanart.jpg', 'fanart', 360),
          '/MediaCover/1/fanart-360.jpg');
      expect(sizedLocalImageUrl('/MediaCover/1/fanart.jpg', 'fanart', 1280),
          '/MediaCover/1/fanart.jpg');
      expect(sizedLocalImageUrl('/MediaCover/1/banner.jpg', 'banner', 60),
          '/MediaCover/1/banner-70.jpg');
      // Only the picture asked for, and nothing Lidarr keeps one size of.
      expect(sizedLocalImageUrl('/MediaCover/1/clearlogo.png', 'poster', 300),
          '/MediaCover/1/clearlogo.png');
      expect(sizedLocalImageUrl('/MediaCover/Albums/1/cover.jpg', 'cover', 100),
          '/MediaCover/Albums/1/cover.jpg');
      // The Cover Art Archive's 250, 500 and 1200, through Lidarr's cache.
      const cover =
          'https://images.lidarr.audio/cache/https://coverartarchive.org/release/23d7/650-1200.jpg';
      expect(sizedImageUrl(cover, 120), cover.replaceFirst('-1200', '-250'));
      expect(sizedImageUrl(cover, 342), cover.replaceFirst('-1200', '-500'));
      expect(sizedImageUrl(cover, 900), cover);
      // An artist's poster on the grid, as Lidarr serves it.
      final c = _client(_Lidarr());
      final a = ArrArtist.fromJson(_map('lidarr_artist1'));
      expect(c.imageUrl(a.images, 'poster', width: 342),
          startsWith('http://lidarr:8686/MediaCover/1/poster-500.jpg?lastWrite='));
    });

    test('whether Lidarr renames, from its own setting', () async {
      final on = _Lidarr({'config/naming': () => {'renameTracks': true}});
      expect(await _client(on).renamingOn(), isTrue);
      final off = _Lidarr({
        'config/naming': () => {'renameTracks': false, 'renameMovies': true},
      });
      expect(await _client(off).renamingOn(), isFalse);
    });

    test('Lidarr alone opens the Manage section', () {
      final c = ProviderContainer(
        overrides: [
          sonarrClientProvider.overrideWithValue(null),
          radarrClientProvider.overrideWithValue(null),
          lidarrClientProvider.overrideWithValue(_client(_Lidarr())),
        ],
      );
      addTearDown(c.dispose);
      expect(c.read(arrConfiguredProvider), isTrue);
      expect(c.read(arrLibraryKindsProvider), [ArrKind.lidarr]);
    });

    test('the artist Lidarr has for a MusicBrainz id, by that id', () async {
      final s = _Lidarr({'artist': () => _list('lidarr_artists')});
      final c = _client(s);
      final found = await c.artistByMbId('8F6BD1E4-FBE1-4F50-AA9B-94C450EC0F11');
      expect(found?.name, 'Portishead');
      expect(await c.artistByMbId('00000000-0000-0000-0000-000000000000'), isNull);
    });
  });

  group('an artist\'s albums, laid out', () {
    test('by kind in Lidarr\'s order, the newest first', () {
      ArrAlbum al(int id, String type, int? year) => ArrAlbum(
        id: id,
        artistId: 1,
        title: '$id',
        albumType: type,
        releaseDate: year == null ? null : DateTime(year),
      );
      final groups = arrAlbumGroups([
        al(1, 'Single', 2001),
        al(2, 'Album', 1994),
        al(3, 'Album', 2008),
        al(4, 'Album', null),
        al(5, 'Audiobook', 2010),
        al(6, 'EP', 1999),
      ]);
      expect([for (final g in groups) g.$1], ['Album', 'EP', 'Single', 'Other']);
      expect([for (final a in groups.first.$2) a.id], [3, 2, 4]);
      expect([for (final a in groups.last.$2) a.id], [5]);
    });

    test('a track\'s length as a player shows it', () {
      expect(arrTrackLength(const Duration(seconds: 282)), '4:42');
      expect(arrTrackLength(const Duration(seconds: 61)), '1:01');
      expect(arrTrackLength(const Duration(hours: 1, minutes: 2, seconds: 5)), '1:02:05');
    });

    test('the library on show is the one picked while it\'s connected', () {
      const all = [ArrKind.radarr, ArrKind.sonarr, ArrKind.lidarr];
      expect(arrShownLibrary(all, ArrKind.lidarr), ArrKind.lidarr);
      expect(arrShownLibrary(const [ArrKind.lidarr], ArrKind.radarr), ArrKind.lidarr);
      expect(arrShownLibrary(const [ArrKind.radarr], ArrKind.lidarr), ArrKind.radarr);
      expect(arrShownLibrary(const [], ArrKind.lidarr), isNull);
    });
  });

  group('Play opens the artist in Jellyfin', () {
    test('found by its MusicBrainz id, as a music artist', () async {
      final jf = _Jellyfin();
      final c = ProviderContainer(
        overrides: [
          sessionControllerProvider.overrideWith(
            () => _Signed(
              const Session(
                baseUrl: 'http://jf',
                accessToken: 't',
                userId: 'u',
                userName: 'rig',
              ),
            ),
          ),
          jellyfinClientProvider.overrideWithValue(
            JellyfinClient(deviceId: 'd', httpClient: Dio()..httpClientAdapter = jf),
          ),
        ],
      );
      addTearDown(c.dispose);
      await c.read(sessionControllerProvider.future);
      final k = arrLibraryKeyOfArtist(ArrArtist.fromJson(_map('lidarr_artist1')));
      final sub = c.listen(arrLibraryItemProvider(k), (_, _) {});
      addTearDown(sub.close);
      expect(await c.read(arrLibraryItemProvider(k).future), 'jf-portishead');
      expect(jf.asked.first['IncludeItemTypes'], 'MusicArtist');
      expect(k.onDisk, isTrue);

      // Another artist of the same name isn't it.
      final other = arrLibraryKeyOfArtist(
        ArrArtist.fromJson({
          ..._map('lidarr_artist1'),
          'foreignArtistId': '11111111-1111-1111-1111-111111111111',
          'statistics': {'trackFileCount': 0},
        }),
      );
      final sub2 = c.listen(arrLibraryItemProvider(other), (_, _) {});
      addTearDown(sub2.close);
      expect(await c.read(arrLibraryItemProvider(other).future), isNull);
    });
  });

  group('Settings', () {
    testWidgets('a Lidarr card that saves its own address and key', (t) async {
      final container = ProviderContainer(
        overrides: [preferencesProvider.overrideWith(() => _FakePrefs(const Prefs()))],
      );
      addTearDown(container.dispose);
      t.view.physicalSize = const Size(900, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(const Color(0xFF8AB4F8)),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ArrSettingsScreen(),
          ),
        ),
      );
      await _settle(t);
      expect(find.text('Lidarr'), findsOneWidget);
      expect(find.text('http://192.168.1.10:8686'), findsOneWidget);
      final fields = find.byType(TextField);
      // Sonarr's two fields, Radarr's, then Lidarr's.
      expect(fields, findsNWidgets(6));
      await t.enterText(fields.at(4), '10.0.0.5:8686');
      await t.enterText(fields.at(5), 'lkey');
      await t.tap(find.text('Save & Test').last);
      await _settle(t);
      // The check is Lidarr's: a test has no network, so it says it failed.
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.textContaining('Lidarr'),
        ),
        findsOneWidget,
      );
      final p = container.read(preferencesProvider).requireValue;
      expect(p.lidarrUrl, 'http://10.0.0.5:8686');
      expect(p.lidarrApiKey, 'lkey');
      expect(p.radarrUrl, isEmpty);
      expect(p.sonarrUrl, isEmpty);
    });
  });

  group('the Music library', () {
    testWidgets('Lidarr alone: its artists, with no switch', (t) async {
      final s = _Lidarr();
      await _open(t, _app(home: const ArrScreen(), lidarr: s));
      expect(find.text('Portishead'), findsOneWidget);
      expect(find.text('Radiohead'), findsOneWidget);
      expect(find.text('11 of 46 tracks'), findsOneWidget);
      expect(find.byType(ArrSwitch<ArrKind>), findsNothing);
      expect(find.text('Search your artists'), findsOneWidget);
      // Add is for artists here.
      expect(find.text('Add'), findsOneWidget);
    });

    testWidgets('by Lidarr\'s sort name, whatever order they come in', (t) async {
      final s = _Lidarr({
        'artist': () => [
          for (final a in _list('lidarr_artists').reversed)
            if (a['artistName'] == 'Radiohead')
              {...a, 'sortName': 'radiohead'}
            else
              {...a, 'artistName': 'The Portishead', 'sortName': 'portishead'},
        ],
      });
      await _open(t, _app(home: const ArrScreen(), lidarr: s));
      final p = t.getTopLeft(find.text('The Portishead'));
      final r = t.getTopLeft(find.text('Radiohead'));
      expect(p.dx < r.dx || p.dy < r.dy, isTrue);
    });

    testWidgets('several at once: Edit with the metadata profile', (t) async {
      final s = _Lidarr();
      await _open(t, _app(home: const ArrScreen(), lidarr: s));
      await t.tap(find.byTooltip('Select'));
      await _settle(t);
      await t.tap(_poster('Portishead'));
      await _settle(t);
      await t.tap(find.byTooltip('Edit'));
      await _settle(t);
      expect(find.text('1 artist'), findsOneWidget);
      expect(find.text('Minimum Availability'), findsNothing);
      expect(find.text('Series Type'), findsNothing);
      final metadata = find.ancestor(
        of: find.text('Metadata Profile'),
        matching: find.byType(Column),
      ).first;
      await t.tap(
        find.descendant(of: metadata, matching: find.text('No Change')),
      );
      await _settle(t);
      await t.tap(find.text('None').last);
      await _settle(t);
      final newAlbums = find.ancestor(
        of: find.text('Monitor New Albums'),
        matching: find.byType(Column),
      ).first;
      await t.ensureVisible(newAlbums);
      await t.tap(
        find.descendant(of: newAlbums, matching: find.text('No Change')),
      );
      await _settle(t);
      await t.tap(find.text('New Releases Only').last);
      await _settle(t);
      await t.tap(find.text('Save'));
      await _settle(t);
      expect(s.body('PUT', 'artist/editor'), {
        'artistIds': [1],
        'metadataProfileId': 2,
        'monitorNewItems': 'new',
      });
    });

    testWidgets('a poster opens the artist\'s page on a phone', (t) async {
      await _open(
        t,
        _app(home: const ArrScreen(), lidarr: _Lidarr()),
        size: const Size(420, 900),
      );
      await t.tap(_poster('Portishead'));
      await _settle(t);
      await t.pump(const Duration(milliseconds: 400));
      await _settle(t);
      expect(find.byType(ArrArtistScreen), findsOneWidget);
      expect(find.byType(ArrScreen, skipOffstage: false), findsOneWidget);
    });

    testWidgets('and in the pane beside the list on a wide window', (t) async {
      await _open(
        t,
        _app(home: const ArrScreen(), lidarr: _Lidarr()),
        size: const Size(1800, 1200),
      );
      await t.tap(_poster('Radiohead'));
      await _settle(t);
      // Beside the grid, in the same screen.
      expect(
        find.descendant(
          of: find.byType(ArrScreen),
          matching: find.byType(ArrArtistScreen),
        ),
        findsOneWidget,
      );
    });

    testWidgets('beside Radarr: Movies and Music on the switch', (t) async {
      await _open(t, _app(home: const ArrScreen(), lidarr: _Lidarr(), radarr: true));
      expect(find.text('Movies'), findsWidgets);
      expect(find.text('Music'), findsOneWidget);
      expect(find.text('Shows'), findsNothing);
      await t.tap(find.text('Music'));
      await _settle(t);
      expect(find.text('Portishead'), findsOneWidget);
    });

    testWidgets('Missing keeps the artists with tracks to find', (t) async {
      final s = _Lidarr({
        'artist': () => [
          for (final a in _list('lidarr_artists'))
            if (a['artistName'] == 'Portishead')
              a
            else
              {
                ...a,
                'statistics': {'trackFileCount': 3, 'trackCount': 3},
              },
        ],
      });
      await _open(t, _app(home: const ArrScreen(), lidarr: s));
      await t.tap(find.byTooltip('Filter'));
      await _settle(t);
      await t.tap(find.text('Missing').last);
      await _settle(t);
      expect(find.text('Portishead'), findsOneWidget);
      expect(find.text('Radiohead'), findsNothing);
    });
  });

  group('an artist\'s page', () {
    testWidgets('its facts and albums, an album opening into its tracks', (
      t,
    ) async {
      final s = _Lidarr();
      await _open(t, _app(home: const ArrArtistScreen(id: 1), lidarr: s));
      expect(find.text('Portishead'), findsWidgets);
      // The metadata profile by name, and the files by tracks.
      expect(find.text('Standard'), findsOneWidget);
      expect(find.text('11 of 46 tracks'), findsOneWidget);
      expect(find.text('35 tracks missing'), findsOneWidget);
      expect(find.text('Dummy'), findsOneWidget);
      // Lidarr's history, by the names the other apps' events have.
      // Each import by its track.
      expect(find.text('Cowboys · Imported · FLAC'), findsOneWidget);
      expect(find.text('Third'), findsOneWidget);
      // Albums alone: no heading says so.
      expect(find.text('Albums'), findsNothing);
      // Closed albums haven't asked for their tracks.
      expect(s.sent('GET', 'track'), isEmpty);
      final row = find.ancestor(
        of: find.text('1997 · 11 of 11 tracks · 2 MB'),
        matching: find.byType(ExpansionTile),
      );
      expect(row, findsOneWidget);
      await t.ensureVisible(row);
      await t.tap(find.text('1997 · 11 of 11 tracks · 2 MB'));
      await _settle(t);
      expect(s.sent('GET', 'track').single.query, {'albumId': '1'});
      expect(find.text('Cowboys'), findsOneWidget);
      expect(find.text('A1'), findsOneWidget);
      expect(find.text('FLAC'), findsWidgets);
      expect(find.text('4:42'), findsOneWidget);
    });

    testWidgets('a boxed set lists each disc under its number', (t) async {
      final s = _Lidarr();
      await _open(t, _app(home: const ArrArtistScreen(id: 1), lidarr: s));
      await t.ensureVisible(find.text('Third'));
      await t.tap(find.text('Third'));
      await _settle(t);
      expect(s.sent('GET', 'track').single.query, {'albumId': '3'});
      for (final n in [1, 2, 3, 4]) {
        expect(find.text('Disc $n', skipOffstage: false), findsOneWidget);
      }
      // Out, monitored, and no files: missing.
      expect(find.text('Missing', skipOffstage: false), findsWidgets);
    });

    testWidgets('a track\'s file, with its audio', (t) async {
      final s = _Lidarr();
      await _open(t, _app(home: const ArrArtistScreen(id: 1), lidarr: s));
      await t.ensureVisible(find.text('Portishead').last);
      await t.tap(find.text('1997 · 11 of 11 tracks · 2 MB'));
      await _settle(t);
      await t.tap(find.text('Cowboys'));
      await _settle(t);
      expect(find.textContaining('16-bit · 44.1 kHz'), findsOneWidget);
      expect(find.text('Delete File'), findsOneWidget);
    });

    testWidgets('an album\'s bookmark switches it', (t) async {
      final s = _Lidarr();
      await _open(t, _app(home: const ArrArtistScreen(id: 1), lidarr: s));
      final third = find.ancestor(
        of: find.text('Third'),
        matching: find.byType(ExpansionTile),
      );
      await t.ensureVisible(third);
      await t.tap(
        find.descendant(of: third, matching: find.byTooltip('Unmonitor')),
      );
      await _settle(t);
      expect(s.body('PUT', 'album/monitor'), {
        'albumIds': [3],
        'monitored': false,
      });
    });

    testWidgets('an album\'s Interactive Search asks for that album', (t) async {
      final s = _Lidarr();
      await _open(t, _app(home: const ArrArtistScreen(id: 1), lidarr: s));
      final third = find.ancestor(
        of: find.text('Third'),
        matching: find.byType(ExpansionTile),
      );
      await t.ensureVisible(third);
      await t.tap(
        find.descendant(of: third, matching: find.byTooltip('Album Actions')),
      );
      await _settle(t);
      await t.tap(find.text('Interactive Search'));
      await _settle(t);
      expect(_visited.single, '/arr/releases?album=3');
      expect(s.sent('GET', 'release').single.query, {'albumId': '3'});
      // Named in the bar by its artist and title.
      expect(find.text('Portishead · Third'), findsOneWidget);
    });

    testWidgets('Monitoring: Latest Album and New Releases Only in one call', (
      t,
    ) async {
      final s = _Lidarr();
      await _open(t, _app(home: const ArrArtistScreen(id: 1), lidarr: s));
      await t.tap(_button('Monitoring'));
      await _settle(t);
      expect(find.text('3 of 3 albums are monitored now'), findsOneWidget);
      await t.tap(find.text('Keep As They Are'));
      await _settle(t);
      await t.tap(find.text('Latest Album').last);
      await _settle(t);
      await t.tap(find.text('All Albums').last);
      await _settle(t);
      await t.tap(find.text('New Releases Only').last);
      await _settle(t);
      expect(
        find.textContaining("as new as the artist's latest"),
        findsOneWidget,
      );
      await t.tap(find.text('Save'));
      await _settle(t);
      expect(s.body('POST', 'albumstudio'), {
        'artist': [
          {'id': 1, 'monitored': true},
        ],
        'monitoringOptions': {'monitor': 'latest'},
        'monitorNewItems': 'new',
      });
    });

    testWidgets('searches: the artist\'s monitored albums, or one album', (t) async {
      final s = _Lidarr();
      await _open(t, _app(home: const ArrArtistScreen(id: 1), lidarr: s));
      await t.tap(_button('Search Monitored'));
      await _settle(t);
      final third = find.ancestor(
        of: find.text('Third'),
        matching: find.byType(ExpansionTile),
      );
      await t.ensureVisible(third);
      await t.tap(
        find.descendant(of: third, matching: find.byTooltip('Search Album')),
      );
      await _settle(t);
      expect([for (final a in s.sent('POST', 'command')) a.body], [
        {'name': 'ArtistSearch', 'artistId': 1},
        {
          'name': 'AlbumSearch',
          'albumIds': [3],
        },
      ]);
    });

    testWidgets('an album still to come says when, and its tracks aren\'t missing', (
      t,
    ) async {
      final s = _Lidarr({
        'album': () => [
          {
            ..._list('lidarr_albums').firstWhere((a) => a['id'] == 3),
            'releaseDate': '2099-03-05T00:00:00Z',
          },
        ],
        'track': () => [
          for (final t in _list('lidarr_tracks_album3'))
            if (t['mediumNumber'] == 1) t,
        ],
      });
      await _open(t, _app(home: const ArrArtistScreen(id: 1), lidarr: s));
      // The day it's out, not a year as if it were.
      expect(find.textContaining(RegExp(r'^Out .*2099 · ')), findsOneWidget);
      expect(find.textContaining(RegExp(r'^2099 · ')), findsNothing);
      // The only album: open already.
      expect(find.text('Not Released'), findsWidgets);
      expect(find.text('Missing'), findsNothing);
    });

    testWidgets('Monitoring: new albums alone leaves the albums be', (t) async {
      final s = _Lidarr();
      await _open(t, _app(home: const ArrArtistScreen(id: 1), lidarr: s));
      await t.tap(_button('Monitoring'));
      await _settle(t);
      await t.tap(find.text('All Albums').last);
      await _settle(t);
      await t.tap(find.text('None').last);
      await _settle(t);
      await t.tap(find.text('Save'));
      await _settle(t);
      expect(s.body('POST', 'albumstudio'), {
        'artist': [
          {'id': 1, 'monitored': true},
        ],
        'monitorNewItems': 'none',
      });
    });

    testWidgets('Monitoring: None stops the artist too', (t) async {
      final s = _Lidarr();
      await _open(t, _app(home: const ArrArtistScreen(id: 1), lidarr: s));
      await t.tap(_button('Monitoring'));
      await _settle(t);
      await t.tap(find.text('Keep As They Are'));
      await _settle(t);
      await t.tap(find.text('None').last);
      await _settle(t);
      await t.tap(find.text('Save'));
      await _settle(t);
      expect(s.body('POST', 'albumstudio'), {
        'artist': [
          {'id': 1, 'monitored': false},
        ],
        'monitoringOptions': {'monitor': 'none'},
        'monitorNewItems': 'all',
      });
    });

    testWidgets('Edit: the metadata profile, sent with the whole artist', (
      t,
    ) async {
      final s = _Lidarr();
      await _open(t, _app(home: const ArrArtistScreen(id: 1), lidarr: s));
      await t.tap(_button('Edit'));
      await _settle(t);
      // On the page, and in the dialog over it.
      expect(find.text('Metadata Profile'), findsNWidgets(2));
      // Neither a show's nor a movie's own fields.
      expect(find.text('Series Type'), findsNothing);
      expect(find.text('Minimum Availability'), findsNothing);
      // Its monitoring is under Monitoring, as a show's is.
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(SwitchListTile),
        ),
        findsNothing,
      );
      await t.tap(find.text('Standard').last);
      await _settle(t);
      await t.tap(find.text('None').last);
      await _settle(t);
      await t.tap(find.text('Save'));
      await _settle(t);
      final put = s.sent('PUT', 'artist/1').single;
      expect((put.body! as Map)['metadataProfileId'], 2);
      expect((put.body! as Map)['foreignArtistId'], '8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11');
    });

    testWidgets('Delete takes the artist out of Lidarr, and leaves', (t) async {
      final s = _Lidarr();
      await _open(t, _app(home: const Text('the list'), lidarr: s));
      _router.push('/arr/artist/1');
      await _settle(t);
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(_button('More'));
      await _settle(t);
      await t.tap(find.text('Delete').last);
      await _settle(t);
      await t.tap(find.text('Delete Files'));
      await _settle(t);
      await t.tap(find.widgetWithText(FilledButton, 'Delete'));
      await _settle(t);
      expect(s.sent('DELETE', 'artist/1').single.query, {
        'deleteFiles': 'true',
        'addImportListExclusion': 'false',
      });
      await t.pump(const Duration(milliseconds: 400));
      await _settle(t);
      expect(find.text('the list'), findsOneWidget);
      expect(find.byType(ArrArtistScreen), findsNothing);
    });

    testWidgets('Edit: profiles that arrive after the artist still show', (
      t,
    ) async {
      // Lidarr is slow with its profiles: the dialog is open, with the
      // artist in it, before they come.
      final s = _Lidarr(const {}, const {
        'metadataprofile': Duration(milliseconds: 1500),
      });
      await _open(t, _app(home: const ArrArtistScreen(id: 1), lidarr: s));
      await t.tap(_button('Edit'));
      await _settle(t);
      final field = find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(DropdownButtonFormField<int>),
      );
      expect(field, findsNWidgets(2));
      expect(
        find.descendant(of: field.last, matching: find.text('Standard')),
        findsNothing,
      );
      await t.pump(const Duration(milliseconds: 1600));
      await _settle(t);
      // Its value set once the list is there, not left blank.
      expect(
        find.descendant(of: field.last, matching: find.text('Standard')),
        findsOneWidget,
      );
    });

    testWidgets('on a TV: no file deleting, renaming or Open in Lidarr', (
      t,
    ) async {
      isTvDevice = true;
      addTearDown(() => isTvDevice = false);
      final s = _Lidarr();
      await _open(
        t,
        _app(home: const ArrArtistScreen(id: 1), lidarr: s),
        size: const Size(1920, 2400),
      );
      await t.tap(_button('More'));
      await _settle(t);
      expect(find.text('Refresh & Scan'), findsOneWidget);
      expect(find.text('Rename Files'), findsNothing);
      expect(find.text('Open in Lidarr'), findsNothing);
      await t.tapAt(const Offset(5, 5));
      await _settle(t);
      final first = find.ancestor(
        of: find.text('1997 · 11 of 11 tracks · 2 MB'),
        matching: find.byType(ExpansionTile),
      );
      await t.ensureVisible(first);
      await t.tap(
        find.descendant(of: first, matching: find.byTooltip('Album Actions')),
      );
      await _settle(t);
      expect(find.text('Interactive Search'), findsOneWidget);
      expect(find.text('Delete Album Files'), findsNothing);
    });

    testWidgets('off a TV the same menus have them', (t) async {
      // One of the artist's files is another album's: it stays.
      final s = _Lidarr({
        'trackfile': () => [
          ..._list('lidarr_trackfiles'),
          {..._list('lidarr_trackfiles').first, 'id': 99, 'albumId': 3},
        ],
      });
      await _open(t, _app(home: const ArrArtistScreen(id: 1), lidarr: s));
      await t.tap(_button('More'));
      await _settle(t);
      expect(find.text('Rename Files'), findsOneWidget);
      expect(find.text('Open in Lidarr'), findsOneWidget);
      await t.tapAt(const Offset(5, 5));
      await _settle(t);
      final first = find.ancestor(
        of: find.text('1997 · 11 of 11 tracks · 2 MB'),
        matching: find.byType(ExpansionTile),
      );
      await t.ensureVisible(first);
      // Open, so its tracks are on show.
      await t.tap(find.text('1997 · 11 of 11 tracks · 2 MB'));
      await _settle(t);
      expect(s.sent('GET', 'track'), hasLength(1));
      await t.tap(
        find.descendant(of: first, matching: find.byTooltip('Album Actions')),
      );
      await _settle(t);
      expect(find.text('Delete Album Files'), findsOneWidget);
      await t.tap(find.text('Delete Album Files'));
      await _settle(t);
      await t.tap(find.widgetWithText(FilledButton, 'Delete'));
      await _settle(t);
      final gone = s.body('DELETE', 'trackfile/bulk')['trackFileIds'] as List;
      expect(gone, hasLength(11));
      expect(gone, isNot(contains(99)));
      // The files and the open album's tracks are asked for again.
      expect(s.sent('GET', 'trackfile'), hasLength(2));
      expect(s.sent('GET', 'track'), hasLength(2));
    });

    testWidgets('Play, where Jellyfin has the artist, opens it there', (t) async {
      final jf = _Jellyfin();
      await _open(
        t,
        _app(
          home: const ArrArtistScreen(id: 1),
          lidarr: _Lidarr(),
          jellyfin: jf,
          session: const Session(
            baseUrl: 'http://jf',
            accessToken: 't',
            userId: 'u',
            userName: 'rig',
          ),
        ),
      );
      expect(_button('Play'), findsOneWidget);
      expect(_button('Watch'), findsNothing);
      await t.tap(_button('Play'));
      await _settle(t);
      // On its albums, as the Music library opens an artist.
      expect(_visited, ['/artist jf-portishead']);
    });
  });
}

/// Keeps each request's options and answers with nothing.
class _Capture implements HttpClientAdapter {
  final void Function(RequestOptions o) seen;
  _Capture(this.seen);

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    seen(o);
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
