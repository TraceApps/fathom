import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/seerr_detail.dart';
import '../models/seerr_genre.dart';
import '../models/seerr_person.dart';
import '../models/seerr_request.dart';
import '../models/seerr_options.dart';
import '../models/seerr_result.dart';

class SeerrException implements Exception {
  final String message;
  SeerrException(this.message);
  @override
  String toString() => message;
}

/// Resolves a Seerr avatar value to a full URL. Jellyseerr returns either a
/// relative path (e.g. `/avatarproxy/…`, served by the instance) or an absolute
/// Gravatar URL. Returns null when there's nothing to show.
String? seerrAvatarUrl(String baseUrl, String? raw) {
  if (raw == null || raw.isEmpty) return null;
  if (raw.startsWith('http')) return raw;
  return '$baseUrl${raw.startsWith('/') ? raw : '/$raw'}';
}

/// Signs in to a Seerr instance with Jellyfin credentials and returns the
/// session cookie (connect.sid=...), for cookie-based auth. First-time sign-in
/// creates/links the matching Seerr account. Throws on failure.
Future<String> seerrJellyfinLogin(
  String baseUrl, {
  required String username,
  required String password,
  String? hostname,
}) => _seerrCookieLogin(baseUrl, '/api/v1/auth/jellyfin', {
  'username': username,
  'password': password,
  if (hostname != null && hostname.isNotEmpty) 'hostname': hostname,
});

/// Signs in to a Seerr instance with a local Seerr account (email + password),
/// for users whose Seerr account isn't linked to Jellyfin. Returns the session
/// cookie. Throws on failure.
Future<String> seerrLocalLogin(
  String baseUrl, {
  required String email,
  required String password,
}) => _seerrCookieLogin(baseUrl, '/api/v1/auth/local', {
  'email': email,
  'password': password,
});

/// Posts credentials to a Seerr auth endpoint and returns the connect.sid
/// session cookie. Shared by the Jellyfin and local sign-in paths.
Future<String> _seerrCookieLogin(
  String baseUrl,
  String path,
  Map<String, dynamic> data,
) async {
  final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 12)));
  try {
    final res = await dio.post('$baseUrl$path', data: data);
    final setCookies = res.headers['set-cookie'] ?? const [];
    for (final c in setCookies) {
      final pair = c.split(';').first.trim();
      if (pair.startsWith('connect.sid=')) return pair;
    }
    throw SeerrException('Signed in, but no session cookie was returned.');
  } on DioException catch (e) {
    final code = e.response?.statusCode;
    if (code == 401 || code == 403) {
      throw SeerrException('Wrong username or password.');
    }
    if (e.type == DioExceptionType.connectionError) {
      throw SeerrException('Could not reach the Seerr server.');
    }
    throw SeerrException('Sign-in failed (${code ?? 'unknown'}).');
  }
}

/// Client for a Seerr / Overseerr instance (request management + discover).
class SeerrClient {
  final String baseUrl;
  final String apiKey;

  /// Session cookie for signed-in (per-user) auth. When set, it's sent instead
  /// of the admin API key.
  final String? cookie;
  final Dio _dio;

