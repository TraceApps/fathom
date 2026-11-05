import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/arr.dart';

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

class ArrException implements Exception {
  final String message;
  ArrException(this.message);
  @override
  String toString() => message;
}

/// Talks to one Sonarr or Radarr server over its v3 API, with its API key.
/// [baseUrl] is what the user typed, including any URL base ("/sonarr").
abstract class ArrClient {
  final ArrKind kind;
  final String baseUrl;
  final String apiKey;
  final Dio _dio;

  ArrClient(this.kind, String baseUrl, this.apiKey, {Dio? dio})
    : baseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), ''),
      _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
            ),
          );

  Options get _opts => Options(headers: {'X-Api-Key': apiKey});

  /// For pictures served by the app itself (its MediaCover copies).
  Map<String, String> get imageHeaders => {'X-Api-Key': apiKey};

  String _api(String path) => '$baseUrl/api/v3/$path';

  Future<dynamic> _get(String path, [Map<String, dynamic>? query]) async {
    try {
      final r = await _dio.get(
        _api(path),
        queryParameters: query,
        options: _opts,
      );
      return r.data;
    } on DioException catch (e) {
      throw ArrException(arrErrorMessage(kind, e));
    }
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async {
    try {
      final r = await _dio.request(
        _api(path),
        data: body,
        queryParameters: query,
        options: _opts.copyWith(method: method),
      );
      return r.data;
    } on DioException catch (e) {
      throw ArrException(arrErrorMessage(kind, e));
    }
  }

  Future<dynamic> _post(String path, Object? body) =>
      _send('POST', path, body: body);
  Future<dynamic> _put(String path, Object? body) =>
      _send('PUT', path, body: body);
  Future<dynamic> _delete(String path, [Map<String, dynamic>? query]) =>
      _send('DELETE', path, query: query);

  /// Starts one of the app's tasks (a search, a refresh, a rename). It runs
  /// on the server; the answer only says it was queued.
  Future<void> command(String name, [Map<String, dynamic> args = const {}]) =>
      _post('command', {'name': name, ...args});

  /// Where the app may put new titles, with the free space on each.
  Future<List<ArrRootFolder>> rootFolders() async {
    final data = await _get('rootfolder');
    return [
      for (final m in (data as List?) ?? const [])
        if (m is Map) ArrRootFolder.fromJson(Map<String, dynamic>.from(m)),
    ];
  }

  /// Every release the indexers offer for what [query] names (an episode, a
  /// season or a movie), with the app's verdict on each. Slow: the app asks
  /// every indexer before it answers.
  Future<List<ArrSearchResult>> _releases(Map<String, dynamic> query) async {
    try {
      final r = await _dio.get(
        _api('release'),
        queryParameters: query,
        options: _opts.copyWith(receiveTimeout: const Duration(minutes: 3)),
      );
      return [
        for (final m in (r.data as List?) ?? const [])
          if (m is Map) ArrSearchResult.fromJson(Map<String, dynamic>.from(m)),
      ];
    } on DioException catch (e) {
      throw ArrException(arrErrorMessage(kind, e));
    }
  }

  /// Sends a release from an interactive search to the download client.
  Future<void> grab(ArrSearchResult r) =>
      _post('release', {'guid': r.guid, 'indexerId': r.indexerId});

  /// Takes a download out of the queue. [blocklist] stops the app taking the
  /// same release again, and with [searchAgain] it looks for another.
  Future<void> removeFromQueue(
    int id, {
    required bool removeFromClient,
    required bool blocklist,
    bool searchAgain = false,
  }) => _delete('queue/$id', {
    'removeFromClient': removeFromClient,
    'blocklist': blocklist,
    if (blocklist) 'skipRedownload': !searchAgain,
  });

  /// What renaming would change: each file's current and new name.
  Future<List<ArrRename>> renamePreview(int id);

  /// Whether the app renames files at all (Settings, Media Management). Off,
  /// a rename preview is always empty.
  Future<bool> renamingOn() async {
    final data = await _get('config/naming');
    final key = kind == ArrKind.sonarr ? 'renameEpisodes' : 'renameMovies';
    return data is Map && data[key] == true;
  }

  /// Renames the files the preview listed.
  Future<void> rename(int id, List<int> fileIds);

  /// Which app answers at this address, and its version. Throws when it isn't
  /// the app this client is for, so a Radarr address typed in the Sonarr box
  /// is caught on Save & Test.
  Future<ArrStatus> status() async {
    final data = await _get('system/status');
    if (data is! Map) {
      throw ArrException('${kind.appName} sent something unexpected.');
    }
    final s = ArrStatus.fromJson(Map<String, dynamic>.from(data));
    if (s.appName.isNotEmpty &&
        s.appName.toLowerCase() != kind.appName.toLowerCase()) {
      throw ArrException('This address is ${s.appName}, not ${kind.appName}.');
    }
    return s;
  }

  Future<List<ArrQualityProfile>> qualityProfiles() async {
    final data = await _get('qualityprofile');
    return [
      for (final m in (data as List?) ?? const [])
        if (m is Map) ArrQualityProfile.fromJson(Map<String, dynamic>.from(m)),
    ];
  }

  /// Everything in the queue, with the title it belongs to.
  Future<List<ArrQueueItem>> queue() async {
    final data = await _get('queue', {
      'page': 1,
      'pageSize': 500,
      if (kind == ArrKind.sonarr) ...{
        'includeSeries': true,
        'includeEpisode': true,
      } else
        'includeMovie': true,
    });
    final records = (data as Map?)?['records'];
    return [
      for (final m in (records as List?) ?? const [])
        if (m is Map) ArrQueueItem.fromJson(kind, Map<String, dynamic>.from(m)),
    ];
  }

  /// What's airing or being released between [start] and [end].
  Future<List<ArrCalendarEntry>> calendar(DateTime start, DateTime end);

  /// A picture of a title, of [type] (poster, fanart, banner), at about
  /// [width] pixels where the source can be asked for a size.
  String? imageUrl(List<ArrImage> images, String type, {int width = 500}) {
    ArrImage? image;
    for (final i in images) {
      if (i.coverType == type) {
        image = i;
        break;
      }
    }
    if (image == null) return null;
    final remote = image.remoteUrl;
    if (remote != null && remote.isNotEmpty) {
      return sizedImageUrl(remote, width);
    }
    final local = image.url;
    if (local == null || local.isEmpty) return null;
    // The app's own copy: its path already carries any URL base, so it
    // resolves against the server's origin.
    return Uri.parse(baseUrl).resolve(local).toString();
  }

  /// The address of this title in the app's own web page.
  String webUrl(String? titleSlug) =>
      '$baseUrl/${kind == ArrKind.sonarr ? 'series' : 'movie'}/${titleSlug ?? ''}';
}

