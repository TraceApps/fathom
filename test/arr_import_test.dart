import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fathom/api/arr_client.dart';
import 'package:fathom/models/arr.dart';
import 'package:fathom/state/arr_providers.dart';
import 'package:fathom/state/preferences.dart';
import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/widgets/arr_actions.dart';
import 'package:fathom/widgets/arr_file_edit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Recorded from Sonarr 4.0.20 and Radarr 6.4.4 with three finished
// downloads each app wouldn't import on its own: a show neither app has, a
// file worse than the one in the library, and one the other app's.
dynamic _fixture(String name) =>
    jsonDecode(File('test/fixtures/arr/$name.json').readAsStringSync());

List<ArrImportItem> _items(ArrKind kind, String name) => [
  for (final m in _fixture(name) as List)
    ArrImportItem.fromJson(kind, Map<String, dynamic>.from(m)),
];

/// Answers every request with [reply] and keeps what was sent.
class _Recorder implements HttpClientAdapter {
  final Object? Function(RequestOptions o) reply;
  final List<RequestOptions> sent = [];
  _Recorder(this.reply);

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    sent.add(o);
    return ResponseBody.fromString(
      jsonEncode(reply(o)),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

(SonarrClient, _Recorder) _sonarr(Object? Function(RequestOptions) reply) {
  final r = _Recorder(reply);
  return (SonarrClient('http://s', 'k', dio: Dio()..httpClientAdapter = r), r);
}

(RadarrClient, _Recorder) _radarr(Object? Function(RequestOptions) reply) {
  final r = _Recorder(reply);
  return (RadarrClient('http://r', 'k', dio: Dio()..httpClientAdapter = r), r);
}

void main() {
  group('queue', () {
    test('asks for downloads the app could not match, as the apps do', () async {
      final (s, sr) = _sonarr((_) => _fixture('sonarr_queue'));
      final items = await s.queue();
      expect(sr.sent.single.queryParameters['includeUnknownSeriesItems'], true);
      // The unmatched show is there, with no show of its own.
      final unknown = items.firstWhere((i) => i.title.startsWith('Totally'));
      expect(unknown.seriesId, isNull);
      expect(unknown.trackedDownloadState, 'importBlocked');

      final (r, rr) = _radarr((_) => _fixture('radarr_queue'));
      await r.queue();
      expect(rr.sent.single.queryParameters['includeUnknownMovieItems'], true);
    });

    test('offers Manual Import exactly where the apps do', () async {
      final (s, _) = _sonarr((_) => _fixture('sonarr_queue'));
      final items = await s.queue();
      expect(items, hasLength(3));
      for (final i in items) {
        expect(i.downloadId, isNotEmpty);
        expect(i.canManualImport, isTrue, reason: i.title);
      }
      // Still downloading, or finished without a warning: not offered.
      ArrQueueItem q(Map<String, dynamic> j) => ArrQueueItem.fromJson(
        ArrKind.sonarr,
        {'id': 1, 'title': 't', 'downloadId': 'd', ...j},
      );
      expect(
        q({'status': 'downloading', 'trackedDownloadStatus': 'ok'})
            .canManualImport,
        isFalse,
      );
      expect(
        q({'status': 'completed', 'trackedDownloadStatus': 'ok'})
            .canManualImport,
        isFalse,
      );
      expect(
        q({'status': 'completed', 'trackedDownloadStatus': 'warning'})
            .canManualImport,
        isTrue,
      );
      expect(
        ArrQueueItem.fromJson(ArrKind.sonarr, {
          'id': 1,
          'title': 't',
          'status': 'completed',
          'trackedDownloadStatus': 'warning',
        }).canManualImport,
        isFalse,
        reason: 'nothing to import without a download id',
      );
    });

    test('remove offers what the apps offer', () async {
      ArrQueueItem q(Map<String, dynamic> j) =>
          ArrQueueItem.fromJson(ArrKind.sonarr, {'id': 1, 'title': 't', ...j});
      // Ignore needs a known show; Change Category a client that has one.
      expect(q({}).canIgnore, isFalse);
      expect(q({'seriesId': 2}).canIgnore, isTrue);
      expect(q({}).clientHasPostImportCategory, isFalse);
      expect(
        q({'downloadClientHasPostImportCategory': true})
            .clientHasPostImportCategory,
        isTrue,
      );
      expect(q({'status': 'delay'}).isPending, isTrue);
      expect(q({'status': 'downloadClientUnavailable'}).isPending, isTrue);
      expect(q({'status': 'completed'}).isPending, isFalse);

      final (s, r) = _sonarr((_) => const {});
      await s.removeFromQueue(5, removeFromClient: false, blocklist: false,
          changeCategory: true);
      expect(r.sent.last.queryParameters, {
        'removeFromClient': false,
        'changeCategory': true,
        'blocklist': false,
      });
      // Ignore: leave it in the client, nothing else.
      await s.removeFromQueue(5, removeFromClient: false, blocklist: false);
      expect(r.sent.last.queryParameters,
          {'removeFromClient': false, 'blocklist': false});
      await s.removeManyFromQueue([5, 6], removeFromClient: false,
          blocklist: true, changeCategory: true);
      expect(r.sent.last.queryParameters['changeCategory'], true);
      expect(r.sent.last.data, {'ids': [5, 6]});
    });

    test('shows "&amp;" in a release name as "&"', () {
      final q = ArrQueueItem.fromJson(ArrKind.sonarr, {
        'id': 1,
        'title': 'Law.&amp;.Order.Special.Victims.Unit.S28E01',
      });
      expect(q.title, 'Law.&.Order.Special.Victims.Unit.S28E01');
      expect(arrUnescape('A &amp;amp; B &quot;C&quot; &#39;D&#39;'),
          'A &amp; B "C" \'D\'');
      expect(arrUnescape('No escapes'), 'No escapes');
    });
  });

  group('Sonarr files', () {
    final items = _items(ArrKind.sonarr, 'sonarr_manualimport');
    final unknown = items.firstWhere((i) => i.seriesTitle == null &&
        i.fileName.startsWith('Totally'));
    final worse = items.firstWhere((i) => i.seriesTitle == 'Breaking Bad');

    test('reads what the app guessed and why it held back', () {
      expect(unknown.gap, ArrImportGap.title);
      expect(unknown.rejections, contains('Unknown Series'));
      expect(unknown.qualityName, 'HDTV-720p');
      expect(unknown.downloadId, isNotEmpty);

      expect(worse.seriesId, 2);
      expect(worse.episodeCode, 'S01E01');
      expect(worse.gap, isNull);
      expect(
        worse.rejections.any((r) => r.startsWith('Not an upgrade')),
        isTrue,
      );
      expect(worse.fileName, endsWith('.mkv'));
      expect(worse.fileName, isNot(contains('/')));
    });

    test('a new show clears the season and episodes for the app to redo', () {
      const severance = ArrSeries(id: 3, title: 'Severance');
      final next = const ArrFileChanges(series: severance).applyTo(worse);
      expect(next.seriesId, 3);
      expect(next.seriesTitle, 'Severance');
      expect(next.seasonNumber, isNull);
      expect(next.episodes, isEmpty);
      expect(next.gap, ArrImportGap.season);
      // What it sends: the show, and nothing left of the old episodes.
      final j = next.toReprocessJson();
      expect(j['seriesId'], 3);
      expect(j['episodeIds'], isEmpty);
      expect(j['downloadId'], worse.downloadId);
    });

    test('the app fills the episodes back in after a recheck', () {
      final back = _items(ArrKind.sonarr, 'sonarr_manualimport_recheck').single;
      final mine = const ArrFileChanges(
        series: ArrSeries(id: 3, title: 'Severance'),
      ).applyTo(unknown);
      final merged = mine.mergeReprocessed(back);
      expect(merged.seriesTitle, 'Severance');
      expect(merged.seasonNumber, 1);
      expect(merged.episodeCode, 'S01E01');
      expect(merged.rejections, isNot(contains('Unknown Series')));
      expect(merged.gap, isNull);
    });

    test('names a double episode as a range, others one by one', () {
      ArrEpisode e(int n) =>
          ArrEpisode(id: n, seriesId: 2, seasonNumber: 1, episodeNumber: n);
      expect(worse.copyWith(episodes: [e(1), e(2)]).episodeCode, 'S01E01-E02');
      expect(
        worse.copyWith(episodes: [e(1), e(3)]).episodeCode,
        'S01E01, S01E03',
      );
    });

    test('a new quality keeps the revision (proper, repack)', () {
      const bluray = ArrQualityChoice({
        'id': 7,
        'name': 'Bluray-1080p',
        'source': 'bluray',
        'resolution': 1080,
      }, 'Bluray-1080p');
      final proper = worse.copyWith(
        quality: {
          ...worse.quality!,
          'revision': {'version': 2, 'real': 0, 'isRepack': false},
        },
      );
      final next = const ArrFileChanges(quality: bluray).applyTo(proper);
      expect(arrQualityId(next.quality), 7);
      expect((next.quality!['revision'] as Map)['version'], 2);
    });

    test('imports with the same fields the apps own page sends', () async {
      final (s, r) = _sonarr((_) => {'id': 1, 'status': 'queued'});
      await s.manualImport([worse], 'auto');
      final body = r.sent.single.data as Map;
      expect(r.sent.single.path, endsWith('/api/v3/command'));
      expect(body['name'], 'ManualImport');
      expect(body['importMode'], 'auto');
      final f = (body['files'] as List).single as Map;
      expect(f.keys.toSet(), {
        'path', 'folderName', 'seriesId', 'episodeIds', 'episodeFileId',
        'releaseType', 'quality', 'languages', 'releaseGroup',
        'indexerFlags', 'downloadId',
      });
      expect(f['seriesId'], 2);
      expect(f['episodeIds'], [worse.episodes.single.id]);
      expect(f['downloadId'], worse.downloadId);
      expect((f['languages'] as List).single, {'id': 1, 'name': 'English'});
    });

    test('finds files in a download, a folder or a title folder', () async {
      final (s, r) = _sonarr((_) => const []);
      await s.importFiles(downloadId: 'abc');
      await s.importFiles(folder: '/tv/Breaking Bad');
      await s.importFiles(titleId: 2, filterExisting: false);
      expect(r.sent[0].queryParameters, {
        'downloadId': 'abc',
        'filterExistingFiles': true,
      });
      expect(r.sent[1].queryParameters, {
        'folder': '/tv/Breaking Bad',
        'filterExistingFiles': true,
      });
      expect(r.sent[2].queryParameters, {
        'seriesId': 2,
        'filterExistingFiles': false,
      });
    });

    test('a file edit goes to episodefile/bulk', () async {
      final (s, r) = _sonarr((_) => const []);
      await s.updateFiles([
        {'id': 3, 'releaseGroup': 'GRP'},
      ]);
      expect(r.sent.single.method, 'PUT');
      expect(r.sent.single.path, endsWith('/api/v3/episodefile/bulk'));
      final (m, mr) = _radarr((_) => const []);
      await m.updateFiles([
        {'id': 1, 'releaseGroup': 'GRP'},
      ]);
      expect(mr.sent.single.path, endsWith('/api/v3/moviefile/bulk'));
    });
  });

  group('Radarr files', () {
    final items = _items(ArrKind.radarr, 'radarr_manualimport');
    final interstellar = items.firstWhere(
      (i) => i.movieTitle == 'Interstellar',
    );
    final unknown = items.firstWhere((i) => i.movieId == null);

    test('reads the movie, or that it needs one', () {
      expect(interstellar.movieId, 1);
      expect(interstellar.movieYear, 2014);
      expect(interstellar.gap, isNull);
      expect(unknown.gap, ArrImportGap.title);
      expect(unknown.rejections, contains('Unknown Movie'));
    });

    test('imports with movieId, not the Sonarr fields', () {
      final j = const ArrFileChanges(
        movie: ArrMovie(id: 4, title: 'Avengers: Doomsday'),
      ).applyTo(unknown).toCommandJson();
      expect(j['movieId'], 4);
      expect(j.containsKey('seriesId'), isFalse);
      expect(j.containsKey('episodeIds'), isFalse);
      expect(j.containsKey('releaseType'), isFalse);
    });
  });

  group('remove dialog', () {
    Future<void> open(WidgetTester t, List<ArrQueueItem> items) async {
      t.view.physicalSize = const Size(900, 1200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showArrQueueRemoveManyDialog(
                context,
                items: items,
                clientFor: (_) => null,
              ),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
    }

    ArrQueueItem q(Map<String, dynamic> j) => ArrQueueItem.fromJson(
      ArrKind.sonarr,
      {'id': 1, 'title': 'Show.S01E01', 'status': 'completed', ...j},
    );

    testWidgets('offers Change Category and Ignore where they apply', (t) async {
      await open(t, [
        q({'seriesId': 2, 'downloadClientHasPostImportCategory': true}),
      ]);
      expect(find.text('In the Download Client'), findsOneWidget);
      await t.tap(find.text('Remove from Download Client'));
      await t.pumpAndSettle();
      expect(find.text('Change Category'), findsWidgets);
      expect(find.text('Ignore Download'), findsWidgets);
    });

    testWidgets('an unmatched download can only be removed', (t) async {
      await open(t, [q({})]);
      await t.tap(find.text('Remove from Download Client'));
      await t.pumpAndSettle();
      expect(find.text('Ignore Download'), findsNothing);
      expect(find.text('Change Category'), findsNothing);
    });

    testWidgets('a held-back download has nothing in a client', (t) async {
      await open(t, [q({'status': 'delay', 'seriesId': 2})]);
      expect(find.text('In the Download Client'), findsNothing);
    });
  });

  test('languages leave out the profile-only Any and Original', () {
    expect(const ArrLanguage(-2, 'Original').known, isFalse);
    expect(const ArrLanguage(0, 'Unknown').known, isFalse);
    expect(const ArrLanguage(1, 'English').known, isTrue);
  });

  test('qualities come worst to best, as the app ranks them', () async {
    final (s, _) = _sonarr((_) => [
      {'quality': {'id': 7, 'name': 'Bluray-1080p'}, 'title': 'Bluray-1080p', 'weight': 14},
      {'quality': {'id': 1, 'name': 'SDTV'}, 'title': 'SDTV', 'weight': 2},
    ]);
    expect((await s.qualities()).map((q) => q.name), ['SDTV', 'Bluray-1080p']);
  });

  test('server folders read with the folder above', () async {
    final (s, r) = _sonarr((_) => {
      'parent': '/',
      'directories': [
        {'type': 'folder', 'name': 'watch', 'path': '/downloads/watch/'},
      ],
    });
    final l = await s.folders('/downloads/');
    expect(r.sent.single.queryParameters['includeFiles'], false);
    expect(l.parent, '/');
    expect(l.folders.single.path, '/downloads/watch/');
    final top = ArrFolderListing.fromJson('', {'parent': '', 'directories': []});
    expect(top.parent, isNull);
  });

  test('recent folders and the Move or Copy choice survive a restart', () {
    var p = const Prefs().copyWith(
      arrImport: {
        'sonarr': ['/downloads/tv', '/downloads'],
        'mode': 'copy',
      },
    );
    p = Prefs.fromJson(jsonDecode(jsonEncode(p.toJson())));
    expect(arrImportRecent(p, ArrKind.sonarr), ['/downloads/tv', '/downloads']);
    expect(arrImportRecent(p, ArrKind.radarr), isEmpty);
    expect(arrImportMode(p), 'copy');
    expect(arrImportMode(const Prefs()), isNull);
  });
}
