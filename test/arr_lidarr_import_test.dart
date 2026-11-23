import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fathom/api/arr_client.dart';
import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/models/arr.dart';
import 'package:fathom/models/session.dart';
import 'package:fathom/screens/arr_detail_screens.dart';
import 'package:fathom/screens/arr_import_screen.dart';
import 'package:fathom/screens/arr_screen.dart';
import 'package:fathom/state/arr_providers.dart';
import 'package:fathom/state/preferences.dart';
import 'package:fathom/state/session_controller.dart';
import 'package:fathom/theme/app_theme.dart';
import 'package:fathom/widgets/arr_file_edit.dart';
import 'package:fathom/widgets/detail_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// Manual Import for Lidarr: a download it couldn't import (it knew the
// artist, not the album), and files in a folder. What Lidarr is told, what
// it says back, and the page that puts the two together. The answers are
// Lidarr 3.1.6's own, saved from the rig.

Object? _fixture(String name) =>
    jsonDecode(File('test/fixtures/arr/$name.json').readAsStringSync());

List<Map<String, dynamic>> _list(String name) => [
  for (final m in _fixture(name)! as List) Map<String, dynamic>.from(m as Map),
];

ArrImportItem _item(String name, [int at = 0]) =>
    ArrImportItem.fromJson(ArrKind.lidarr, _list(name)[at]);

typedef _Asked = ({
  String method,
  String path,
  Map<String, String> query,
  Object? body,
});

class _Lidarr implements HttpClientAdapter {
  final List<_Asked> asked = [];
  _Lidarr();
  final Map<String, Object? Function()> answers = const {};

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
            ('GET', 'manualimport') when q['downloadId'] != null =>
              _list('lidarr_manualimport_download'),
            ('GET', 'manualimport') => _list('lidarr_manualimport_folder'),
            ('POST', 'manualimport') => _list('lidarr_manualimport_recheck'),
            ('GET', 'artist') => _list('lidarr_artists'),
            ('GET', 'album') => _list('lidarr_albums'),
            ('GET', 'track') when q['albumReleaseId'] != null =>
              _list('lidarr_tracks_album1'),
            ('GET', 'track') when q['albumId'] == '3' =>
              _list('lidarr_tracks_album3'),
            ('GET', 'track') => _list('lidarr_tracks_album1'),
            ('GET', 'qualitydefinition') => [
              {
                'quality': {'id': 0, 'name': 'Unknown'},
                'weight': 1,
              },
              {
                'quality': {'id': 4, 'name': 'MP3-320'},
                'weight': 10,
              },
              {
                'quality': {'id': 6, 'name': 'FLAC'},
                'weight': 23,
              },
            ],
            ('GET', 'queue') => {
              'totalRecords': 1,
              'records': [
                {
                  ...Map<String, dynamic>.from(
                    ((_fixture('lidarr_queue')! as Map)['records'] as List)
                        .single as Map,
                  ),
                },
              ],
            },
            ('GET', 'queue/status') => {'totalCount': 1, 'warnings': true},
            ('GET', 'artist/1') => (_fixture('lidarr_artist1')! as Map),
            ('GET', 'filesystem') => {
              'directories': [
                {'name': 'downloads', 'path': '/downloads/'},
              ],
            },
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

Widget _app(_Lidarr lidarr, {required Widget home, bool sonarr = false}) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, _) => home),
      GoRoute(
        path: '/arr/import',
        builder: (_, s) {
          _visited.add(s.uri.toString());
          return ArrImportScreen(
            target: ArrImportTarget.fromQuery(s.uri.queryParameters),
          );
        },
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      lidarrClientProvider.overrideWithValue(_client(lidarr)),
      sonarrClientProvider.overrideWithValue(
        sonarr
            ? SonarrClient('http://s', 'k', dio: Dio()..httpClientAdapter = _Lidarr())
            : null,
      ),
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
  Size size = const Size(1000, 1400),
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(app);
  await _settle(t);
}

