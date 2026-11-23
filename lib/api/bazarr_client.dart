import 'package:dio/dio.dart';

import '../models/arr.dart';
import 'arr_client.dart' show ArrException, arrAppErrorMessage;

// Bazarr, the subtitles app beside Sonarr and Radarr: what's missing, a
// search (Bazarr picks the best) or a manual one (every provider's results,
// scored), what it did, and how its providers are doing. Its API is
// Bazarr's own (1.x), at /api, with the key in X-API-KEY.

/// A subtitle language, as Bazarr names it.
class BazarrLanguage {
  final String name;

  /// "en".
  final String code;
  final bool forced;

  /// For the hard of hearing.
  final bool hi;

  const BazarrLanguage({
    required this.name,
    required this.code,
    this.forced = false,
    this.hi = false,
  });

  factory BazarrLanguage.fromJson(Map<String, dynamic> j) => BazarrLanguage(
    name: j['name'] as String? ?? '',
    code: j['code2'] as String? ?? '',
    forced: _bool(j['forced']),
    hi: _bool(j['hi']),
  );
}

/// An episode or a movie missing subtitles in one or more languages.
class BazarrWanted {
  /// Sonarr's series and episode ids, or Radarr's movie id.
  final int? seriesId;
  final int? episodeId;
  final int? movieId;

  /// The show's or the movie's title.
  final String title;

  /// "S01E02", for an episode.
  final String? episodeCode;
  final String? episodeTitle;
  final List<BazarrLanguage> missing;

  const BazarrWanted({
    this.seriesId,
    this.episodeId,
    this.movieId,
    required this.title,
    this.episodeCode,
    this.episodeTitle,
    this.missing = const [],
  });

  bool get isEpisode => episodeId != null;

  /// One of a kind, across episodes and movies.
  String get key => isEpisode ? 'e$episodeId' : 'm$movieId';

  factory BazarrWanted.fromEpisode(Map<String, dynamic> j) => BazarrWanted(
    seriesId: _int(j['sonarrSeriesId']),
    episodeId: _int(j['sonarrEpisodeId']),
    title: j['seriesTitle'] as String? ?? '',
    episodeCode: bazarrEpisodeCode(j['episode_number']),
    episodeTitle: j['episodeTitle'] as String?,
    missing: _languages(j['missing_subtitles']),
  );

  factory BazarrWanted.fromMovie(Map<String, dynamic> j) => BazarrWanted(
    movieId: _int(j['radarrId']),
    title: j['title'] as String? ?? '',
    missing: _languages(j['missing_subtitles']),
  );
}

/// Bazarr's "1x2" as "S01E02"; null for anything else.
String? bazarrEpisodeCode(Object? v) {
  final m = RegExp(r'^(\d+)x(\d+)$').firstMatch('${v ?? ''}');
  if (m == null) return null;
  return 'S${m[1]!.padLeft(2, '0')}E${m[2]!.padLeft(2, '0')}';
}

/// What Bazarr did, as its history numbers it (from its own source: the
/// history_log calls).
enum BazarrAction {
  deleted,
  downloaded,
  manual,
  upgraded,
  uploaded,
  synced,
  translated,
  extracted,
  other;

  static BazarrAction of(Object? v) => switch (_int(v)) {
    0 => deleted,
    1 => downloaded,
    2 => manual,
    3 => upgraded,
    4 => uploaded,
    5 => synced,
    6 => translated,
    7 => extracted,
    _ => other,
  };
}

/// One thing Bazarr did to an episode's or a movie's subtitles.
class BazarrHistoryItem {
  final BazarrAction action;
  final String title;
  final String? episodeCode;
  final String? episodeTitle;
  final BazarrLanguage? language;
  final String? provider;

  /// "90.56%", as Bazarr writes it.
  final String? score;

  /// Bazarr's own words for it, for an action this doesn't know.
  final String? description;

  /// When, on Bazarr's clock ("11/23/26 07:34:00").
  final DateTime? time;
  final int? seriesId;
  final int? movieId;

  const BazarrHistoryItem({
    required this.action,
    required this.title,
    this.episodeCode,
    this.episodeTitle,
    this.language,
    this.provider,
    this.score,
    this.description,
    this.time,
    this.seriesId,
    this.movieId,
  });

  factory BazarrHistoryItem.fromJson(Map<String, dynamic> j) =>
      BazarrHistoryItem(
        action: BazarrAction.of(j['action']),
        title: (j['seriesTitle'] ?? j['title']) as String? ?? '',
        episodeCode: bazarrEpisodeCode(j['episode_number']),
        episodeTitle: j['episodeTitle'] as String?,
        language: j['language'] is Map
            ? BazarrLanguage.fromJson(
                Map<String, dynamic>.from(j['language'] as Map),
              )
            : null,
        provider: _text(j['provider']),
        score: _text(j['score']),
        description: _text(j['description']),
        time: bazarrTime(j['parsed_timestamp']),
        seriesId: _int(j['sonarrSeriesId']),
        movieId: _int(j['radarrId']),
      );
}

