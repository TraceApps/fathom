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
  /// With [changeCategory] (and not [removeFromClient]) the client moves it
  /// to its post-import category instead, keeping the data (to seed on).
  Future<void> removeFromQueue(
    int id, {
    required bool removeFromClient,
    required bool blocklist,
    bool searchAgain = false,
    bool changeCategory = false,
  }) => _delete('queue/$id', {
    'removeFromClient': removeFromClient,
    if (changeCategory) 'changeCategory': true,
    'blocklist': blocklist,
    if (blocklist) 'skipRedownload': !searchAgain,
  });

  /// Sends a download held back by a delay profile to the client now.
  Future<void> grabFromQueue(int id) => _post('queue/grab/$id', null);

  /// [removeFromQueue] for several at once.
  Future<void> removeManyFromQueue(
    List<int> ids, {
    required bool removeFromClient,
    required bool blocklist,
    bool searchAgain = false,
    bool changeCategory = false,
  }) => _send(
    'DELETE',
    'queue/bulk',
    query: {
      'removeFromClient': removeFromClient,
      if (changeCategory) 'changeCategory': true,
      'blocklist': blocklist,
      if (blocklist) 'skipRedownload': !searchAgain,
    },
    body: {'ids': ids},
  );

  /// Releases the app won't grab again, newest first.
  Future<ArrPage<ArrBlocklistItem>> blocklist({int pageSize = 50}) async {
    final data = await _get('blocklist', {
      'page': 1,
      'pageSize': pageSize,
      'sortKey': 'date',
      'sortDirection': 'descending',
    });
    return _page(data, (m) => ArrBlocklistItem.fromJson(kind, m));
  }

  /// Takes releases off the blocklist, so the app may grab them again.
  Future<void> removeFromBlocklist(List<int> ids) => ids.length == 1
      ? _delete('blocklist/${ids.single}')
      : _send('DELETE', 'blocklist/bulk', body: {'ids': ids});

  /// Empties the blocklist.
  Future<void> clearBlocklist() => command('ClearBlocklist');

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

  // Several titles at once, as the apps' select mode does.

  /// Changes settings on several titles. [changes] holds only what changes:
  /// monitored, qualityProfileId, rootFolderPath (with moveFiles), tags with
  /// applyTags (add, remove, replace), and each app's own fields.
  Future<void> editMany(List<int> ids, Map<String, dynamic> changes);

  Future<void> deleteMany(
    List<int> ids, {
    required bool deleteFiles,
    required bool addExclusion,
  });

  Future<void> refreshMany(List<int> ids);
  Future<void> renameMany(List<int> ids);
  Future<void> searchMany(List<int> ids);

  /// Every tag on the server, by id.
  Future<List<ArrTag>> tags() async {
    final data = await _get('tag');
    return [
      for (final m in (data as List?) ?? const [])
        if (m is Map) ArrTag.fromJson(Map<String, dynamic>.from(m)),
    ]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  }

  /// Makes a tag (the apps keep labels lowercase and unique; an existing
  /// label comes back as the existing tag).
  Future<ArrTag> createTag(String label) async => ArrTag.fromJson(
    Map<String, dynamic>.from(
      await _post('tag', {'label': label.trim()}) as Map,
    ),
  );

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

  // ------------------------------------------------------- Manual Import

  /// The video files Manual Import finds: in a download ([downloadId]), a
  /// folder on the server ([folder]), or with [titleId] a show's or movie's
  /// own folder. [filterExisting] leaves out files already in the library.
  Future<List<ArrImportItem>> importFiles({
    String? downloadId,
    String? folder,
    int? titleId,
    bool filterExisting = true,
  }) async {
    final data = await _get('manualimport', {
      'downloadId': ?downloadId,
      'folder': ?folder,
      kind == ArrKind.sonarr ? 'seriesId' : 'movieId': ?titleId,
      'filterExistingFiles': filterExisting,
    });
    return [
      for (final m in (data as List?) ?? const [])
        if (m is Map) ArrImportItem.fromJson(kind, Map<String, dynamic>.from(m)),
    ];
  }

  /// Has the app look at [items] again after a change (a show, season,
  /// movie, quality): it works out the episodes and says what it thinks now.
  Future<List<ArrImportItem>> recheckImport(List<ArrImportItem> items) async {
    final data = await _post('manualimport', [
      for (final i in items) i.toReprocessJson(),
    ]);
    return [
      for (final m in (data as List?) ?? const [])
        if (m is Map) ArrImportItem.fromJson(kind, Map<String, dynamic>.from(m)),
    ];
  }

  /// Imports [items] as they are now. [mode]: auto (a download: as the app's
  /// settings say), move or copy (a folder).
  Future<void> manualImport(List<ArrImportItem> items, String mode) =>
      command('ManualImport', {
        'importMode': mode,
        'files': [for (final i in items) i.toCommandJson()],
      });

  /// Changes the quality, languages or release group of files already in
  /// the library. Each map has the file's id and what changes.
  Future<void> updateFiles(List<Map<String, dynamic>> files) => _put(
    kind == ArrKind.sonarr ? 'episodefile/bulk' : 'moviefile/bulk',
    files,
  );

  /// The languages a file can be marked with.
  Future<List<ArrLanguage>> languages() async {
    final data = await _get('language');
    return [
      for (final m in (data as List?) ?? const [])
        if (m is Map) ArrLanguage.fromJson(Map<String, dynamic>.from(m)),
    ];
  }

  /// Every quality a file can be, worst to best, as the app ranks them.
  Future<List<ArrQualityChoice>> qualities() async {
    final data = await _get('qualitydefinition');
    final list = [
      for (final m in (data as List?) ?? const [])
        if (m is Map) Map<String, dynamic>.from(m),
    ]..sort((a, b) => _int(a['weight']).compareTo(_int(b['weight'])));
    return [for (final m in list) ArrQualityChoice.fromJson(m)];
  }

  /// The folders in [path] on the app's server ('' for the top: drives or /).
  Future<ArrFolderListing> folders(String path) async {
    final data = await _get('filesystem', {
      'path': path,
      'includeFiles': false,
      'allowFoldersWithoutTrailingSlashes': true,
    });
    return ArrFolderListing.fromJson(
      path,
      Map<String, dynamic>.from((data as Map?) ?? const {}),
    );
  }

  Future<List<ArrQualityProfile>> qualityProfiles() async {
    final data = await _get('qualityprofile');
    return [
      for (final m in (data as List?) ?? const [])
        if (m is Map) ArrQualityProfile.fromJson(Map<String, dynamic>.from(m)),
    ];
  }

  /// Everything in the queue, with the title it belongs to. Downloads the
  /// app couldn't match to a title come too, as on the apps' own queue:
  /// they're the ones that need Manual Import.
  Future<List<ArrQueueItem>> queue() async {
    final data = await _get('queue', {
      'page': 1,
      'pageSize': 500,
      if (kind == ArrKind.sonarr) ...{
        'includeSeries': true,
        'includeEpisode': true,
        'includeUnknownSeriesItems': true,
      } else ...{
        'includeMovie': true,
        'includeUnknownMovieItems': true,
      },
    });
    final records = (data as Map?)?['records'];
    return [
      for (final m in (records as List?) ?? const [])
        if (m is Map) ArrQueueItem.fromJson(kind, Map<String, dynamic>.from(m)),
    ];
  }

  /// What's airing or being released between [start] and [end].
  /// What's coming up; with [unmonitored], unmonitored titles too.
  Future<List<ArrCalendarEntry>> calendar(
    DateTime start,
    DateTime end, {
    bool unmonitored = false,
  });

  /// Titles with nothing downloaded yet that are out, newest first: the
  /// monitored ones, or with [monitored] false the unmonitored ones.
  Future<ArrPage<ArrWantedItem>> missing({
    int pageSize = 50,
    bool monitored = true,
  });

  /// Titles below their quality profile's cutoff (monitored, or not).
  Future<ArrPage<ArrWantedItem>> cutoffUnmet({
    int pageSize = 50,
    bool monitored = true,
  });

  /// Searches for everything missing, or everything below its cutoff. Runs
  /// on the server and can take a while on a big library.
  Future<void> searchAllMissing();
  Future<void> searchAllCutoffUnmet();

  /// What the app has done lately across the whole library, newest first.
  /// With [only], just those kinds of events.
  Future<ArrPage<ArrHistoryItem>> recentHistory({
    int pageSize = 50,
    ArrHistoryFilter only = ArrHistoryFilter.all,
  }) async {
    final types = arrHistoryEventTypes(kind, only);
    final data = await _get('history', {
      'page': 1,
      'pageSize': pageSize,
      'sortKey': 'date',
      'sortDirection': 'descending',
      if (types.isNotEmpty) 'eventType': types,
      if (kind == ArrKind.sonarr) ...{
        'includeSeries': true,
        'includeEpisode': true,
      } else
        'includeMovie': true,
    });
    return _page(data, (m) => ArrHistoryItem.fromJson(m, kind));
  }

  /// Marks a grab as failed: the app blocklists the release and, if it's
  /// set to, searches for another.
  Future<void> markFailed(int historyId) =>
      _post('history/failed/$historyId', null);

  /// What the app's health check has found right now.
  Future<List<ArrHealth>> health() async {
    final data = await _get('health');
    return [
      for (final m in (data as List?) ?? const [])
        if (m is Map) ArrHealth.fromJson(kind, Map<String, dynamic>.from(m)),
    ];
  }

  ArrPage<T> _page<T>(Object? data, T Function(Map<String, dynamic> m) parse) {
    final map = data is Map ? data : const {};
    final records = [
      for (final m in (map['records'] as List?) ?? const [])
        if (m is Map) parse(Map<String, dynamic>.from(m)),
    ];
    return ArrPage(records, _int(map['totalRecords']));
  }

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

  /// Saves a changed show. [raw] is what [seriesRaw] gave, edited. With
  /// [moveFiles], a changed path moves the show's folder there too.
  Future<void> updateSeries(
    Map<String, dynamic> raw, {
    bool moveFiles = false,
  }) async {
    final id = _int(raw['id']);
    await _send(
      'PUT',
      'series/$id',
      body: raw,
      query: moveFiles ? {'moveFiles': true} : null,
    );
  }

  /// Changes which episodes are monitored, the way Sonarr's Monitoring
  /// options do: [monitor] is all, future, missing, existing, recent, pilot,
  /// firstSeason, lastSeason, monitorSpecials, unmonitorSpecials or none.
  /// [monitored] is the show's own switch, sent with it because the options
  /// leave it alone (only none turns it off).
  Future<void> applyMonitoring(
    int id, {
    required String monitor,
    required bool monitored,
  }) => _post('seasonpass', {
    'series': [
      {'id': id, 'monitored': monitored},
    ],
    'monitoringOptions': {'monitor': monitor},
  });

  /// Deletes episode files from disk, several at once.
  Future<void> deleteEpisodeFiles(List<int> ids) =>
      _send('DELETE', 'episodefile/bulk', body: {'episodeFileIds': ids});

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
    bool searchCutoff = false,
    bool monitorNewSeasons = true,
    List<int> tags = const [],
    String? path,
  }) async {
    final body = Map<String, dynamic>.from(lookupRaw)
      ..remove('id')
      ..['qualityProfileId'] = qualityProfileId
      ..['rootFolderPath'] = rootFolderPath
      ..['monitored'] = monitor != 'none'
      ..['monitorNewItems'] = monitorNewSeasons ? 'all' : 'none'
      ..['seriesType'] = seriesType
      ..['seasonFolder'] = seasonFolder
      ..['tags'] = tags
      ..['addOptions'] = {
        'monitor': monitor,
        'searchForMissingEpisodes': search,
        'searchForCutoffUnmetEpisodes': searchCutoff,
      };
    // An existing folder on disk: the app uses it (and the files in it)
    // instead of making a new one from its naming rules.
    if (path != null) body['path'] = path;
    return ArrSeries.fromJson(
      Map<String, dynamic>.from(await _post('series', body) as Map),
    );
  }

  @override
  Future<void> editMany(List<int> ids, Map<String, dynamic> changes) =>
      _put('series/editor', {'seriesIds': ids, ...changes});

  @override
  Future<void> deleteMany(
    List<int> ids, {
    required bool deleteFiles,
    required bool addExclusion,
  }) => _send(
    'DELETE',
    'series/editor',
    body: {
      'seriesIds': ids,
      'deleteFiles': deleteFiles,
      'addImportListExclusion': addExclusion,
    },
  );

  @override
  Future<void> refreshMany(List<int> ids) =>
      command('RefreshSeries', {'seriesIds': ids});

  @override
  Future<void> renameMany(List<int> ids) =>
      command('RenameSeries', {'seriesIds': ids});

  /// Sonarr's search takes one show at a time.
  @override
  Future<void> searchMany(List<int> ids) async {
    for (final id in ids) {
      await searchSeries(id);
    }
  }

  /// One Monitoring choice for several shows (see [applyMonitoring]). Each
  /// show keeps its own switch (Sonarr leaves it alone when it isn't sent),
  /// except None, which turns it off.
  Future<void> applyMonitoringMany(List<int> ids, String monitor) =>
      _post('seasonpass', {
        'series': [
          for (final id in ids)
            {'id': id, if (monitor == 'none') 'monitored': false},
        ],
        'monitoringOptions': {'monitor': monitor},
      });

  Future<void> deleteSeries(
    int id, {
    required bool deleteFiles,
    required bool addExclusion,
  }) => _delete('series/$id', {
    'deleteFiles': deleteFiles,
    'addImportListExclusion': addExclusion,
  });

  Future<void> deleteEpisodeFile(int id) => _delete('episodefile/$id');

  /// The show Sonarr has for this TVDB id, if it has it.
  Future<ArrSeries?> seriesByTvdb(int tvdbId) async {
    final data = await _get('series', {'tvdbId': tvdbId});
    for (final m in (data as List?) ?? const []) {
      if (m is Map) return ArrSeries.fromJson(Map<String, dynamic>.from(m));
    }
    return null;
  }

  Map<String, dynamic> _wantedQuery(
    int pageSize, {
    bool cutoff = false,
    bool monitored = true,
  }) => {
    'page': 1,
    'pageSize': pageSize,
    'sortKey': 'episodes.airDateUtc',
    'sortDirection': 'descending',
    'includeSeries': true,
    if (cutoff) 'includeEpisodeFile': true,
    'monitored': monitored,
  };

  @override
  Future<ArrPage<ArrWantedItem>> missing({
    int pageSize = 50,
    bool monitored = true,
  }) async => _page(
    await _get('wanted/missing', _wantedQuery(pageSize, monitored: monitored)),
    ArrWantedItem.fromEpisode,
  );

  @override
  Future<ArrPage<ArrWantedItem>> cutoffUnmet({
    int pageSize = 50,
    bool monitored = true,
  }) async => _page(
        await _get(
          'wanted/cutoff',
          _wantedQuery(pageSize, cutoff: true, monitored: monitored),
        ),
        ArrWantedItem.fromEpisode,
      );

  @override
  Future<void> searchAllMissing() =>
      command('MissingEpisodeSearch', {'monitored': true});

  @override
  Future<void> searchAllCutoffUnmet() =>
      command('CutoffUnmetEpisodeSearch', {'monitored': true});

  @override
  Future<List<ArrCalendarEntry>> calendar(
    DateTime start,
    DateTime end, {
    bool unmonitored = false,
  }) async {
    final data = await _get('calendar', {
      'start': start.toUtc().toIso8601String(),
      'end': end.toUtc().toIso8601String(),
      'includeSeries': true,
      'unmonitored': unmonitored,
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

  /// Saves a changed movie. [raw] is what [movieRaw] gave, edited. With
  /// [moveFiles], a changed path moves the movie's folder there too.
  Future<void> updateMovie(
    Map<String, dynamic> raw, {
    bool moveFiles = false,
  }) async {
    final id = _int(raw['id']);
    await _send(
      'PUT',
      'movie/$id',
      body: raw,
      query: moveFiles ? {'moveFiles': true} : null,
    );
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
    List<int> tags = const [],
    String? path,
  }) async {
    final body = Map<String, dynamic>.from(lookupRaw)
      ..remove('id')
      ..['qualityProfileId'] = qualityProfileId
      ..['rootFolderPath'] = rootFolderPath
      ..['monitored'] = monitor != 'none'
      ..['minimumAvailability'] = minimumAvailability
      ..['tags'] = tags
      ..['addOptions'] = {'monitor': monitor, 'searchForMovie': search};
    if (path != null) body['path'] = path;
    return ArrMovie.fromJson(
      Map<String, dynamic>.from(await _post('movie', body) as Map),
    );
  }

  @override
  Future<void> editMany(List<int> ids, Map<String, dynamic> changes) =>
      _put('movie/editor', {'movieIds': ids, ...changes});

  @override
  Future<void> deleteMany(
    List<int> ids, {
    required bool deleteFiles,
    required bool addExclusion,
  }) => _send(
    'DELETE',
    'movie/editor',
    body: {
      'movieIds': ids,
      'deleteFiles': deleteFiles,
      'addImportExclusion': addExclusion,
    },
  );

  @override
  Future<void> refreshMany(List<int> ids) =>
      command('RefreshMovie', {'movieIds': ids});

  @override
  Future<void> renameMany(List<int> ids) =>
      command('RenameMovie', {'movieIds': ids});

  @override
  Future<void> searchMany(List<int> ids) =>
      command('MoviesSearch', {'movieIds': ids});

  Future<void> deleteMovie(
    int id, {
    required bool deleteFiles,
    required bool addExclusion,
  }) => _delete('movie/$id', {
    'deleteFiles': deleteFiles,
    'addImportExclusion': addExclusion,
  });

  Future<void> deleteMovieFile(int id) => _delete('moviefile/$id');

  Future<List<ArrCollection>> collections() async {
    final data = await _get('collection');
    return [
      for (final m in (data as List?) ?? const [])
        if (m is Map) ArrCollection.fromJson(Map<String, dynamic>.from(m)),
    ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }

  /// The collection exactly as Radarr keeps it, for sending back changed.
  Future<Map<String, dynamic>> collectionRaw(int id) async =>
      Map<String, dynamic>.from(await _get('collection/$id') as Map);

  Future<void> updateCollection(Map<String, dynamic> raw) {
    final id = _int(raw['id']);
    return _put('collection/$id', raw);
  }

  /// Has Radarr bring collections up to date now, which is also when a
  /// monitored one gets its missing movies added (otherwise that waits for
  /// Radarr's scheduled refresh). Empty [ids]: all of them.
  Future<void> refreshCollections([List<int> ids = const []]) => command(
    'RefreshCollections',
    {if (ids.isNotEmpty) 'collectionIds': ids},
  );

  /// The movie Radarr has for this TMDB id, if it has it.
  Future<ArrMovie?> movieByTmdb(int tmdbId) async {
    final data = await _get('movie', {'tmdbId': tmdbId});
    for (final m in (data as List?) ?? const []) {
      if (m is Map) return ArrMovie.fromJson(Map<String, dynamic>.from(m));
    }
    return null;
  }

  Map<String, dynamic> _wantedQuery(
    int pageSize, {
    bool cutoff = false,
    bool monitored = true,
  }) => {
    'page': 1,
    'pageSize': pageSize,
    'sortKey': 'movieMetadata.digitalRelease',
    'sortDirection': 'descending',
    'monitored': monitored,
  };

  @override
  Future<ArrPage<ArrWantedItem>> missing({
    int pageSize = 50,
    bool monitored = true,
  }) async => _page(
    await _get('wanted/missing', _wantedQuery(pageSize, monitored: monitored)),
    ArrWantedItem.fromMovie,
  );

  @override
  Future<ArrPage<ArrWantedItem>> cutoffUnmet({
    int pageSize = 50,
    bool monitored = true,
  }) async => _page(
        await _get(
          'wanted/cutoff',
          _wantedQuery(pageSize, cutoff: true, monitored: monitored),
        ),
        ArrWantedItem.fromMovie,
      );

  @override
  Future<void> searchAllMissing() =>
      command('MissingMoviesSearch', {'monitored': true});

  @override
  Future<void> searchAllCutoffUnmet() =>
      command('CutoffUnmetMoviesSearch', {'monitored': true});

  @override
  Future<List<ArrCalendarEntry>> calendar(
    DateTime start,
    DateTime end, {
    bool unmonitored = false,
  }) async {
    final data = await _get('calendar', {
      'start': start.toUtc().toIso8601String(),
      'end': end.toUtc().toIso8601String(),
      'unmonitored': unmonitored,
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