/// TMDB serves every size of a picture; the apps keep the "original" link,
/// which can be several megabytes. Asks for a sensible width instead. Other
/// sources (TheTVDB, fanart.tv) are left as they are.
@visibleForTesting
String sizedImageUrl(String url, int width) {
  const original = '/t/p/original/';
  if (!url.contains('image.tmdb.org') || !url.contains(original)) return url;
  final size = width <= 185
      ? 'w185'
      : width <= 342
      ? 'w342'
      : width <= 500
      ? 'w500'
      : width <= 780
      ? 'w780'
      : 'w1280';
  return url.replaceFirst(original, '/t/p/$size/');
}

/// What to tell the user when the app answers with an error. Sonarr and Radarr
/// explain a refusal in `message`, or in a list of field errors.
@visibleForTesting
String arrErrorMessage(ArrKind kind, DioException e) {
  final app = kind.appName;
  final code = e.response?.statusCode;
  if (code == 401) return '$app rejected the API key.';
  final data = e.response?.data;
  String? message;
  if (data is Map) {
    final m = data['message'] ?? data['error'];
    if (m is String) message = m;
  } else if (data is List) {
    final errors = [
      for (final x in data)
        if (x is Map && x['errorMessage'] is String)
          x['errorMessage'] as String,
    ];
    if (errors.isNotEmpty) message = errors.join(' ');
  }
  if (message != null && message.trim().isNotEmpty) {
    return '$app: ${message.trim()}';
  }
  switch (e.type) {
    case DioExceptionType.connectionError:
    case DioExceptionType.connectionTimeout:
      return 'Could not reach $app.';
    case DioExceptionType.receiveTimeout:
      return '$app took too long to answer.';
    default:
      break;
  }
  if (code == 404) return "$app isn't at this address (404).";
  return '$app error (${code ?? 'unknown'}).';
}

