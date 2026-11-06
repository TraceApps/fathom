import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fathom/api/arr_client.dart';
import 'package:fathom/models/arr.dart';
import 'package:fathom/screens/arr_releases_screen.dart';
import 'package:fathom/services/settings_backup.dart';
import 'package:fathom/state/arr_providers.dart';
import 'package:fathom/state/preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Recorded from Sonarr 4.0.20 and Radarr 6.4.4 (test servers seeded with
// three shows, four movies and real files).
dynamic _fixture(String name) =>
    jsonDecode(File('test/fixtures/arr/$name.json').readAsStringSync());

DioException _error(int? code, Object? body,
        [DioExceptionType type = DioExceptionType.badResponse]) =>
    DioException(
      requestOptions: RequestOptions(path: '/x'),
      type: type,
      response: code == null
          ? null
          : Response(
              requestOptions: RequestOptions(path: '/x'),
              statusCode: code,
              data: body),
    );

void main() {
  group('Sonarr', () {
    final series = [
      for (final m in _fixture('sonarr_series') as List) ArrSeries.fromJson(m)
    ];
    final bb = series.firstWhere((s) => s.title == 'Breaking Bad');

    test('reads shows with their counts', () {
      expect(series.map((s) => s.title),
          containsAll(['Breaking Bad', 'Severance', 'The Simpsons']));
      expect(bb.year, 2008);
      expect(bb.network, 'AMC');
      expect(bb.ended, isTrue);
      expect(bb.episodeFileCount, 2);
      expect(bb.episodeCount, 62);
      expect(bb.missingEpisodes, 60);
      expect(bb.state, ArrState.missing);
      expect(bb.tvdbId, 81189);
    });

    test('reads episodes and their files', () {
      final eps = [
        for (final m in _fixture('sonarr_episodes') as List)
          ArrEpisode.fromJson(m)
      ];
      final pilot = eps.firstWhere((e) => e.episodeNumber == 1);
      expect(pilot.code, 'S01E01');
      expect(pilot.hasFile, isTrue);
      expect(pilot.aired(DateTime.now()), isTrue);
      final files = [
        for (final m in _fixture('sonarr_episodefiles') as List)
          ArrFile.fromJson(m)
      ];
      final f = files.firstWhere((f) => f.id == pilot.episodeFileId);
      expect(f.quality, 'Bluray-1080p');
      expect(f.mediaInfo?.videoCodec, 'x264');
      expect(f.mediaInfo?.resolution, '1920x1080');
      expect(f.mediaInfo?.channels, '5.1');
      expect(f.languages, contains('English'));
    });

    test('a queue record names the show and episode', () {
      final q = ArrQueueItem.fromJson(ArrKind.sonarr, {
        'id': 7,
        'seriesId': bb.id,
        'series': {'title': 'Breaking Bad', 'images': []},
        'episode': {'seasonNumber': 1, 'episodeNumber': 3, 'title': '...And the Bag\'s in the River'},
        'title': 'Breaking.Bad.S01E03.1080p.BluRay.x264',
        'size': 2000,
        'sizeleft': 500,
        'status': 'downloading',
        'trackedDownloadStatus': 'ok',
        'trackedDownloadState': 'downloading',
        'statusMessages': [
          {'title': 'x', 'messages': ['Not enough free space']}
        ],
        'quality': {'quality': {'name': 'Bluray-1080p'}},
      });
      expect(q.mediaTitle, 'Breaking Bad');
      expect(q.episodeCode, 'S01E03');
      expect(q.progress, 0.75);
      expect(q.messages, ['Not enough free space']);
      expect(q.hasProblem, isFalse);
      expect(
          ArrQueueItem.fromJson(ArrKind.sonarr,
              {'id': 1, 'title': 't', 'trackedDownloadState': 'importBlocked'}).hasProblem,
          isTrue);
    });
  });

  group('Radarr', () {
    final movies = [
      for (final m in _fixture('radarr_movies') as List) ArrMovie.fromJson(m)
    ];

    test('reads movies and where each stands', () {
      ArrMovie byTitle(String t) => movies.firstWhere((m) => m.title == t);
      expect(byTitle('Interstellar').state, ArrState.downloaded);
      expect(byTitle('Project Hail Mary').state, ArrState.missing);
      expect(byTitle('Avengers: Doomsday').state, ArrState.unreleased);
      expect(byTitle('Interstellar').tmdbId, 157336);
    });

    test('reads a movie with its file', () {
      final m = ArrMovie.fromJson(_fixture('radarr_movie1'));
      expect(m.movieFile?.relativePath, 'Interstellar (2014) Bluray-1080p.mkv');
      expect(m.movieFile?.mediaInfo?.audioCodec, 'AC3');
      expect(m.sizeOnDisk, greaterThan(0));
    });

    test('release dates stay on their day in any time zone', () {
      final m = ArrMovie.fromJson({
        'id': 1,
        'title': 'x',
        'physicalRelease': '2026-12-02T00:00:00Z',
      });
      expect(m.physicalRelease, DateTime(2026, 12, 2));
    });

    test('the calendar lists each release inside the window', () {
      final entries = ArrCalendarEntry.fromMovie({
        'id': 3,
        'title': 'Spider-Man: Brand New Day',
        'inCinemas': '2026-07-29T00:00:00Z',
        'digitalRelease': '2026-10-06T00:00:00Z',
        'physicalRelease': '2026-12-02T00:00:00Z',
        'monitored': true,
      }, DateTime(2026, 11, 3), DateTime(2026, 12, 3));
      expect(entries, hasLength(1));
      expect(entries.single.release, ArrRelease.physical);
      expect(entries.single.date, DateTime(2026, 12, 2));
    });
  });

  group('pictures', () {
    test('TMDB pictures are asked for at a sensible size', () {
      expect(sizedImageUrl('https://image.tmdb.org/t/p/original/a.jpg', 342),
          'https://image.tmdb.org/t/p/w342/a.jpg');
      expect(sizedImageUrl('https://image.tmdb.org/t/p/original/a.jpg', 1280),
          'https://image.tmdb.org/t/p/w1280/a.jpg');
      expect(sizedImageUrl('https://artworks.thetvdb.com/p.jpg', 342),
          'https://artworks.thetvdb.com/p.jpg');
    });

    test("the app's own copies resolve against its address", () {
      final c = SonarrClient('http://nas:8989/sonarr/', 'k');
      expect(
          c.imageUrl(const [
            ArrImage(coverType: 'poster', url: '/sonarr/MediaCover/1/poster.jpg')
          ], 'poster'),
          'http://nas:8989/sonarr/MediaCover/1/poster.jpg');
      expect(c.imageUrl(const [], 'poster'), isNull);
    });
  });

  group('error messages', () {
    test('a rejected key says so', () {
      expect(arrErrorMessage(ArrKind.sonarr, _error(401, null)),
          'Sonarr rejected the API key.');
    });

    test("the app's own reason is shown, in either of its shapes", () {
      expect(
          arrErrorMessage(
              ArrKind.radarr, _error(400, {'message': 'Movie not found'})),
          'Radarr: Movie not found');
      expect(
          arrErrorMessage(ArrKind.sonarr, _error(400, [
            {'propertyName': 'Path', 'errorMessage': 'Path is already configured'}
          ])),
          'Sonarr: Path is already configured');
    });

    test('nothing answering, or the wrong address', () {
      expect(
          arrErrorMessage(ArrKind.sonarr,
              _error(null, null, DioExceptionType.connectionError)),
          'Could not reach Sonarr.');
      expect(arrErrorMessage(ArrKind.radarr, _error(404, '<html>')),
          "Radarr isn't at this address (404).");
    });
  });

  group('interactive search', () {
    List<ArrSearchResult> read(String name) => [
      for (final m in _fixture(name) as List) ArrSearchResult.fromJson(m),
    ];

    test("Sonarr's releases keep its verdict and ranking data", () {
      final list = read('sonarr_releases');
      expect(list, hasLength(6));
      final uhd = list.firstWhere((r) => r.title.contains('2160p'));
      expect(uhd.rejected, isTrue);
      expect(uhd.rejections, ['WEBDL-2160p is not wanted in profile']);
      expect(uhd.quality, 'WEBDL-2160p');
      expect(uhd.qualityWeight, greaterThan(0));
      expect(uhd.protocol, 'usenet');
      expect(uhd.isTorrent, isFalse);
      expect(uhd.indexerId, greaterThan(0));
      expect(uhd.guid, isNotEmpty);
      expect(uhd.ageHours, closeTo(120, 1));
      final ok = list.firstWhere((r) => r.title.contains('BluRay'));
      expect(ok.rejected, isFalse);
      expect(ok.rejections, isEmpty);
      expect(ok.downloadAllowed, isTrue);
    });

    test("Radarr's rejections and languages read the same way", () {
      final list = read('radarr_releases');
      final german = list.firstWhere((r) => r.title.contains('German'));
      expect(german.rejected, isTrue);
      expect(german.rejections.single, contains('German'));
      expect(german.languages, ['German']);
    });

    test('rejections sent as objects still read', () {
      final r = ArrSearchResult.fromJson({
        'guid': 'g',
        'indexerId': 1,
        'title': 't',
        'rejected': true,
        'rejections': [
          {'reason': 'Not an upgrade', 'type': 'permanent'},
        ],
        'protocol': 'torrent',
        'seeders': 12,
        'leechers': 3,
      });
      expect(r.rejections, ['Not an upgrade']);
      expect(r.isTorrent, isTrue);
      expect(r.seeders, 12);
    });

    test('ages read like the apps show them', () {
      expect(arrAge(0.5), '30m');
      expect(arrAge(5), '5h');
      expect(arrAge(120), '5d');
      expect(arrAge(24 * 800), '2y');
    });

    test('the search page finds its target again from the address', () {
      for (final t in [
        const ArrReleaseTarget.movie(4),
        const ArrReleaseTarget.season(2, 0),
        const ArrReleaseTarget.episode(2, 31),
      ]) {
        final back = ArrReleaseTarget.fromQuery(
          Uri.parse(t.location).queryParameters,
        )!;
        expect(back.kind, t.kind);
        expect(back.movieId, t.movieId);
        expect(back.seriesId, t.seriesId);
        expect(back.seasonNumber, t.seasonNumber);
        expect(back.episodeId, t.episodeId);
      }
      expect(ArrReleaseTarget.fromQuery(const {}), isNull);
      expect(ArrReleaseTarget.fromQuery(const {'series': '2'}), isNull);
    });
  });

  group('adding', () {
    test('lookups say what is already in the library', () {
      final shows = [
        for (final m in _fixture('sonarr_lookup') as List)
          ArrLookup(ArrSeries.fromJson(m), Map<String, dynamic>.from(m)),
      ];
      final bb = shows.firstWhere((s) => s.item.title == 'Breaking Bad');
      expect(bb.inLibrary, isTrue);
      expect(bb.existingId, 2);
      expect(shows.where((s) => !s.inLibrary), isNotEmpty);
      final movies = [
        for (final m in _fixture('radarr_lookup') as List)
          ArrLookup(ArrMovie.fromJson(m), Map<String, dynamic>.from(m)),
      ];
      expect(movies.first.item.title, 'The Matrix');
      expect(movies.first.inLibrary, isFalse);
    });

    test('root folders come with their free space', () {
      final roots = [
        for (final m in _fixture('sonarr_rootfolder') as List)
          ArrRootFolder.fromJson(m),
      ];
      expect(roots.single.path, '/tv');
      expect(roots.single.freeSpace, greaterThan(0));
    });

    test('a rename names the file and both paths', () {
      final r = ArrRename.fromJson({
        'episodeFileId': 4,
        'existingPath': 'Season 1/breaking.bad.s01e02.mkv',
        'newPath': 'Season 1/Breaking Bad - S01E02.mkv',
      });
      expect(r.fileId, 4);
      expect(ArrRename.fromJson({'movieFileId': 9}).fileId, 9);
    });
  });

  test('the calendar shows yesterday through four weeks ahead', () {
    final w = arrCalendarWindow(DateTime(2026, 11, 4, 15, 30));
    expect(w.start, DateTime(2026, 11, 3));
    expect(w.end, DateTime(2026, 12, 3));
  });

  test('API keys never go into a settings backup', () {
    expect(secretPrefKeys, containsAll(['sonarrApiKey', 'radarrApiKey']));
    // The keys really are the preference names.
    final json = const Prefs(sonarrApiKey: 's', radarrApiKey: 'r').toJson();
    expect(json['sonarrApiKey'], 's');
    expect(json['radarrApiKey'], 'r');
  });

  group('Wanted', () {
    test('Sonarr missing: episodes with their show, newest first', () {
      final j = _fixture('sonarr_wanted_missing') as Map<String, dynamic>;
      expect(j['totalRecords'], 884);
      final w = [
        for (final r in j['records'] as List)
          ArrWantedItem.fromEpisode(Map<String, dynamic>.from(r)),
      ];
      expect(w.first.kind, ArrKind.sonarr);
      expect(w.first.title, 'The Simpsons');
      expect(w.first.episodeCode, 'S38E05');
      expect(w.first.episodeTitle, 'Testing 1-2-3');
      expect(w.first.episodeId, 880);
      expect(w.first.seriesId, isNotNull);
      expect(w.first.available, isTrue);
      expect(w.first.images, isNotEmpty);
      expect(w.first.date!.isAfter(w[1].date!), isTrue);
    });

    test('Sonarr cutoff unmet carries the quality there now', () {
      final j = _fixture('sonarr_wanted_cutoff') as Map<String, dynamic>;
      final w = ArrWantedItem.fromEpisode(
        Map<String, dynamic>.from((j['records'] as List).single),
      );
      expect(w.title, 'Breaking Bad');
      expect(w.episodeCode, 'S01E03');
      expect(w.quality, 'WEBDL-720p');
    });

    test('Radarr missing includes movies not out yet, marked so', () {
      final j = _fixture('radarr_wanted_missing') as Map<String, dynamic>;
      final w = [
        for (final r in j['records'] as List)
          ArrWantedItem.fromMovie(Map<String, dynamic>.from(r)),
      ];
      expect(w.map((x) => x.title), [
        'Spider-Man: Brand New Day',
        'Project Hail Mary',
        'Avengers: Doomsday',
      ]);
      expect(w.first.available, isTrue);
      expect(w.first.date, DateTime(2026, 10, 6));
      expect(w.first.year, 2026);
      expect(w.first.movieId, isNotNull);
      expect(w.last.available, isFalse);
      // No digital or disc date yet: the cinema date stands in.
      expect(w.last.date, DateTime(2026, 12, 16));
    });
  });

  test('Wanted puts what is not out yet last, not first as the newest',
      () async {
    final container = ProviderContainer(overrides: [
      sonarrClientProvider.overrideWithValue(null),
      radarrClientProvider.overrideWithValue(_FakeRadarr(const [], 0, wanted: [
        ArrWantedItem(
          kind: ArrKind.radarr,
          title: 'Coming',
          date: DateTime(2026, 12, 16),
          available: false,
        ),
        ArrWantedItem(
          kind: ArrKind.radarr,
          title: 'Out',
          date: DateTime(2026, 10, 6),
        ),
      ])),
    ]);
    addTearDown(container.dispose);
    final m = await container.read(
      arrWantedProvider((ArrWantedList.missing, arrPageSize)).future,
    );
    expect(m.items.map((w) => w.title), ['Out', 'Coming']);
  });

  group('History', () {
    test('Sonarr history names the show and episode', () {
      final j = _fixture('sonarr_recent_history') as Map<String, dynamic>;
      final h = ArrHistoryItem.fromJson(
        Map<String, dynamic>.from((j['records'] as List).first),
        ArrKind.sonarr,
      );
      expect(h.kind, ArrKind.sonarr);
      expect(h.eventType, 'grabbed');
      expect(h.canMarkFailed, isTrue);
      expect(h.title, 'Severance');
      expect(h.episodeCode, 'S02E10');
      expect(h.quality, 'Bluray-1080p');
      expect(h.sourceTitle, 'Severance.S02.1080p.BluRay.x264-GRP');
      expect(h.detail, 'Rig');
      expect(h.seriesId, isNotNull);
      expect(h.images, isNotEmpty);
    });

    test('Radarr history names the movie', () {
      final j = _fixture('radarr_recent_history') as Map<String, dynamic>;
      final h = ArrHistoryItem.fromJson(
        Map<String, dynamic>.from((j['records'] as List).first),
        ArrKind.radarr,
      );
      expect(h.title, 'Avengers: Doomsday');
      expect(h.movieId, 4);
      expect(h.episodeCode, isNull);
    });

    test('a title page\'s history still reads without the title', () {
      final h = ArrHistoryItem.fromJson({
        'id': 1,
        'eventType': 'downloadFolderImported',
        'date': '2026-11-01T10:00:00Z',
      });
      expect(h.kind, isNull);
      expect(h.title, isNull);
      expect(h.canMarkFailed, isFalse);
    });

    test('both apps merge newest first, and Load More knows there is more',
        () async {
      ArrHistoryItem at(ArrKind k, int id, int day) => ArrHistoryItem(
            kind: k,
            id: id,
            eventType: 'grabbed',
            date: DateTime(2026, 11, day),
          );
      final container = ProviderContainer(overrides: [
        sonarrClientProvider.overrideWithValue(_FakeSonarr([
          at(ArrKind.sonarr, 1, 5),
          at(ArrKind.sonarr, 2, 2),
        ], 10)),
        radarrClientProvider.overrideWithValue(_FakeRadarr([
          at(ArrKind.radarr, 3, 4),
          at(ArrKind.radarr, 4, 1),
        ], 2)),
      ]);
      addTearDown(container.dispose);
      final m = await container.read(arrRecentHistoryProvider(3).future);
      expect(m.items.map((h) => h.id), [1, 3, 2]);
      expect(m.total, 12);
      expect(m.hasMore, isTrue);
      expect(m.errors, isEmpty);
    });
  });

  test('health checks read with their wiki link', () {
    final list = _fixture('sonarr_health') as List;
    final h = ArrHealth.fromJson(
      ArrKind.sonarr,
      Map<String, dynamic>.from(list.single),
    );
    expect(h.source, 'DownloadClientCheck');
    expect(h.type, 'warning');
    expect(h.isProblem, isTrue);
    expect(h.message, 'No download client is available');
    expect(h.wikiUrl,
        'https://wiki.servarr.com/sonarr/system#no-download-client-is-available');
    expect(
      ArrHealth.fromJson(ArrKind.radarr, {
        'type': 'notice',
        'message': 'x',
        'wikiUrl': {'fullUri': 'https://wiki.servarr.com/x'},
      }).wikiUrl,
      'https://wiki.servarr.com/x',
    );
    expect(
      ArrHealth.fromJson(ArrKind.radarr, {'type': 'notice'}).isProblem,
      isFalse,
    );
  });
}

class _FakeSonarr extends SonarrClient {
  final List<ArrHistoryItem> items;
  final int total;
  _FakeSonarr(this.items, this.total) : super('http://sonarr', 'k');
  @override
  Future<ArrPage<ArrHistoryItem>> recentHistory({int pageSize = 50}) async =>
      ArrPage(items.take(pageSize).toList(), total);
}

class _FakeRadarr extends RadarrClient {
  final List<ArrHistoryItem> items;
  final int total;
  final List<ArrWantedItem> wanted;
  _FakeRadarr(this.items, this.total, {this.wanted = const []})
      : super('http://radarr', 'k');
  @override
  Future<ArrPage<ArrWantedItem>> missing({int pageSize = 50}) async =>
      ArrPage(wanted, wanted.length);
  @override
  Future<ArrPage<ArrHistoryItem>> recentHistory({int pageSize = 50}) async =>
      ArrPage(items.take(pageSize).toList(), total);
}