/// Bazarr's "MM/DD/YY HH:MM:SS".
DateTime? bazarrTime(Object? v) {
  final m = RegExp(
    r'^(\d{1,2})/(\d{1,2})/(\d{2,4}) (\d{1,2}):(\d{2}):(\d{2})$',
  ).firstMatch('${v ?? ''}'.trim());
  if (m == null) return null;
  var year = int.parse(m[3]!);
  if (year < 100) year += 2000;
  final month = int.parse(m[1]!), day = int.parse(m[2]!);
  // Anything but month/day (a day first, say) is no date at all, rather
  // than a wrong one.
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  return DateTime(
    year,
    month,
    day,
    int.parse(m[4]!),
    int.parse(m[5]!),
    int.parse(m[6]!),
  );
}

/// A subtitle provider and how it's doing: "Good", or what went wrong and
/// when Bazarr tries it again.
class BazarrProvider {
  final String name;
  final String status;

  /// "in 10 minutes", or "-".
  final String? retry;

  const BazarrProvider({required this.name, required this.status, this.retry});

  bool get good => status.toLowerCase() == 'good';

  factory BazarrProvider.fromJson(Map<String, dynamic> j) => BazarrProvider(
    name: j['name'] as String? ?? '',
    status: j['status'] as String? ?? '',
    retry: _text(j['retry']) == '-' ? null : _text(j['retry']),
  );
}

/// One subtitle a manual search found.
class BazarrRelease {
  final String provider;

  /// Bazarr's token for it, sent back to download it.
  final String subtitle;

  /// 0 to 100.
  final int score;
  final List<String> releaseInfo;
  final List<String> matches;
  final List<String> dontMatches;
  final String language;
  final bool hi;
  final bool forced;
  final bool originalFormat;
  final String? uploader;
  final String? url;

  const BazarrRelease({
    required this.provider,
    required this.subtitle,
    required this.score,
    this.releaseInfo = const [],
    this.matches = const [],
    this.dontMatches = const [],
    this.language = '',
    this.hi = false,
    this.forced = false,
    this.originalFormat = false,
    this.uploader,
    this.url,
  });

  factory BazarrRelease.fromJson(Map<String, dynamic> j) => BazarrRelease(
    provider: j['provider'] as String? ?? '',
    subtitle: j['subtitle'] as String? ?? '',
    score: _int(j['score']) ?? 0,
    releaseInfo: _strings(j['release_info']),
    matches: _strings(j['matches']),
    dontMatches: _strings(j['dont_matches']),
    language: j['language'] as String? ?? '',
    hi: _bool(j['hearing_impaired']),
    forced: _bool(j['forced']),
    originalFormat: _bool(j['original_format']),
    uploader: _text(j['uploader']),
    url: _text(j['url']),
  );
}

class BazarrClient {
  final String baseUrl;
  final String apiKey;
  final Dio _dio;

  static const appName = 'Bazarr';