class SonarrClient extends ArrClient {
  SonarrClient(String baseUrl, String apiKey, {super.dio})
    : super(ArrKind.sonarr, baseUrl, apiKey);

  Future<List<ArrSeries>> series() async {
    final data = await _get('series');
    return [
      for (final m in (data as List?) ?? const [])
        if (m is Map) ArrSeries.fromJson(Map<String, dynamic>.from(m)),
    ];
  }

  Future<ArrSeries> seriesById(int id) async => ArrSeries.fromJson(
    Map<String, dynamic>.from(await _get('series/$id') as Map),
  );

  Future<List<ArrEpisode>> episodes(int seriesId) async {
    final data = await _get('episode', {'seriesId': seriesId});
    return [
      for (final m in (data as List?) ?? const [])
        if (m is Map) ArrEpisode.fromJson(Map<String, dynamic>.from(m)),
    ];
  }

  Future<List<ArrFile>> episodeFiles(int seriesId) async {
    final data = await _get('episodefile', {'seriesId': seriesId});
    return [
      for (final m in (data as List?) ?? const [])
        if (m is Map) ArrFile.fromJson(Map<String, dynamic>.from(m)),
    ];
  }

  Future<List<ArrHistoryItem>> history(int seriesId) async {
    final data = await _get('history/series', {'seriesId': seriesId});
    return [
      for (final m in (data as List?) ?? const [])
        if (m is Map) ArrHistoryItem.fromJson(Map<String, dynamic>.from(m)),
    ]..sort((a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)));
  }

  /// The show exactly as Sonarr keeps it, for sending back changed.
  Future<Map<String, dynamic>> seriesRaw(int id) async =>
      Map<String, dynamic>.from(await _get('series/$id') as Map);

  /// Saves a changed show. [raw] is what [seriesRaw] gave, edited.
  Future<void> updateSeries(Map<String, dynamic> raw) async {
    final id = _int(raw['id']);
    await _put('series/$id', raw);
  }

  /// Monitors or stops monitoring a show, and with it every season, as
  /// Sonarr's own toggle does.
  Future<void> setSeriesMonitored(int id, bool monitored) async {
    final raw = await seriesRaw(id);
    raw['monitored'] = monitored;
    await updateSeries(raw);
  }

  Future<void> setSeasonMonitored(
    int seriesId,
    int seasonNumber,
    bool monitored,
  ) async {
    final raw = await seriesRaw(seriesId);
    for (final s in (raw['seasons'] as List?) ?? const []) {
      if (s is Map && s['seasonNumber'] == seasonNumber) {
        s['monitored'] = monitored;
      }
    }
    await updateSeries(raw);
  }

  Future<void> setEpisodesMonitored(List<int> ids, bool monitored) =>
      _put('episode/monitor', {'episodeIds': ids, 'monitored': monitored});

  Future<void> searchSeries(int id) =>
      command('SeriesSearch', {'seriesId': id});
  Future<void> searchSeason(int id, int seasonNumber) =>
      command('SeasonSearch', {'seriesId': id, 'seasonNumber': seasonNumber});
  Future<void> searchEpisodes(List<int> ids) =>
      command('EpisodeSearch', {'episodeIds': ids});
  Future<void> refreshSeries(int id) =>
      command('RefreshSeries', {'seriesId': id});

  Future<List<ArrSearchResult>> releasesForEpisode(int episodeId) =>
      _releases({'episodeId': episodeId});
  Future<List<ArrSearchResult>> releasesForSeason(int id, int seasonNumber) =>
      _releases({'seriesId': id, 'seasonNumber': seasonNumber});

  @override
  Future<List<ArrRename>> renamePreview(int id) async {
    final data = await _get('rename', {'seriesId': id});
    return [
      for (final m in (data as List?) ?? const [])
        if (m is Map) ArrRename.fromJson(Map<String, dynamic>.from(m)),
    ];
  }

  @override
  Future<void> rename(int id, List<int> fileIds) =>
      command('RenameFiles', {'seriesId': id, 'files': fileIds});

  /// Shows matching [term] (a name, or tvdb:12345), whether or not Sonarr
  /// has them. Each comes with the raw entry [addSeries] needs.
  Future<List<ArrLookup<ArrSeries>>> lookup(String term) async {
    final data = await _get('series/lookup', {'term': term});
    return [
      for (final m in (data as List?) ?? const [])
        if (m is Map)
          ArrLookup(
            ArrSeries.fromJson(Map<String, dynamic>.from(m)),
            Map<String, dynamic>.from(m),
          ),
    ];
  }

  Future<ArrSeries> addSeries(
    Map<String, dynamic> lookupRaw, {
    required int qualityProfileId,
    required String rootFolderPath,
    required String monitor, // all, future, missing, existing, pilot, ...
    required String seriesType, // standard, daily, anime
    required bool seasonFolder,
    required bool search,
  }) async {
    final body = Map<String, dynamic>.from(lookupRaw)
      ..remove('id')
      ..['qualityProfileId'] = qualityProfileId
      ..['rootFolderPath'] = rootFolderPath
      ..['monitored'] = monitor != 'none'
      ..['seriesType'] = seriesType
      ..['seasonFolder'] = seasonFolder
      ..['addOptions'] = {
        'monitor': monitor,
        'searchForMissingEpisodes': search,
        'searchForCutoffUnmetEpisodes': false,
      };
    return ArrSeries.fromJson(
      Map<String, dynamic>.from(await _post('series', body) as Map),
    );
  }

  Future<void> deleteSeries(
    int id, {
    required bool deleteFiles,
    required bool addExclusion,
  }) => _delete('series/$id', {
    'deleteFiles': deleteFiles,
    'addImportListExclusion': addExclusion,
  });

  Future<void> deleteEpisodeFile(int id) => _delete('episodefile/$id');

  @override
  Future<List<ArrCalendarEntry>> calendar(DateTime start, DateTime end) async {
    final data = await _get('calendar', {
      'start': start.toUtc().toIso8601String(),
      'end': end.toUtc().toIso8601String(),
      'includeSeries': true,
      'unmonitored': false,
    });
    return [
      for (final m in (data as List?) ?? const [])
        if (m is Map)
          ?ArrCalendarEntry.fromEpisode(Map<String, dynamic>.from(m)),
    ];
  }
}

