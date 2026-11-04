import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fathom/api/arr_client.dart';
import 'package:fathom/models/arr.dart';
import 'package:fathom/services/settings_backup.dart';
import 'package:fathom/state/arr_providers.dart';
import 'package:fathom/state/preferences.dart';
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
}
