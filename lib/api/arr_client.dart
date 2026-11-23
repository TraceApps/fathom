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

/// Talks to one Sonarr, Radarr or Lidarr server over its API (v3, or v1 for
/// Lidarr), with its API key. [baseUrl] is what the user typed, including
/// any URL base ("/sonarr").
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

  String _api(String path) =>
      '$baseUrl/api/${kind == ArrKind.lidarr ? 'v1' : 'v3'}/$path';

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
    final key = switch (kind) {
      ArrKind.sonarr => 'renameEpisodes',
      ArrKind.radarr => 'renameMovies',
      ArrKind.lidarr => 'renameTracks',
    };
    return data is Map && data[key] == true;
  }

  /// Renames the files the preview listed.
  Future<void> rename(int id, List<int> fileIds);

  // One title (a show, a movie, an artist), the same way in every app.

  /// The title exactly as the app keeps it, for sending back changed.
  Future<Map<String, dynamic>> titleRaw(int id);

  /// Saves a changed title. [raw] is what [titleRaw] gave, edited. With
  /// [moveFiles], a changed path moves the title's folder there too.
  Future<void> updateTitle(Map<String, dynamic> raw, {bool moveFiles = false});

  /// Takes the title out of the app; with [deleteFiles] its files go too,
  /// and with [addExclusion] an import list won't add it back.
  Future<void> deleteTitle(
    int id, {
    required bool deleteFiles,
    required bool addExclusion,
  });

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
      switch (kind) {
        ArrKind.sonarr => 'seriesId',
        ArrKind.radarr => 'movieId',
        ArrKind.lidarr => 'artistId',
      }: ?titleId,
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
    switch (kind) {
      ArrKind.sonarr => 'episodefile/bulk',
      ArrKind.radarr => 'moviefile/bulk',
      // Lidarr's file editor takes another shape; nothing asks it yet.
      ArrKind.lidarr => throw UnsupportedError('Lidarr track files'),
    },
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
      ...switch (kind) {
        ArrKind.sonarr => {
          'includeSeries': true,
          'includeEpisode': true,
          'includeUnknownSeriesItems': true,
        },
        ArrKind.radarr => {
          'includeMovie': true,
          'includeUnknownMovieItems': true,
        },
        ArrKind.lidarr => {
          'includeArtist': true,
          'includeAlbum': true,
          'includeUnknownArtistItems': true,
        },
      },
    });
    final records = (data as Map?)?['records'];
    return [
      for (final m in (records as List?) ?? const [])
        if (m is Map) ArrQueueItem.fromJson(kind, Map<String, dynamic>.from(m)),
    ];
  }

  /// How many downloads the queue holds and whether one needs a look: the
  /// small answer behind the apps' own Activity count, so the count needn't
  /// download the whole queue.
  Future<({int count, bool problem})> queueStatus() async {
    final data = await _get('queue/status');
    final m = data is Map ? data : const {};
    return (
      count: (m['totalCount'] as num?)?.toInt() ?? 0,
      problem: [
        'errors',
        'warnings',
        'unknownErrors',
        'unknownWarnings',
      ].any((k) => m[k] == true),
    );
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
      ...switch (kind) {
        ArrKind.sonarr => {'includeSeries': true, 'includeEpisode': true},
        ArrKind.radarr => {'includeMovie': true},
        ArrKind.lidarr => {
          'includeArtist': true,
          'includeAlbum': true,
          'includeTrack': true,
        },
      },
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

  /// What the app did since [since], oldest first, each with its title
  /// (series and episode, movie, or artist and album), for notifications.
  Future<List<Map<String, dynamic>>> historySince(DateTime since) async {
    final data = await _get('history/since', {
      'date': since.toUtc().toIso8601String(),
      ...switch (kind) {
        ArrKind.sonarr => {'includeSeries': true, 'includeEpisode': true},
        ArrKind.radarr => {'includeMovie': true},
        ArrKind.lidarr => {'includeArtist': true, 'includeAlbum': true},
      },
    });
    return [
      for (final m in (data as List?) ?? const [])
        if (m is Map) Map<String, dynamic>.from(m),
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
    // Lidarr's "remote" link of a saved artist's picture is a path on its
    // own server (/config/MediaCover/...), not an address: its copy then.
    if (remote != null && remote.startsWith(RegExp('https?://'))) {
      return sizedImageUrl(remote, width);
    }
    final local = image.url;
    if (local == null || local.isEmpty) return null;
    // The app's own copy: its path already carries any URL base, so it
    // resolves against the server's origin.
    return Uri.parse(
      baseUrl,
    ).resolve(sizedLocalImageUrl(local, type, width)).toString();
  }

  /// The address of this title in the app's own web page. [titleSlug] is
  /// Lidarr's MusicBrainz id of the artist.
  String webUrl(String? titleSlug) {
    final where = switch (kind) {
      ArrKind.sonarr => 'series',
      ArrKind.radarr => 'movie',
      ArrKind.lidarr => 'artist',
    };
    return '$baseUrl/$where/${titleSlug ?? ''}';
  }
}

/// TMDB serves every size of a picture; the apps keep the "original" link,
/// which can be several megabytes. Asks for a sensible width instead. So
/// does the Cover Art Archive, behind Lidarr's album covers: 250, 500 or
/// 1200 pixels. Other sources (TheTVDB, fanart.tv) are left as they are.
@visibleForTesting
String sizedImageUrl(String url, int width) {
  final cover = RegExp(r'(coverartarchive\.org/.+)-(250|500|1200)\.jpg$');
  if (cover.hasMatch(url)) {
    final size = width <= 250 ? 250 : width <= 500 ? 500 : 1200;
    return url.replaceFirstMapped(cover, (m) => '${m[1]}-$size.jpg');
  }
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

/// The apps keep their copy of a picture at full size and, beside it,
/// smaller ones their own pages ask for: posters at 250 and 500 pixels,
/// backdrops at 180 and 360, banners at 35 and 70. The smallest that's wide
/// enough, or the full one when none is.
@visibleForTesting
String sizedLocalImageUrl(String url, String type, int width) {
  final sizes = switch (type) {
    'poster' => const [250, 500],
    'fanart' => const [180, 360],
    'banner' => const [35, 70],
    _ => const <int>[],
  };
  final size = sizes.where((s) => s >= width).firstOrNull;
  if (size == null) return url;
  // /MediaCover/12/poster.jpg?lastWrite=... -> /MediaCover/12/poster-500.jpg?...
  return url.replaceFirstMapped(
    RegExp('/$type(\\.[a-z]+)(\\?|\$)'),
    (m) => '/$type-$size${m[1]}${m[2]}',
  );
}

/// What to tell the user when the app answers with an error. Sonarr and Radarr
/// explain a refusal in `message`, or in a list of field errors.
@visibleForTesting
String arrErrorMessage(ArrKind kind, DioException e) =>
    arrAppErrorMessage(kind.appName, e);

/// [arrErrorMessage] for any of the apps by name (Prowlarr too).
String arrAppErrorMessage(String app, DioException e) {
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

  /// Import Library: adds shows already on disk, each in its own folder,
  /// in one go (Sonarr's series/import). [items] pairs a [lookup] entry with
  /// the folder it lives in.
  Future<void> importSeries(
    List<({Map<String, dynamic> lookupRaw, String path, String root})> items, {
    required int qualityProfileId,
    required String monitor,
    required String seriesType,
    required bool seasonFolder,
    required bool search,
    bool monitorNewSeasons = true,
  }) => _post('series/import', [
    for (final i in items)
      Map<String, dynamic>.from(i.lookupRaw)
        ..remove('id')
        ..['path'] = i.path
        ..['rootFolderPath'] = i.root
        ..['qualityProfileId'] = qualityProfileId
        ..['monitored'] = monitor != 'none'
        ..['monitorNewItems'] = monitorNewSeasons ? 'all' : 'none'
        ..['seriesType'] = seriesType
        ..['seasonFolder'] = seasonFolder
        ..['tags'] = const <int>[]
        ..['addOptions'] = {
          'monitor': monitor,
          'searchForMissingEpisodes': search,
          'searchForCutoffUnmetEpisodes': false,
        },
  ]);

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

  @override
  Future<Map<String, dynamic>> titleRaw(int id) => seriesRaw(id);

  @override
  Future<void> updateTitle(
    Map<String, dynamic> raw, {
    bool moveFiles = false,
  }) => updateSeries(raw, moveFiles: moveFiles);

  @override
  Future<void> deleteTitle(
    int id, {
    required bool deleteFiles,
    required bool addExclusion,
  }) => deleteSeries(id, deleteFiles: deleteFiles, addExclusion: addExclusion);

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
      if (m is! Map) continue;
      // By its id, not just the first: a server that didn't take the
      // filter answers with every show it has.
      final series = ArrSeries.fromJson(Map<String, dynamic>.from(m));
      if (series.tvdbId == tvdbId) return series;
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

  /// Import Library: adds movies already on disk, each in its own folder,
  /// in one go (Radarr's movie/import).
  Future<void> importMovies(
    List<({Map<String, dynamic> lookupRaw, String path, String root})> items, {
    required int qualityProfileId,
    required String monitor,
    required String minimumAvailability,
    required bool search,
  }) => _post('movie/import', [
    for (final i in items)
      Map<String, dynamic>.from(i.lookupRaw)
        ..remove('id')
        ..['path'] = i.path
        ..['rootFolderPath'] = i.root
        ..['qualityProfileId'] = qualityProfileId
        ..['monitored'] = monitor != 'none'
        ..['minimumAvailability'] = minimumAvailability
        ..['tags'] = const <int>[]
        ..['addOptions'] = {'monitor': monitor, 'searchForMovie': search},
  ]);

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

  @override
  Future<Map<String, dynamic>> titleRaw(int id) => movieRaw(id);

  @override
  Future<void> updateTitle(
    Map<String, dynamic> raw, {
    bool moveFiles = false,
  }) => updateMovie(raw, moveFiles: moveFiles);

  @override
  Future<void> deleteTitle(
    int id, {
    required bool deleteFiles,
    required bool addExclusion,
  }) => deleteMovie(id, deleteFiles: deleteFiles, addExclusion: addExclusion);

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
      if (m is! Map) continue;
      // By its id, not just the first: a server that didn't take the
      // filter answers with every movie it has.
      final movie = ArrMovie.fromJson(Map<String, dynamic>.from(m));
      if (movie.tmdbId == tmdbId) return movie;
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
    // Radarr keeps a release date as midnight UTC of its day and compares it
    // as a moment. Asked from local midnight, a movie out on the first day
    // would be left out anywhere west of UTC: the days are asked for as
    // UTC's. The last day comes back as well, and is dropped below.
    DateTime day(DateTime d) => DateTime.utc(d.year, d.month, d.day);
    final data = await _get('calendar', {
      'start': day(start).toIso8601String(),
      'end': day(end).toIso8601String(),
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

/// Lidarr: artists, their albums and the albums' tracks, over its v1 API.
class LidarrClient extends ArrClient {
  LidarrClient(String baseUrl, String apiKey, {super.dio})
    : super(ArrKind.lidarr, baseUrl, apiKey);

  Future<List<ArrArtist>> artists() async {
    final data = await _get('artist');
    return [
      for (final m in (data as List?) ?? const [])
        if (m is Map) ArrArtist.fromJson(Map<String, dynamic>.from(m)),
    ];
  }

  Future<ArrArtist> artist(int id) async => ArrArtist.fromJson(
    Map<String, dynamic>.from(await _get('artist/$id') as Map),
  );

  /// The artist Lidarr has for this MusicBrainz id, if it has it.
  Future<ArrArtist?> artistByMbId(String mbId) async {
    final data = await _get('artist', {'mbId': mbId});
    for (final m in (data as List?) ?? const []) {
      if (m is! Map) continue;
      // By its id, not just the first: a server that didn't take the
      // filter answers with every artist it has.
      final a = ArrArtist.fromJson(Map<String, dynamic>.from(m));
      if (a.foreignArtistId?.toLowerCase() == mbId.toLowerCase()) return a;
    }
    return null;
  }

  /// The artist's albums (as its metadata profile keeps them).
  Future<List<ArrAlbum>> albums(int artistId) async {
    final data = await _get('album', {'artistId': artistId});
    return [
      for (final m in (data as List?) ?? const [])
        if (m is Map) ArrAlbum.fromJson(Map<String, dynamic>.from(m)),
    ];
  }

  /// Artists matching [term] (a name, or `lidarr:` and a MusicBrainz id), whether
  /// or not Lidarr has them.
  Future<List<ArrLookup<ArrArtist>>> lookup(String term) async {
    final data = await _get('artist/lookup', {'term': term});
    return [
      for (final m in (data as List?) ?? const [])
        if (m is Map)
          ArrLookup(
            ArrArtist.fromJson(Map<String, dynamic>.from(m)),
            Map<String, dynamic>.from(m),
          ),
    ];
  }

  /// Adds an artist from a [lookup] entry. [monitor] is which of its albums
  /// Lidarr looks for (all, future, missing, existing, latest, first or
  /// none); [monitorNewItems] which ones added later (all, new or none).
  Future<ArrArtist> addArtist(
    Map<String, dynamic> lookupRaw, {
    required int qualityProfileId,
    required int metadataProfileId,
    required String rootFolderPath,
    required String monitor,
    required String monitorNewItems,
    required bool search,
    List<int> tags = const [],
  }) async {
    final body = Map<String, dynamic>.from(lookupRaw)
      ..remove('id')
      ..['qualityProfileId'] = qualityProfileId
      ..['metadataProfileId'] = metadataProfileId
      ..['rootFolderPath'] = rootFolderPath
      ..['monitored'] = monitor != 'none'
      ..['monitorNewItems'] = monitorNewItems
      ..['tags'] = tags
      ..['addOptions'] = {
        'monitor': monitor,
        'searchForMissingAlbums': search,
      };
    return ArrArtist.fromJson(
      Map<String, dynamic>.from(await _post('artist', body) as Map),
    );
  }

  /// One album, with its artist's name.
  Future<ArrAlbum> album(int id) async => ArrAlbum.fromJson(
    Map<String, dynamic>.from(await _get('album/$id') as Map),
  );

  /// An album's tracks, of the edition Lidarr is set to.
  Future<List<ArrTrack>> tracks(int albumId) async {
    final data = await _get('track', {'albumId': albumId});
    return [
      for (final m in (data as List?) ?? const [])
        if (m is Map) ArrTrack.fromJson(Map<String, dynamic>.from(m)),
    ];
  }

  /// The tracks of one edition of an album, which can differ from the
  /// edition Lidarr is set to (a deluxe release, another country's).
  Future<List<ArrTrack>> releaseTracks(int albumReleaseId) async {
    final data = await _get('track', {'albumReleaseId': albumReleaseId});
    return [
      for (final m in (data as List?) ?? const [])
        if (m is Map) ArrTrack.fromJson(Map<String, dynamic>.from(m)),
    ];
  }

  /// Every track file of the artist, by id.
  Future<List<ArrFile>> trackFiles(int artistId) async {
    final data = await _get('trackfile', {'artistId': artistId});
    return [
      for (final m in (data as List?) ?? const [])
        if (m is Map) ArrFile.fromJson(Map<String, dynamic>.from(m)),
    ];
  }

  /// The artist's latest events, newest first. From the whole history,
  /// filtered to the artist: Lidarr's own per-artist list leaves out the
  /// track and album each event was about (checked on Lidarr 3.1.6).
  Future<List<ArrHistoryItem>> history(int artistId) async {
    final data = await _get('history', {
      'page': 1,
      'pageSize': 100,
      'sortKey': 'date',
      'sortDirection': 'descending',
      'artistIds': artistId,
      'includeAlbum': true,
      'includeTrack': true,
    });
    return _page(data, (m) => ArrHistoryItem.fromJson(m, kind)).items;
  }

  Future<List<ArrMetadataProfile>> metadataProfiles() async {
    final data = await _get('metadataprofile');
    return [
      for (final m in (data as List?) ?? const [])
        if (m is Map) ArrMetadataProfile.fromJson(Map<String, dynamic>.from(m)),
    ];
  }

  @override
  Future<Map<String, dynamic>> titleRaw(int id) async =>
      Map<String, dynamic>.from(await _get('artist/$id') as Map);

  @override
  Future<void> updateTitle(
    Map<String, dynamic> raw, {
    bool moveFiles = false,
  }) async {
    final id = _int(raw['id']);
    await _send(
      'PUT',
      'artist/$id',
      body: raw,
      query: moveFiles ? {'moveFiles': true} : null,
    );
  }

  @override
  Future<void> deleteTitle(
    int id, {
    required bool deleteFiles,
    required bool addExclusion,
  }) => _delete('artist/$id', {
    'deleteFiles': deleteFiles,
    'addImportListExclusion': addExclusion,
  });

  /// Takes one album out of Lidarr (an artist's later refresh may bring it
  /// back unless [addExclusion]).
  Future<void> deleteAlbum(
    int id, {
    required bool deleteFiles,
    required bool addExclusion,
  }) => _delete('album/$id', {
    'deleteFiles': deleteFiles,
    'addImportListExclusion': addExclusion,
  });

  /// Changes which albums are monitored, the way Lidarr's Monitoring options
  /// do: [monitor] is all, future, missing, existing, latest, first or none,
  /// or null to leave the albums as they are. [monitored] is the artist's
  /// own switch (none turns it off whatever it says), and [newItems] which
  /// albums added later are monitored: all, none or new. One call: Lidarr
  /// saves the artist and its albums together.
  Future<void> applyMonitoring(
    int id, {
    required String? monitor,
    required bool monitored,
    String? newItems,
  }) => _post('albumstudio', {
    'artist': [
      {'id': id, 'monitored': monitored},
    ],
    if (monitor != null) 'monitoringOptions': {'monitor': monitor},
    'monitorNewItems': ?newItems,
  });

  Future<void> setAlbumsMonitored(List<int> ids, bool monitored) =>
      _put('album/monitor', {'albumIds': ids, 'monitored': monitored});

  Future<void> searchArtist(int id) =>
      command('ArtistSearch', {'artistId': id});
  Future<void> searchAlbums(List<int> ids) =>
      command('AlbumSearch', {'albumIds': ids});
  Future<void> refreshArtist(int id) =>
      command('RefreshArtist', {'artistId': id});

  Future<List<ArrSearchResult>> releasesForAlbum(int albumId) =>
      _releases({'albumId': albumId});

  Future<void> deleteTrackFiles(List<int> ids) =>
      _send('DELETE', 'trackfile/bulk', body: {'trackFileIds': ids});

  @override
  Future<List<ArrRename>> renamePreview(int id) async {
    final data = await _get('rename', {'artistId': id});
    return [
      for (final m in (data as List?) ?? const [])
        if (m is Map) ArrRename.fromJson(Map<String, dynamic>.from(m)),
    ];
  }

  @override
  Future<void> rename(int id, List<int> fileIds) =>
      command('RenameFiles', {'artistId': id, 'files': fileIds});

  @override
  Future<void> editMany(List<int> ids, Map<String, dynamic> changes) =>
      _put('artist/editor', {'artistIds': ids, ...changes});

  @override
  Future<void> deleteMany(
    List<int> ids, {
    required bool deleteFiles,
    required bool addExclusion,
  }) => _send(
    'DELETE',
    'artist/editor',
    body: {
      'artistIds': ids,
      'deleteFiles': deleteFiles,
      'addImportListExclusion': addExclusion,
    },
  );

  @override
  Future<void> refreshMany(List<int> ids) =>
      command('RefreshArtist', {'artistIds': ids});

  @override
  Future<void> renameMany(List<int> ids) =>
      command('RenameArtist', {'artistIds': ids});

  /// Lidarr's search takes one artist at a time. One that fails doesn't
  /// stop the others; the first failure is passed on after.
  @override
  Future<void> searchMany(List<int> ids) async {
    Object? failed;
    for (final id in ids) {
      try {
        await searchArtist(id);
      } catch (e) {
        failed ??= e;
      }
    }
    if (failed != null) throw failed;
  }

  /// Albums out between [start] and [end]. Lidarr keeps a release date as
  /// midnight UTC of its day, as Radarr does: the days are asked for as
  /// UTC's, and what falls outside them here is dropped.
  @override
  Future<List<ArrCalendarEntry>> calendar(
    DateTime start,
    DateTime end, {
    bool unmonitored = false,
  }) async {
    DateTime day(DateTime d) => DateTime.utc(d.year, d.month, d.day);
    final data = await _get('calendar', {
      'start': day(start).toIso8601String(),
      'end': day(end).toIso8601String(),
      'unmonitored': unmonitored,
      'includeArtist': true,
    });
    return [
      for (final m in (data as List?) ?? const [])
        if (m is Map)
          if (ArrCalendarEntry.fromAlbum(Map<String, dynamic>.from(m))
              case final e?
              when !e.date.isBefore(start) && e.date.isBefore(end))
            e,
    ];
  }

  Map<String, dynamic> _wantedQuery(int pageSize, {bool monitored = true}) =>
      {
        'page': 1,
        'pageSize': pageSize,
        'sortKey': 'releaseDate',
        'sortDirection': 'descending',
        'includeArtist': true,
        'monitored': monitored,
      };

  @override
  Future<ArrPage<ArrWantedItem>> missing({
    int pageSize = 50,
    bool monitored = true,
  }) async => _page(
    await _get('wanted/missing', _wantedQuery(pageSize, monitored: monitored)),
    ArrWantedItem.fromAlbum,
  );

  @override
  Future<ArrPage<ArrWantedItem>> cutoffUnmet({
    int pageSize = 50,
    bool monitored = true,
  }) async => _page(
    await _get('wanted/cutoff', _wantedQuery(pageSize, monitored: monitored)),
    ArrWantedItem.fromAlbum,
  );

  @override
  Future<void> searchAllMissing() =>
      command('MissingAlbumSearch', {'monitored': true});

  @override
  Future<void> searchAllCutoffUnmet() =>
      command('CutoffUnmetAlbumSearch', {'monitored': true});
}

/// [text] with the keys in any address it quotes hidden (apikey=, passkey=,
/// api_key=...): Prowlarr's test failures quote the indexer's own request.
String arrHideKeys(String text) => text.replaceAllMapped(
  RegExp(r'((?:api_?key|passkey|key|token)=)[^&\s\]\)]+', caseSensitive: false),
  (m) => '${m[1]}…',
);

/// Prowlarr: the indexers the other apps search through, over its v1 API.
/// Not one of the library apps, so it has no [ArrKind].
class ProwlarrClient {
  final String baseUrl;
  final String apiKey;
  final Dio _dio;

  ProwlarrClient(String baseUrl, this.apiKey, {Dio? dio})
    : baseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), ''),
      _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
            ),
          );

  static const appName = 'Prowlarr';

  Options get _opts => Options(headers: {'X-Api-Key': apiKey});
  String _api(String path) => '$baseUrl/api/v1/$path';

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Duration? wait,
  }) async {
    try {
      final r = await _dio.request(
        _api(path),
        data: body,
        queryParameters: query,
        options: _opts.copyWith(method: method, receiveTimeout: wait),
      );
      return r.data;
    } on DioException catch (e) {
      throw ArrException(arrAppErrorMessage(appName, e));
    }
  }

  Future<dynamic> _get(String path, [Map<String, dynamic>? query]) =>
      _send('GET', path, query: query);

  /// A request whose refusal carries an answer of its own (a test's
  /// failures): the error is left to the caller.
  Future<Response<dynamic>> _try(String method, String path, {Object? body}) =>
      _dio.request(
        _api(path),
        data: body,
        options: _opts.copyWith(
          method: method,
          receiveTimeout: const Duration(minutes: 3),
        ),
      );

  /// Which app answers at this address, and its version. Throws when it
  /// isn't Prowlarr.
  Future<ArrStatus> status() async {
    final data = await _get('system/status');
    if (data is! Map) {
      throw ArrException('$appName sent something unexpected.');
    }
    final s = ArrStatus.fromJson(Map<String, dynamic>.from(data));
    if (s.appName.isNotEmpty && s.appName.toLowerCase() != 'prowlarr') {
      throw ArrException('This address is ${s.appName}, not $appName.');
    }
    return s;
  }

  Future<List<ArrHealth>> health() async {
    final data = await _get('health');
    return [
      for (final m in (data as List?) ?? const [])
        if (m is Map) ArrHealth.fromJson(null, Map<String, dynamic>.from(m)),
    ];
  }

  Future<List<ProwlarrIndexer>> indexers() async {
    final data = await _get('indexer');
    return [
      for (final m in (data as List?) ?? const [])
        if (m is Map) ProwlarrIndexer.fromJson(Map<String, dynamic>.from(m)),
    ];
  }

  /// The indexers Prowlarr is holding back after failures.
  Future<List<ProwlarrIndexerStatus>> statuses() async {
    final data = await _get('indexerstatus');
    return [
      for (final m in (data as List?) ?? const [])
        if (m is Map)
          ProwlarrIndexerStatus.fromJson(Map<String, dynamic>.from(m)),
    ];
  }

  Future<List<ProwlarrIndexerStats>> stats() async {
    final data = await _get('indexerstats');
    return [
      for (final m in ((data as Map?)?['indexers'] as List?) ?? const [])
        if (m is Map) ProwlarrIndexerStats.fromJson(Map<String, dynamic>.from(m)),
    ];
  }

  /// What Prowlarr did lately, newest first.
  Future<ArrPage<ProwlarrHistoryItem>> history({int pageSize = 50}) async {
    final data = await _get('history', {
      'page': 1,
      'pageSize': pageSize,
      'sortKey': 'date',
      'sortDirection': 'descending',
    });
    final map = data is Map ? data : const {};
    return ArrPage([
      for (final m in (map['records'] as List?) ?? const [])
        if (m is Map) ProwlarrHistoryItem.fromJson(Map<String, dynamic>.from(m)),
    ], (map['totalRecords'] as num?)?.toInt() ?? 0);
  }

  /// Turns indexers on or off, several at once.
  Future<void> setEnabled(List<int> ids, bool enable) =>
      _send('PUT', 'indexer/bulk', body: {'ids': ids, 'enable': enable});

  /// Tests one indexer: null when it works, otherwise what's wrong.
  Future<List<String>?> test(ProwlarrIndexer i) async {
    try {
      await _try('POST', 'indexer/test', body: i.raw);
      return null;
    } on DioException catch (e) {
      final problems = _problems(e.response?.data);
      if (e.response?.statusCode == 400 && problems.isNotEmpty) {
        return problems;
      }
      throw ArrException(arrAppErrorMessage(appName, e));
    }
  }

  /// Tests every indexer. Prowlarr answers 400 when any fails, with the
  /// results still in the answer.
  Future<List<ProwlarrTestResult>> testAll() async {
    Object? data;
    try {
      data = (await _try('POST', 'indexer/testall')).data;
    } on DioException catch (e) {
      if (e.response?.statusCode != 400 || e.response?.data is! List) {
        throw ArrException(arrAppErrorMessage(appName, e));
      }
      data = e.response!.data;
    }
    return [
      for (final m in (data as List?) ?? const [])
        if (m is Map)
          (
            id: (m['id'] as num?)?.toInt() ?? 0,
            ok: m['isValid'] == true,
            problems: _problems(m['validationFailures']),
          ),
    ];
  }

  /// What a test found wrong: its errors, not its warnings, with any
  /// indexer's key in a quoted address hidden.
  static List<String> _problems(Object? v) => [
    for (final f in (v as List?) ?? const [])
      if (f is Map &&
          f['errorMessage'] is String &&
          f['isWarning'] != true &&
          f['severity'] != 'warning')
        arrHideKeys(f['errorMessage'] as String),
  ];

  /// Hands the indexers to the connected apps again (Prowlarr's Sync App
  /// Indexers).
  Future<void> syncApps() =>
      _send('POST', 'command', body: {'name': 'ApplicationIndexerSync'});

  /// Searches every enabled indexer (or [indexerIds]) for [query], in
  /// [categories] (Newznab's: 2000 movies, 5000 TV, 3000 audio...). Slow:
  /// Prowlarr waits for each indexer.
  Future<List<ProwlarrRelease>> search(
    String query, {
    List<int> categories = const [],
    List<int> indexerIds = const [],
    int limit = 100,
  }) async {
    final data = await _send(
      'GET',
      'search',
      query: {
        'query': query,
        'type': 'search',
        'limit': limit,
        'offset': 0,
        if (categories.isNotEmpty) 'categories': categories,
        if (indexerIds.isNotEmpty) 'indexerIds': indexerIds,
      },
      wait: const Duration(minutes: 3),
    );
    return [
      for (final m in (data as List?) ?? const [])
        if (m is Map) ProwlarrRelease.fromJson(Map<String, dynamic>.from(m)),
    ];
  }

  /// Sends a release to Prowlarr's own download client.
  Future<void> grab(ProwlarrRelease r) => _send(
    'POST',
    'search',
    body: {'guid': r.guid, 'indexerId': r.indexerId},
  );
}
