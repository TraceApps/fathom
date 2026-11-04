import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/arr.dart';

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