class RadarrClient extends ArrClient {
  RadarrClient(String baseUrl, String apiKey, {super.dio})
    : super(ArrKind.radarr, baseUrl, apiKey);

  Future<List<ArrMovie>> movies() async {
    final data = await _get('movie');
    return [
      for (final m in (data as List?) ?? const [])
        if (m is Map) ArrMovie.fromJson(Map<String, dynamic>.from(m)),
    ];
  }

  Future<ArrMovie> movie(int id) async => ArrMovie.fromJson(
    Map<String, dynamic>.from(await _get('movie/$id') as Map),
  );

  Future<List<ArrHistoryItem>> history(int movieId) async {
    final data = await _get('history/movie', {'movieId': movieId});
    return [
      for (final m in (data as List?) ?? const [])
        if (m is Map) ArrHistoryItem.fromJson(Map<String, dynamic>.from(m)),
    ]..sort((a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)));
  }

  /// The movie exactly as Radarr keeps it, for sending back changed.
  Future<Map<String, dynamic>> movieRaw(int id) async =>
      Map<String, dynamic>.from(await _get('movie/$id') as Map);

  /// Saves a changed movie. [raw] is what [movieRaw] gave, edited.
  Future<void> updateMovie(Map<String, dynamic> raw) async {
    final id = _int(raw['id']);
    await _put('movie/$id', raw);
  }

  Future<void> setMovieMonitored(int id, bool monitored) async {
    final raw = await movieRaw(id);
    raw['monitored'] = monitored;
    await updateMovie(raw);
  }

  Future<void> searchMovie(int id) => command('MoviesSearch', {
    'movieIds': [id],
  });
  Future<void> refreshMovie(int id) => command('RefreshMovie', {
    'movieIds': [id],
  });

  Future<List<ArrSearchResult>> releasesForMovie(int id) =>
      _releases({'movieId': id});

  @override
  Future<List<ArrRename>> renamePreview(int id) async {
    final data = await _get('rename', {'movieId': id});
    return [
      for (final m in (data as List?) ?? const [])
        if (m is Map) ArrRename.fromJson(Map<String, dynamic>.from(m)),
    ];
  }

  @override
  Future<void> rename(int id, List<int> fileIds) =>
      command('RenameFiles', {'movieId': id, 'files': fileIds});

  /// Movies matching [term] (a name, or tmdb:12345, imdb:tt...), whether or
  /// not Radarr has them.
  Future<List<ArrLookup<ArrMovie>>> lookup(String term) async {
    final data = await _get('movie/lookup', {'term': term});
    return [
      for (final m in (data as List?) ?? const [])
        if (m is Map)
          ArrLookup(
            ArrMovie.fromJson(Map<String, dynamic>.from(m)),
            Map<String, dynamic>.from(m),
          ),
    ];
  }

  Future<ArrMovie> addMovie(
    Map<String, dynamic> lookupRaw, {
    required int qualityProfileId,
    required String rootFolderPath,
    required String monitor, // movieOnly, movieAndCollection, none
    required String minimumAvailability, // announced, inCinemas, released
    required bool search,
  }) async {
    final body = Map<String, dynamic>.from(lookupRaw)
      ..remove('id')
      ..['qualityProfileId'] = qualityProfileId
      ..['rootFolderPath'] = rootFolderPath
      ..['monitored'] = monitor != 'none'
      ..['minimumAvailability'] = minimumAvailability
      ..['addOptions'] = {'monitor': monitor, 'searchForMovie': search};
    return ArrMovie.fromJson(
      Map<String, dynamic>.from(await _post('movie', body) as Map),
    );
  }

  Future<void> deleteMovie(
    int id, {
    required bool deleteFiles,
    required bool addExclusion,
  }) => _delete('movie/$id', {
    'deleteFiles': deleteFiles,
    'addImportExclusion': addExclusion,
  });

  Future<void> deleteMovieFile(int id) => _delete('moviefile/$id');

  @override
  Future<List<ArrCalendarEntry>> calendar(DateTime start, DateTime end) async {
    final data = await _get('calendar', {
      'start': start.toUtc().toIso8601String(),
      'end': end.toUtc().toIso8601String(),
      'unmonitored': false,
    });
    return [
      for (final m in (data as List?) ?? const [])
        if (m is Map)
          ...ArrCalendarEntry.fromMovie(
            Map<String, dynamic>.from(m),
            start,
            end,
          ),
    ];
  }
}
