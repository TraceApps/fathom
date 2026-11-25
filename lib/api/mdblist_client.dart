import 'package:dio/dio.dart';

/// Ratings for one title from MDBList, each a normalized 0-100 score (null when
/// that source has no rating). MDBList aggregates sources that have no API of
/// their own (Letterboxd, etc.) on its servers and exposes them behind one key.
typedef MdbRatings = ({
  int? rtCritic, // tomatoes
  int? rtAudience, // tomatoesaudience
  int? imdb,
  int? tmdb,
  int? letterboxd,
  int? metacritic,
  int? metacriticUser,
  int? trakt,
  int? rogerEbert,
  int? myAnimeList,
});

class MdbListException implements Exception {
  final String message;
  MdbListException(this.message);
  @override
  String toString() => message;
}

/// Reads aggregated ratings from MDBList by TMDB id. Best-effort: any failure
/// (bad key, no match, network) returns null so the UI simply shows nothing
/// extra, never an error.
class MdbListClient {
  final String apiKey;
  final Dio _dio;

  MdbListClient(this.apiKey, {Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ));

  static const appName = 'MDBList';

  /// Asks MDBList whether it takes the key; throws with why when it doesn't.
  Future<void> check() async {
    try {
      await _dio.get<dynamic>(
        'https://api.mdblist.com/user',
        queryParameters: {'apikey': apiKey},
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        throw MdbListException('$appName rejected the API key.');
      }
      if (code == 429) {
        throw MdbListException("$appName's limit for today is used up.");
      }
      if (e.response == null) {
        throw MdbListException('Could not reach $appName.');
      }
      throw MdbListException('$appName error ($code).');
    }
  }

  Future<MdbRatings?> ratings({
    required String mediaType, // 'movie' | 'tv'
    required int tmdbId,
  }) async {
    try {
      final type = mediaType == 'tv' ? 'show' : 'movie';
      final res = await _dio.get<Map<String, dynamic>>(
        'https://api.mdblist.com/tmdb/$type/$tmdbId',
        queryParameters: {'apikey': apiKey},
      );
      final list = res.data?['ratings'];
      if (list is! List) return null;
      // Prefer the normalized 0-100 `score`; the raw `value` scale varies by
      // source, so it isn't safe to display directly.
      final by = <String, int>{};
      for (final r in list) {
        if (r is! Map) continue;
        final source = r['source'];
        final score = r['score'] ?? r['value'];
        if (source is String && score is num) by[source] = score.round();
      }
      return (
        rtCritic: by['tomatoes'],
        rtAudience: by['tomatoesaudience'],
        imdb: by['imdb'],
        tmdb: by['tmdb'],
        letterboxd: by['letterboxd'],
        metacritic: by['metacritic'],
        metacriticUser: by['metacriticuser'],
        trakt: by['trakt'],
        rogerEbert: by['rogerebert'],
        myAnimeList: by['myanimelist'],
      );
    } catch (_) {
      return null;
    }
  }
}