  SeerrClient(this.baseUrl, this.apiKey, {this.cookie})
    : _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));

  Options get _opts => Options(
    headers: cookie != null && cookie!.isNotEmpty
        ? {'Cookie': cookie}
        : {'X-Api-Key': apiKey},
  );

  /// The signed-in user's display name, or null if the session is invalid.
  Future<String?> me() async {
    try {
      final r = await _dio.get('$baseUrl/api/v1/auth/me', options: _opts);
      final m = r.data as Map?;
      return (m?['displayName'] ?? m?['username'] ?? m?['jellyfinUsername'])
          as String?;
    } catch (_) {
      return null;
    }
  }

  /// The signed-in user's permission bitmask (Jellyseerr Permission flags).
  Future<int?> myPermissions() async {
    try {
      final r = await _dio.get('$baseUrl/api/v1/auth/me', options: _opts);
      return ((r.data as Map?)?['permissions'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  /// Removes the media file from Radarr/Sonarr (admin only). [mediaId] is the
  /// Jellyseerr media record id, not the TMDB id.
  Future<void> deleteMediaFile(int mediaId, {bool is4k = false}) async {
    try {
      await _dio.delete(
        '$baseUrl/api/v1/media/$mediaId/file',
        queryParameters: {'is4k': is4k},
        options: _opts,
      );
    } on DioException catch (e) {
      throw SeerrException(_friendly(e));
    }
  }

  /// Forces a title's availability state (the Manage panel's "Mark as
  /// Available"). [status] is one of available/partial/processing/pending/
  /// unknown; the handler requires MANAGE_REQUESTS. [mediaId] is the record id.
  Future<void> setMediaStatus(
    int mediaId,
    String status, {
    bool is4k = false,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/api/v1/media/$mediaId/$status',
        data: {'is4k': is4k},
        options: _opts,
      );
    } on DioException catch (e) {
      throw SeerrException(_friendly(e));
    }
  }

  /// Clears all Jellyseerr data for a title (the Manage panel's "Clear Data"):
  /// removes the media record and its requests. [mediaId] is the record id.
  Future<void> clearMediaData(int mediaId) async {
    try {
      await _dio.delete('$baseUrl/api/v1/media/$mediaId', options: _opts);
    } on DioException catch (e) {
      throw SeerrException(_friendly(e));
    }
  }

  Future<SeerrHideRules>? _hideRules;

  /// The server's hide settings, read once per client. Anything unreadable
  /// (an older Seerr, a dropped connection) hides nothing.
  Future<SeerrHideRules> hideRules() => _hideRules ??= _loadHideRules();

  Future<SeerrHideRules> _loadHideRules() async {
    try {
      final res = await _dio.get(
        '$baseUrl/api/v1/settings/public',
        options: _opts,
      );
      final s = (res.data as Map?) ?? const {};
      var blocklisted = s['hideBlocklisted'] == true;
      if (blocklisted) {
        // Seerr hides blocklisted titles only from people who manage the
        // blocklist (everyone else never sees them listed anyway).
        const admin = 2, manageBlocklist = 268435456;
        final p = await myPermissions() ?? 0;
        blocklisted = p & admin != 0 || p & manageBlocklist != 0;
      }
      return SeerrHideRules(
        available: s['hideAvailable'] == true,
        blocklisted: blocklisted,
        requested: s['hideRequested'] == true,
      );
    } catch (_) {
      _hideRules = null; // try again next time
      return SeerrHideRules.none;
    }
  }

  /// Fetches [pages] pages of a discover endpoint (Seerr returns 20 per
  /// page) and concatenates them, de-duplicating by tmdb id. Stops early once
  /// a page comes back short (no more results). Titles the server's hide
  /// settings cover are left out, as in Seerr's web app.
  Future<List<SeerrResult>> _discover(
    String path, {
    int pages = 3,
    Map<String, dynamic> query = const {},
  }) async {
    final hide = await hideRules();
    try {
      final out = <SeerrResult>[];
      final seen = <int>{};
      var totalPages = pages;
      for (var page = 1; page <= pages && page <= totalPages; page++) {
        final res = await _dio.get(
          '$baseUrl/api/v1/$path',
          queryParameters: {'page': page, ...query},
          options: _opts,
        );
        totalPages = (res.data['totalPages'] as num?)?.toInt() ?? totalPages;
        final results = (res.data['results'] as List?) ?? const [];
        if (results.isEmpty) break;
        for (final e in results.whereType<Map>()) {
          if (e['mediaType'] == 'person') continue;
          final r = SeerrResult.fromJson(Map<String, dynamic>.from(e));
          if (r.tmdbId == 0 || !seen.add(r.tmdbId)) continue;
          if (hide.hides(r)) continue;
          out.add(r);
        }
      }
      return out;
    } on DioException catch (e) {
      throw SeerrException(_friendly(e));
    }
  }

  Future<List<SeerrResult>> trending() => _discover('discover/trending');
  Future<List<SeerrResult>> popularMovies() => _discover('discover/movies');
  Future<List<SeerrResult>> popularTv() => _discover('discover/tv');
  Future<List<SeerrResult>> upcomingMovies() =>
      _discover('discover/movies/upcoming');
  Future<List<SeerrResult>> upcomingTv() => _discover('discover/tv/upcoming');

  /// Movies or series of one genre, for the row opened from a genre-slider tile.
  Future<List<SeerrResult>> discoverByGenre(
    String mediaType,
    int genreId, {
    String? sortBy,
  }) => _discover(
    'discover/${mediaType == 'tv' ? 'tv' : 'movies'}/genre/$genreId',
    query: {'sortBy': ?sortBy},
  );

  /// Movies from a studio, or series from a network, for the card opened from
  /// the Studios / Networks rows.
  Future<List<SeerrResult>> discoverByStudio(int studioId, {String? sortBy}) =>
      _discover('discover/movies/studio/$studioId', query: {'sortBy': ?sortBy});
  Future<List<SeerrResult>> discoverByNetwork(
    int networkId, {
    String? sortBy,
  }) => _discover('discover/tv/network/$networkId', query: {'sortBy': ?sortBy});

  /// TMDB recommendations / similar titles for a title's detail page.
  Future<List<SeerrResult>> recommendations(String mediaType, int tmdbId) =>
      _discover('$mediaType/$tmdbId/recommendations', pages: 1);
  Future<List<SeerrResult>> similar(String mediaType, int tmdbId) =>
      _discover('$mediaType/$tmdbId/similar', pages: 1);

  /// Genre-slider data (genres with a few backdrops each). Returns a bare JSON
  /// array. [mediaType] is 'movie' or 'tv'.
  Future<List<SeerrGenre>> genreSlider(String mediaType) async {
    try {
      final res = await _dio.get(
        '$baseUrl/api/v1/discover/genreslider/$mediaType',
        options: _opts,
      );
      final data = res.data;
      if (data is! List) return const [];
      return [
        for (final e in data.whereType<Map>())
          SeerrGenre.fromJson(Map<String, dynamic>.from(e), mediaType),
      ].where((g) => g.id != 0 && g.name.isNotEmpty).toList();
    } on DioException catch (e) {
      throw SeerrException(_friendly(e));
    }
  }

  /// Recently added, available titles (Jellyseerr's "Recently Added" row). The
  /// `/media` endpoint returns only ids + status; posters are filled in per-card
  /// from the detail endpoint.
  Future<List<SeerrMediaRef>> recentlyAdded({int take = 20}) async {
    try {
      final res = await _dio.get(
        '$baseUrl/api/v1/media',
        queryParameters: {
          'take': take,
          'skip': 0,
          'filter': 'allavailable',
          'sort': 'mediaAdded',
        },
        options: _opts,
      );
      final results = (res.data['results'] as List?) ?? const [];
      return [
            for (final e in results.whereType<Map>())
              SeerrMediaRef.fromJson(Map<String, dynamic>.from(e)),
          ]
          .where(
            (m) =>
                m.tmdbId != 0 &&
                (m.mediaType == 'movie' || m.mediaType == 'tv'),
          )
          .toList();
    } on DioException catch (e) {
      throw SeerrException(_friendly(e));
    }
  }

  /// Search movies, series and people. People come back as results with
  /// mediaType 'person' (poster = their profile), so the UI can route them to
  /// the person page, matching Jellyseerr's mixed search.
  Future<List<SeerrResult>> search(String query) async {
    try {
      // Percent-encode the term as %20 (matching the Jellyseerr web app). Dio's
      // queryParameters encode a space as "+", which some Jellyseerr instances
      // reject with a 400 ("Lasso" works, "ted lasso" fails), so build the URL
      // with the value pre-encoded and skip queryParameters here.
      final res = await _dio.get(
        '$baseUrl/api/v1/search?query=${Uri.encodeComponent(query)}',
        options: _opts,
      );
      final results = (res.data['results'] as List?) ?? const [];
      return [
        for (final e in results.whereType<Map>())
          if (e['mediaType'] == 'person')
            SeerrResult(
              tmdbId: (e['id'] as num?)?.toInt() ?? 0,
              mediaType: 'person',
              title: e['name'] as String? ?? '',
              posterPath: e['profilePath'] as String?,
            )
          else
            SeerrResult.fromJson(Map<String, dynamic>.from(e)),
      ].where((r) => r.tmdbId != 0).toList();
    } on DioException catch (e) {
      throw SeerrException(_friendly(e));
    }
  }

  /// A movie collection (franchise) and its member titles.
  Future<SeerrCollection> collection(int id) async {
    try {
      final res = await _dio.get(
        '$baseUrl/api/v1/collection/$id',
        options: _opts,
      );
      return SeerrCollection.fromJson(
        Map<String, dynamic>.from(res.data as Map),
      );
    } on DioException catch (e) {
      throw SeerrException(_friendly(e));
    }
  }

  /// The episodes of one season of a series.
  Future<List<SeerrEpisode>> season(int tvId, int seasonNumber) async {
    try {
      final res = await _dio.get(
        '$baseUrl/api/v1/tv/$tvId/season/$seasonNumber',
        options: _opts,
      );
      final episodes = (res.data['episodes'] as List?) ?? const [];
      return [
        for (final e in episodes.whereType<Map>())
          SeerrEpisode.fromJson(Map<String, dynamic>.from(e)),
      ];
    } on DioException catch (e) {
      throw SeerrException(_friendly(e));
    }
  }

  /// A person and their appearances (combined cast credits), most notable
  /// first, mapped to requestable results.
  Future<SeerrPerson> person(int id) async {
    try {
      final results = await Future.wait([
        _dio.get('$baseUrl/api/v1/person/$id', options: _opts),
        _dio.get('$baseUrl/api/v1/person/$id/combined_credits', options: _opts),
      ]);
      final detail = Map<String, dynamic>.from(results[0].data as Map);
      final castRaw =
          ((results[1].data as Map?)?['cast'] as List?)
              ?.whereType<Map>()
              .toList() ??
          [];
      // Notable roles first: TMDB's vote count is a decent proxy for that.
      castRaw.sort(
        (a, b) => ((b['voteCount'] as num?)?.toInt() ?? 0).compareTo(
          (a['voteCount'] as num?)?.toInt() ?? 0,
        ),
      );
      final seen = <String>{};
      final credits = <SeerrResult>[];
      for (final c in castRaw) {
        final mt = c['mediaType'];
        if (mt != 'movie' && mt != 'tv') continue;
        final r = SeerrResult.fromJson(Map<String, dynamic>.from(c));
        if (r.tmdbId == 0 || !seen.add('${r.mediaType}-${r.tmdbId}')) continue;
        credits.add(r);
      }
      return SeerrPerson.fromJson(detail, credits);
    } on DioException catch (e) {
      throw SeerrException(_friendly(e));
    }
  }

  /// Full detail for a title. [mediaType] is 'movie' or 'tv'.
  Future<SeerrDetail> detail({
    required String mediaType,
    required int tmdbId,
  }) async {
    try {
      final res = await _dio.get(
        '$baseUrl/api/v1/$mediaType/$tmdbId',
        options: _opts,
      );
      var detail = SeerrDetail.fromJson(
        Map<String, dynamic>.from(res.data as Map),
      );
      // Ratings live on a separate endpoint; best-effort, never fatal.
      final ratings = await ratingsFor(mediaType: mediaType, tmdbId: tmdbId);
      if (ratings != null) {
        detail = detail.copyWithRatings(
          rtCriticScore: ratings.$1,
          rtAudienceScore: ratings.$2,
          imdbScore: ratings.$3,
        );
      }
      return detail;
    } on DioException catch (e) {
      throw SeerrException(_friendly(e));
    }
  }

  /// (rtCritic, rtAudience, imdb) from Seerr's ratings endpoints. Movies expose
  /// a combined RT + IMDb payload; TV exposes RT only. Returns null on any
  /// failure so a missing-ratings backend never blocks the caller.
  Future<(int?, int?, double?)?> ratingsFor({
    required String mediaType,
    required int tmdbId,
  }) async {
    if (mediaType == 'movie') {
      try {
        final r = await _dio.get(
          '$baseUrl/api/v1/movie/$tmdbId/ratingscombined',
          options: _opts,
        );
        final m = Map<String, dynamic>.from(r.data as Map);
        final rt = (m['rt'] as Map?)?.cast<String, dynamic>();
        final imdb = (m['imdb'] as Map?)?.cast<String, dynamic>();
        return (
          (rt?['criticsScore'] as num?)?.toInt(),
          (rt?['audienceScore'] as num?)?.toInt(),
          (imdb?['criticsScore'] as num?)?.toDouble(),
        );
      } catch (_) {
        // Older backends lack /ratingscombined; fall through to RT-only.
      }
    }
    try {
      final r = await _dio.get(
        '$baseUrl/api/v1/$mediaType/$tmdbId/ratings',
        options: _opts,
      );
      final rt = Map<String, dynamic>.from(r.data as Map);
      return (
        (rt['criticsScore'] as num?)?.toInt(),
        (rt['audienceScore'] as num?)?.toInt(),
        null,
      );
    } catch (_) {
      return null;
    }
  }

  /// Request a movie, a whole TV show, or specific seasons of a TV show.
  /// Pass [seasons] as a list of season numbers for TV; omit for movies or a
  /// full-series request.
  Future<void> request({
    required String mediaType,
    required int tmdbId,
    List<int>? seasons,
    int? profileId,
    int? userId,
    List<int>? tags,
    bool is4k = false,
    int? serverId,
    String? rootFolder,
    int? languageProfileId,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/api/v1/request',
        data: {
          'mediaType': mediaType,
          'mediaId': tmdbId,
          if (mediaType == 'tv')
            'seasons': (seasons == null || seasons.isEmpty) ? 'all' : seasons,
          if (is4k) 'is4k': true,
          // These match Jellyseerr's request dialog. Sent only when chosen,
          // so a bare request still works exactly as before.
          'profileId': ?profileId,
          'userId': ?userId,
          'serverId': ?serverId,
          'rootFolder': ?rootFolder,
          'languageProfileId': ?languageProfileId,
          if (tags != null && tags.isNotEmpty) 'tags': tags,
        },
        options: _opts,
      );
    } on DioException catch (e) {
      throw SeerrException(_friendly(e));
    }
  }

  /// Change an existing (pending) request's advanced options. Jellyseerr's PUT
  /// is a full overwrite (any omitted field is cleared), so callers pass every
  /// value they mean to keep, including [tags]. [userId] reassigns the requester
  /// ("Request As") and needs Manage Requests/Users.
  Future<void> editRequest(
    int id, {
    required String mediaType,
    List<int>? seasons,
    int? profileId,
    int? serverId,
    String? rootFolder,
    int? languageProfileId,
    bool? is4k,
    List<int>? tags,
    int? userId,
  }) async {
    try {
      await _dio.put(
        '$baseUrl/api/v1/request/$id',
        data: {
          'mediaType': mediaType,
          if (mediaType == 'tv' && seasons != null && seasons.isNotEmpty)
            'seasons': seasons,
          'is4k': ?is4k,
          'profileId': ?profileId,
          'serverId': ?serverId,
          'rootFolder': ?rootFolder,
          'languageProfileId': ?languageProfileId,
          'userId': ?userId,
          'tags': ?tags,
        },
        options: _opts,
      );
    } on DioException catch (e) {
      throw SeerrException(_friendly(e));
    }
  }

  /// The users the admin can request on behalf of. Degrades to empty.
  Future<List<SeerrUser>> requestUsers() => _users();

  /// The arr servers behind the instance. Used to offer a server picker and to
  /// detect whether 4K is configured. [mediaType] chooses Radarr vs Sonarr.
  Future<List<SeerrServer>> servers(String mediaType) async {
    final service = mediaType == 'tv' ? 'sonarr' : 'radarr';
    try {
      final res = await _dio.get(
        '$baseUrl/api/v1/service/$service',
        options: _opts,
      );
      final list = res.data;
      if (list is! List) return const [];
      return [
        for (final s in list.whereType<Map>())
          SeerrServer(
            id: (s['id'] as num?)?.toInt() ?? 0,
            name: '${s['name'] ?? 'Server'}',
            is4k: s['is4k'] == true,
            isDefault: s['isDefault'] == true,
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// One server's advanced options (profiles, root folders, tags, language
  /// profiles) plus its active defaults. Degrades to empty on failure.
  Future<SeerrServerOptions> serverOptions(
    String mediaType,
    int serverId,
  ) async {
    final service = mediaType == 'tv' ? 'sonarr' : 'radarr';
    try {
      final res = await _dio.get(
        '$baseUrl/api/v1/service/$service/$serverId',
        options: _opts,
      );
      final data = res.data as Map?;
      if (data == null) return SeerrServerOptions.empty;
      final server = (data['server'] as Map?) ?? const {};
      List<T> mapList<T>(String key, T Function(Map) f) => [
        for (final e in (data[key] as List?) ?? const [])
          if (e is Map) f(e),
      ];
      return SeerrServerOptions(
        profiles: mapList(
          'profiles',
          (p) => SeerrProfile(
            id: (p['id'] as num?)?.toInt() ?? 0,
            name: '${p['name'] ?? ''}',
          ),
        ),
        defaultProfileId: (server['activeProfileId'] as num?)?.toInt(),
        rootFolders: mapList(
          'rootFolders',
          (r) => SeerrRootFolder(
            id: (r['id'] as num?)?.toInt() ?? 0,
            path: '${r['path'] ?? ''}',
          ),
        ),
        defaultRootFolder: server['activeDirectory'] as String?,
        tags: mapList(
          'tags',
          (t) => SeerrTag(
            id: (t['id'] as num?)?.toInt() ?? 0,
            label: '${t['label'] ?? t['name'] ?? ''}',
          ),
        ),
        languageProfiles: mapList(
          'languageProfiles',
          (p) => SeerrProfile(
            id: (p['id'] as num?)?.toInt() ?? 0,
            name: '${p['name'] ?? ''}',
          ),
        ),
        defaultLanguageProfileId: (server['activeLanguageProfileId'] as num?)
            ?.toInt(),
      );
    } catch (_) {
      return SeerrServerOptions.empty;
    }
  }

  /// Every user, a page of 100 at a time (a server can have more than one
  /// page; the picker used to stop at the first).
  Future<List<SeerrUser>> _users() async {
    const pageSize = 100;
    final out = <SeerrUser>[];
    try {
      for (var page = 0; page < 50; page++) {
        final res = await _dio.get(
          '$baseUrl/api/v1/user',
          queryParameters: {'take': pageSize, 'skip': page * pageSize},
          options: _opts,
        );
        final data = res.data as Map?;
        final results = data?['results'];
        if (results is! List || results.isEmpty) break;
        for (final u in results.whereType<Map>()) {
          out.add(
            SeerrUser(
              id: (u['id'] as num?)?.toInt() ?? 0,
              name:
                  '${u['displayName'] ?? u['username'] ?? u['jellyfinUsername'] ?? 'User'}',
              email: u['email'] as String?,
              avatarUrl: seerrAvatarUrl(baseUrl, u['avatar'] as String?),
            ),
          );
        }
        final pages = ((data?['pageInfo'] as Map?)?['pages'] as num?)?.toInt();
        if (results.length < pageSize || (pages != null && page + 1 >= pages)) {
          break;
        }
      }
      return out;
    } catch (_) {
      return out;
    }
  }

  /// Media requests. [filter] is one of all/pending/approved/completed/
  /// processing/failed/available/unavailable/deleted; [mediaType] is
  /// all/movie/tv; [sort] is added/modified; [sortDirection] is asc/desc.
  /// These mirror Jellyseerr's Requests page controls exactly.
  Future<List<SeerrRequest>> requests({
    int take = 40,
    String filter = 'all',
    String mediaType = 'all',
    String sort = 'added',
    String sortDirection = 'desc',
  }) async {
    try {
      final res = await _dio.get(
        '$baseUrl/api/v1/request',
        queryParameters: {
          'take': take,
          'skip': 0,
          'filter': filter,
          'mediaType': mediaType,
          'sort': sort,
          'sortDirection': sortDirection,
        },
        options: _opts,
      );
      final results = (res.data['results'] as List?) ?? const [];
      return results
          .whereType<Map>()
          .map((e) => SeerrRequest.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on DioException catch (e) {
      throw SeerrException(_friendly(e));
    }
  }

  Future<void> approveRequest(int id) => _requestAction('$id/approve');
  Future<void> declineRequest(int id) => _requestAction('$id/decline');

  /// Re-runs a failed request's downstream (Radarr/Sonarr) job. Manage Requests.
  Future<void> retryRequest(int id) => _requestAction('$id/retry');

  Future<void> _requestAction(String path) async {
    try {
      await _dio.post('$baseUrl/api/v1/request/$path', options: _opts);
    } on DioException catch (e) {
      throw SeerrException(_friendly(e));
    }
  }

  Future<void> deleteRequest(int id) async {
    try {
      await _dio.delete('$baseUrl/api/v1/request/$id', options: _opts);
    } on DioException catch (e) {
      throw SeerrException(_friendly(e));
    }
  }

  /// Validates the URL + key by hitting the status endpoint.
  Future<bool> testConnection() async {
    try {
      await _dio.get('$baseUrl/api/v1/status', options: _opts);
      return true;
    } on DioException {
      return false;
    }
  }

  String _friendly(DioException e) => seerrErrorMessage(e);
}

/// What to tell the user when Seerr answers with an error. Seerr explains a
/// refused action in the body's `message` (a request that is no longer
/// pending, a request limit reached, a missing permission), so that is shown
/// as it is. Only a refusal without one (its sign-in check, which answers
/// `error`) means the API key or session was turned away.
@visibleForTesting
String seerrErrorMessage(DioException e) {
  final data = e.response?.data;
  final message = data is Map ? data['message'] : null;
  if (message is String && message.trim().isNotEmpty) {
    return 'Seerr: ${message.trim()}';
  }
  if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
    return 'Seerr rejected the API key.';
  }
  if (e.type == DioExceptionType.connectionError) {
    return 'Could not reach the Seerr server.';
  }
  return 'Seerr error (${e.response?.statusCode ?? 'unknown'}).';
}