  BazarrClient(String baseUrl, this.apiKey, {Dio? dio})
    : baseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), ''),
      _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
            ),
          );

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? form,
    Duration? wait,
  }) async {
    try {
      final r = await _dio.request(
        '$baseUrl/api/$path',
        queryParameters: query,
        data: form,
        options: Options(
          method: method,
          headers: {'X-API-KEY': apiKey},
          contentType: form == null ? null : Headers.formUrlEncodedContentType,
          receiveTimeout: wait,
        ),
      );
      return r.data;
    } on DioException catch (e) {
      throw ArrException(arrAppErrorMessage(appName, e));
    }
  }

  static List<Map<String, dynamic>> _list(Object? data) => [
    if (data is Map && data['data'] is List)
      for (final m in data['data'] as List)
        if (m is Map) Map<String, dynamic>.from(m),
  ];

  static int _total(Object? data, int fallback) =>
      data is Map ? (_int(data['total']) ?? fallback) : fallback;

  /// Bazarr's version, after checking this address really is Bazarr.
  Future<String> version() async {
    final data = await _send('GET', 'system/status');
    final s = data is Map ? data['data'] : null;
    final v = s is Map ? s['bazarr_version'] : null;
    if (v is! String) {
      throw ArrException("This address doesn't answer as Bazarr.");
    }
    return v;
  }

  Future<List<ArrHealth>> health() async => [
    for (final h in _list(await _send('GET', 'system/health')))
      ArrHealth(
        kind: null,
        source: h['object'] as String? ?? '',
        type: 'warning',
        // What it's about (a root folder) and what's wrong.
        message: [
          ?_text(h['object']),
          ?_text(h['issue']),
        ].join(': '),
      ),
  ];

  /// Episodes and movies missing subtitles: the first [length] of each,
  /// and how many there are in all.
  Future<({List<BazarrWanted> items, int total})> wanted({
    int length = 50,
    bool episodes = true,
    bool movies = true,
  }) async {
    final r = await Future.wait([
      episodes
          ? _send('GET', 'episodes/wanted', query: {'length': length})
          : Future.value(null),
      movies
          ? _send('GET', 'movies/wanted', query: {'length': length})
          : Future.value(null),
    ]);
    final e = [for (final m in _list(r[0])) BazarrWanted.fromEpisode(m)];
    final m = [for (final x in _list(r[1])) BazarrWanted.fromMovie(x)];
    return (
      items: [...e, ...m],
      total: _total(r[0], e.length) + _total(r[1], m.length),
    );
  }

  /// What Bazarr did lately, the newest first, episodes and movies, and
  /// how many there are in all.
  Future<({List<BazarrHistoryItem> items, int total})> history({
    int length = 50,
    bool episodes = true,
    bool movies = true,
  }) async {
    final r = await Future.wait([
      episodes
          ? _send('GET', 'episodes/history', query: {'length': length})
          : Future.value(null),
      movies
          ? _send('GET', 'movies/history', query: {'length': length})
          : Future.value(null),
    ]);
    final e = _list(r[0]), m = _list(r[1]);
    final all = [
      for (final x in [...e, ...m]) BazarrHistoryItem.fromJson(x),
    ];
    // The newest first; those without a time last.
    all.sort((a, b) {
      final at = a.time, bt = b.time;
      if (at == null) return bt == null ? 0 : 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return (
      items: all,
      total: _total(r[0], e.length) + _total(r[1], m.length),
    );
  }

  Future<List<BazarrProvider>> providers() async => [
    for (final p in _list(await _send('GET', 'providers')))
      BazarrProvider.fromJson(p),
  ];

  /// Lets every provider be tried again now, throttled or not.
  Future<void> resetProviders() =>
      _send('POST', 'providers', query: {'action': 'reset'});

  /// Has Bazarr search for [language] and keep the best it finds. Bazarr
  /// queues it: it's done a moment later.
  Future<void> search(BazarrWanted w, BazarrLanguage language) => _send(
    'PATCH',
    w.isEpisode ? 'episodes/subtitles' : 'movies/subtitles',
    query: {
      if (w.isEpisode) ...{'seriesid': w.seriesId, 'episodeid': w.episodeId},
      if (!w.isEpisode) 'radarrid': w.movieId,
      'language': language.code,
      'forced': _py(language.forced),
      'hi': _py(language.hi),
    },
  );

  /// Every provider's subtitles for [w], the best first.
  Future<List<BazarrRelease>> manualSearch(BazarrWanted w) async {
    final data = await _send(
      'GET',
      w.isEpisode ? 'providers/episodes' : 'providers/movies',
      query: w.isEpisode
          ? {'episodeid': w.episodeId}
          : {'radarrid': w.movieId},
      // It waits on every provider.
      wait: const Duration(minutes: 3),
    );
    final list = [for (final m in _list(data)) BazarrRelease.fromJson(m)];
    list.sort((a, b) => b.score.compareTo(a.score));
    return list;
  }

  /// Downloads one subtitle a manual search found. Queued, as a search is.
  /// What to download goes as a form, as Bazarr's own page sends it: an
  /// older Bazarr's token is kilobytes long, too long for an address
  /// behind some proxies.
  Future<void> download(BazarrWanted w, BazarrRelease r) => _send(
    'POST',
    w.isEpisode ? 'providers/episodes' : 'providers/movies',
    query: {
      if (w.isEpisode) ...{'seriesid': w.seriesId, 'episodeid': w.episodeId},
      if (!w.isEpisode) 'radarrid': w.movieId,
    },
    form: {
      'hi': _py(r.hi),
      'forced': _py(r.forced),
      'original_format': _py(r.originalFormat),
      'provider': r.provider,
      'subtitle': r.subtitle,
    },
  );

  /// Searches for everything missing, episodes and movies (Bazarr's own
  /// Search All tasks).
  Future<void> searchAllWanted() async {
    await _send(
      'POST',
      'system/tasks',
      query: {'taskid': 'wanted_search_missing_subtitles_series'},
    );
    await _send(
      'POST',
      'system/tasks',
      query: {'taskid': 'wanted_search_missing_subtitles_movies'},
    );
  }
}

/// Bazarr reads its yes and no as Python writes them.
String _py(bool b) => b ? 'True' : 'False';

bool _bool(Object? v) => v == true || '$v'.toLowerCase() == 'true';

int? _int(Object? v) => switch (v) {
  num n => n.toInt(),
  String s => int.tryParse(s),
  _ => null,
};

String? _text(Object? v) => v is String && v.trim().isNotEmpty ? v : null;

List<String> _strings(Object? v) => [
  for (final s in (v as List?) ?? const [])
    if (s is String) s,
];

List<BazarrLanguage> _languages(Object? v) => [
  for (final m in (v as List?) ?? const [])
    if (m is Map) BazarrLanguage.fromJson(Map<String, dynamic>.from(m)),
];