const _download = ArrImportTarget.download(
  ArrKind.lidarr,
  'Blackhole_Portishead-Third-2008-WEB-MP3-V0-GRP_639309859101222853',
  title: 'Portishead-Third-2008-WEB-MP3-V0-GRP',
);

void main() {
  setUp(_visited.clear);

  group('Lidarr\'s files, read', () {
    test('a download it knew the artist of, and not the album', () {
      final i = _item('lidarr_manualimport_download');
      expect(i.artistId, 1);
      expect(i.artistName, 'Portishead');
      expect(i.albumId, isNull);
      expect(i.albumReleaseId, isNull, reason: 'Lidarr sends 0 for none');
      expect(i.tracks, isEmpty);
      expect(i.titleId, 1);
      expect(i.gap, ArrImportGap.album);
      expect(i.rejections.single, startsWith("Couldn't find similar album"));
    });

    test('a file it matched: album, edition, track, quality', () {
      final i = _item('lidarr_manualimport_folder');
      expect(i.albumTitle, 'Portishead');
      expect(i.albumReleaseId, 1);
      expect(i.tracks.single.title, isNotEmpty);
      expect(i.qualityName, 'FLAC');
      // No languages to choose: a music file is ready without them.
      expect(i.gap, isNull);
    });

    test('a file with an album and no tracks waits for them', () {
      final i = _item(
        'lidarr_manualimport_download',
      ).copyWith(albumId: 3, albumReleaseId: 37);
      expect(i.gap, ArrImportGap.tracks);
      expect(
        i.copyWith(artistId: null).gap,
        ArrImportGap.title,
      );
    });

    test('what Lidarr\'s check takes, and the command', () {
      final i = _item('lidarr_manualimport_folder');
      final again = i.toReprocessJson();
      expect(again['artistId'], 1);
      expect(again['albumId'], 1);
      expect(again['albumReleaseId'], 1);
      expect(again['trackIds'], [for (final t in i.tracks) t.id]);
      expect(again.containsKey('languages'), isFalse);
      expect(again.containsKey('seriesId'), isFalse);
      final cmd = i.toCommandJson();
      // Lidarr's ManualImportFile, field for field.
      expect(cmd.keys.toSet(), {
        'path',
        'artistId',
        'albumId',
        'albumReleaseId',
        'trackIds',
        'quality',
        'releaseGroup',
        'indexerFlags',
        'downloadId',
        'disableReleaseSwitching',
      });
      expect(cmd['path'], i.path);
    });

    test('a check\'s answer: the edition and tracks it worked out', () {
      final before = _item('lidarr_manualimport_download').copyWith(
        albumId: 3,
        albumTitle: null,
      );
      final r = _item('lidarr_manualimport_recheck');
      final after = before.mergeReprocessed(r);
      expect(after.albumReleaseId, 37);
      expect(after.tracks.single.id, 393);
      expect(after.albumTitle, 'Third');
      expect(after.rejections, r.rejections);
      expect(after.gap, isNull);
    });

    test('left to Lidarr, the album it worked out is taken', () {
      // Lidarr's answer to a file sent with only its artist (seen on the
      // rig): the album as an object, no albumId of its own.
      final asked = _item('lidarr_manualimport_folder', 2).copyWith(
        albumId: null,
        albumTitle: null,
        albumReleaseId: null,
        tracks: const [],
      );
      expect(asked.gap, ArrImportGap.album);
      final r = ArrImportItem.fromJson(ArrKind.lidarr, {
        ..._list('lidarr_manualimport_folder')[2],
        'albumId': null,
      });
      final after = asked.mergeReprocessed(r);
      expect(after.albumId, 1);
      expect(after.albumReleaseId, 1);
      expect(after.tracks, isNotEmpty);
      expect(after.gap, isNull);
    });

    test('tracks picked by hand outlast Lidarr\'s check', () {
      final i = _item('lidarr_manualimport_folder');
      const mine = ArrTrack(id: 9, albumId: 1, title: 'Mine');
      final picked = i.copyWith(tracks: const [mine]);
      final r = _item('lidarr_manualimport_folder');
      expect(picked.mergeReprocessed(r, keepTracks: true).tracks.single.id, 9);
      expect(picked.mergeReprocessed(r).tracks.single.id, r.tracks.single.id);
    });

    test('no edition matched yet: not ready, as Lidarr couldn\'t import it', () {
      final i = _item('lidarr_manualimport_folder');
      expect(i.copyWith(albumReleaseId: null).gap, ArrImportGap.album);
    });

    test('the file\'s own replace setting goes back with a check', () {
      final i = _item('lidarr_manualimport_folder');
      expect(i.replaceExistingFiles, isNotNull);
      expect(
        i.toReprocessJson()['replaceExistingFiles'],
        i.replaceExistingFiles,
      );
    });

    test('a new artist or album starts the rest over', () {
      final i = _item('lidarr_manualimport_folder');
      const third = ArrAlbum(id: 3, artistId: 1, title: 'Third');
      final moved = const ArrFileChanges(album: third).applyTo(i);
      expect(moved.albumId, 3);
      expect(moved.albumTitle, 'Third');
      expect(moved.albumReleaseId, isNull);
      expect(moved.tracks, isEmpty);
      const other = ArrArtist(id: 2, name: 'Radiohead');
      final elsewhere = const ArrFileChanges(artist: other).applyTo(i);
      expect(elsewhere.artistId, 2);
      expect(elsewhere.artistName, 'Radiohead');
      expect(elsewhere.albumId, isNull);
      expect(elsewhere.tracks, isEmpty);
      const track = ArrTrack(id: 9, albumId: 1, title: 'Wandering Star');
      expect(
        const ArrFileChanges(tracks: [track]).applyTo(i).tracks.single.id,
        9,
      );
    });
  });

  group('the page', () {
    testWidgets('a stuck download: choose the album, Lidarr checks, Import', (
      t,
    ) async {
      final s = _Lidarr();
      await _open(t, _app(s, home: const ArrImportScreen(target: _download)));
      expect(
        s.sent('GET', 'manualimport').single.query['downloadId'],
        _download.downloadId,
      );
      expect(find.text('Portishead'), findsOneWidget);
      expect(find.text('Choose the album'), findsOneWidget);
      await t.tap(find.byTooltip('Edit File'));
      await _settle(t);
      // The music file's fields, not a show's or a movie's.
      expect(find.text('Artist'), findsOneWidget);
      expect(find.text('Album'), findsOneWidget);
      expect(find.text('Languages'), findsNothing);
      expect(find.text('Season'), findsNothing);
      await t.tap(find.byType(DropdownButtonFormField<int>).first);
      await _settle(t);
      await t.tap(find.text('Third (2008)').last);
      await _settle(t);
      await t.tap(find.text('Save'));
      await _settle(t);
      final again = (s.sent('POST', 'manualimport').single.body! as List)
          .single as Map;
      expect(again['artistId'], 1);
      expect(again['albumId'], 3);
      expect(again['trackIds'], isEmpty);
      // What Lidarr worked out, and what it still says.
      expect(find.text('Portishead · Third · Silence'), findsOneWidget);
      expect(find.textContaining('Album match is not close enough'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, 'Import'));
      await _settle(t);
      final cmd = s.sent('POST', 'command').single.body! as Map;
      expect(cmd['name'], 'ManualImport');
      expect(cmd['importMode'], 'auto');
      final file = (cmd['files'] as List).single as Map;
      expect(file['albumId'], 3);
      expect(file['albumReleaseId'], 37);
      expect(file['trackIds'], [393]);
    });

    testWidgets('tracks are chosen from the matched edition\'s, and stand', (
      t,
    ) async {
      final s = _Lidarr();
      await _open(
        t,
        _app(
          s,
          home: const ArrImportScreen(
            target: ArrImportTarget.folder(ArrKind.lidarr, '/downloads/x'),
          ),
        ),
      );
      await t.tap(find.byTooltip('Edit File').first);
      await _settle(t);
      expect(find.text('Tracks'), findsOneWidget);
      // The edition Lidarr matched the file to, not the album's set one.
      expect(s.sent('GET', 'track').single.query, {'albumReleaseId': '1'});
      // The field says the file's track now; pressing it opens the list.
      await t.tap(find.text('A1'));
      await _settle(t);
      await t.tap(find.textContaining('A2 · '));
      await _settle(t);
      await t.tap(find.text('Done'));
      await _settle(t);
      await t.tap(find.text('Save'));
      await _settle(t);
      // Lidarr's check would put its own tracks back: it isn't asked.
      expect(s.sent('POST', 'manualimport'), isEmpty);
      await t.tap(find.text('Copy Files'));
      await _settle(t);
      await t.tap(find.widgetWithText(FilledButton, 'Import'));
      await _settle(t);
      final cmd = s.sent('POST', 'command').single.body! as Map;
      final first = (cmd['files'] as List).first as Map;
      expect((first['trackIds'] as List), hasLength(2));
    });

    testWidgets('the queue offers Manual Import for Lidarr\'s stuck download', (
      t,
    ) async {
      final s = _Lidarr();
      await _open(t, _app(s, home: const ArrScreen()));
      await t.tap(find.widgetWithText(Tab, 'Activity'));
      await _settle(t);
      await t.pump(const Duration(milliseconds: 400));
      await _settle(t);
      await t.tap(find.text('Manual Import'));
      await _settle(t);
      expect(_visited.single, contains('app=lidarr'));
      expect(_visited.single, contains('download='));
    });

    testWidgets('an artist\'s More has Manual Import for its folder', (t) async {
      final s = _Lidarr();
      await _open(t, _app(s, home: const ArrArtistScreen(id: 1)));
      await t.tap(
        find.byWidgetPredicate(
          (w) => w is HeaderActionButton && w.tooltip == 'More',
        ),
      );
      await _settle(t);
      await t.tap(find.text('Manual Import'));
      await _settle(t);
      expect(
        _visited.single,
        '/arr/import?app=lidarr&folder=%2Fmusic%2FPortishead',
      );
      // Imported: the artist's page asks Lidarr again for what it has now.
      final before = s.sent('GET', 'artist/1').length;
      await t.tap(find.text('Copy Files'));
      await _settle(t);
      await t.tap(find.widgetWithText(FilledButton, 'Import'));
      await _settle(t);
      await t.pump(const Duration(milliseconds: 400));
      await _settle(t);
      expect(s.sent('GET', 'artist/1').length, greaterThan(before));
    });

    testWidgets('the folder dialog names Lidarr beside the others', (t) async {
      final s = _Lidarr();
      await _open(
        t,
        _app(
          s,
          sonarr: true,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => arrOpenFolderImport(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await _settle(t);
      expect(find.text('Sonarr'), findsOneWidget);
      expect(find.text('Lidarr'), findsOneWidget);
      await t.tap(find.text('Lidarr'));
      await _settle(t);
      expect(s.sent('GET', 'filesystem'), isNotEmpty);
    });
  });

  test('an artist\'s own files are asked for by its artist id', () async {
    final s = _Lidarr();
    await _client(s).importFiles(titleId: 1, filterExisting: false);
    expect(s.sent('GET', 'manualimport').single.query, {
      'artistId': '1',
      'filterExistingFiles': 'false',
    });
  });

  test('the import page\'s address keeps Lidarr', () {
    final back = ArrImportTarget.fromQuery(
      Uri.parse(_download.location).queryParameters,
    )!;
    expect(back.kind, ArrKind.lidarr);
    expect(back.downloadId, _download.downloadId);
  });
}
