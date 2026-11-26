part of 'jellyfin_client.dart';

/// Live TV and the DVR: channels, the guide, recordings, timers, tuners and listing providers.
extension JellyfinLiveTvApi on JellyfinClient {
/// Live TV channels, each with its current program (for now-playing labels).
  Future<List<BaseItemDto>> getLiveTvChannels({
    required String baseUrl,
    required String userId,
    required String token,
  }) async {
    return _getItems(
      '$baseUrl/LiveTv/Channels',
      token,
      query: {
        'UserId': userId,
        'EnableImages': 'true',
        'AddCurrentProgram': 'true',
        'Fields': 'PrimaryImageAspectRatio',
        'Limit': '1000',
      },
    );
  }

/// Existing DVR recordings.
  Future<List<BaseItemDto>> getRecordings({
    required String baseUrl,
    required String userId,
    required String token,
  }) async {
    return _getItems(
      '$baseUrl/LiveTv/Recordings',
      token,
      query: {
        'UserId': userId,
        'EnableImages': 'true',
        'Fields': 'Overview,PrimaryImageAspectRatio',
      },
      // Some servers return recordings typed as their content (Movie/Video), so
      // force 'Recording' — the app keys the Recordings section/actions off it.
      typeOverride: 'Recording',
    );
  }

/// Schedules a recording for a program (single-program timer).
  Future<void> recordProgram({
    required String baseUrl,
    required String token,
    required String programId,
  }) async {
    try {
      final defaults = await _dio.get(
        '$baseUrl/LiveTv/Timers/Defaults',
        queryParameters: {'programId': programId},
        options: _authed(token),
      );
      await _dio.post(
        '$baseUrl/LiveTv/Timers',
        data: defaults.data,
        options: _authed(token),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// Schedules a recording for the whole series a program belongs to.
  Future<void> recordSeries({
    required String baseUrl,
    required String token,
    required String programId,
  }) async {
    try {
      // /LiveTv/Timers/Defaults is what 12 documents; the SeriesTimers one it
      // replaced is gone from the API but still answers on older servers.
      final defaults = await requestWithFallback(
        'GET',
        url: '$baseUrl/LiveTv/Timers/Defaults',
        legacyUrl: '$baseUrl/LiveTv/SeriesTimers/Defaults',
        token: token,
        query: {'programId': programId},
      );
      await _dio.post(
        '$baseUrl/LiveTv/SeriesTimers',
        data: defaults.data,
        options: _authed(token),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// Cancels a scheduled recording timer.
  Future<void> cancelTimer({
    required String baseUrl,
    required String token,
    required String timerId,
  }) async {
    try {
      await _dio.delete(
        '$baseUrl/LiveTv/Timers/$timerId',
        options: _authed(token),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// Programs (EPG entries) for the given channels within a time window.
  Future<List<BaseItemDto>> getGuidePrograms({
    required String baseUrl,
    required String userId,
    required String token,
    required List<String> channelIds,
    required DateTime start,
    required DateTime end,
  }) async {
    try {
      final res = await _dio.post(
        '$baseUrl/LiveTv/Programs',
        data: {
          'ChannelIds': channelIds,
          'UserId': userId,
          'MinStartDate': start.toUtc().toIso8601String(),
          'MaxStartDate': end.toUtc().toIso8601String(),
          'SortBy': ['StartDate'],
          // Ask for descriptions/genres so program detail isn't empty.
          // (EpisodeTitle is returned by default for programs; it is NOT a
          // valid ItemFields value and adding it 400s the whole request.)
          'Fields': ['Overview', 'Genres'],
          'EnableImages': false,
          'EnableTotalRecordCount': false,
        },
        options: _authed(token),
      );
      final data = Map<String, dynamic>.from(res.data as Map);
      return (data['Items'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => BaseItemDto.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

// ---- Live TV administration ----

  /// Live TV info: tuner hosts, listing providers, and enabled state.
  Future<Map<String, dynamic>> getLiveTvInfo({
    required String baseUrl,
    required String token,
  }) async {
    try {
      final res = await _dio.get(
        '$baseUrl/LiveTv/Info',
        options: _authed(token),
      );
      return Map<String, dynamic>.from(res.data as Map);
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// Adds a tuner host, e.g. {'Type': 'm3u', 'Url': '...'} or
  /// {'Type': 'hdhomerun', 'Url': 'http://ip'} (admin only).
  Future<void> addTunerHost({
    required String baseUrl,
    required String token,
    required Map<String, dynamic> tuner,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/LiveTv/TunerHosts',
        data: tuner,
        options: Options(
          headers: {
            'Authorization': authHeader(token: token),
            'Content-Type': 'application/json',
          },
        ),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// Removes a tuner host by id (admin only).
  Future<void> deleteTunerHost({
    required String baseUrl,
    required String token,
    required String id,
  }) async {
    try {
      await _dio.delete(
        '$baseUrl/LiveTv/TunerHosts',
        queryParameters: {'id': id},
        options: _authed(token),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// Adds an XMLTV guide provider from a file path or URL (admin only).
  Future<void> addXmltvListingProvider({
    required String baseUrl,
    required String token,
    required String pathOrUrl,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/LiveTv/ListingProviders',
        queryParameters: {'validateListings': false},
        data: {'Type': 'xmltv', 'Path': pathOrUrl},
        options: Options(
          headers: {
            'Authorization': authHeader(token: token),
            'Content-Type': 'application/json',
          },
        ),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// Saves a guide (listings) provider. Mirrors the official dashboard: pass
  /// [validateLogin] when checking Schedules Direct credentials, and
  /// [validateListings] when committing a chosen lineup. Returns the saved
  /// provider (which carries the generated Id on first save).
  Future<Map<String, dynamic>> saveListingProvider({
    required String baseUrl,
    required String token,
    required Map<String, dynamic> info,
    bool validateLogin = false,
    bool validateListings = false,
  }) async {
    try {
      final res = await _dio.post(
        '$baseUrl/LiveTv/ListingProviders',
        queryParameters: {
          'validateLogin': validateLogin,
          'validateListings': validateListings,
        },
        data: info,
        options: Options(
          headers: {
            'Authorization': authHeader(token: token),
            'Content-Type': 'application/json',
          },
        ),
      );
      return Map<String, dynamic>.from(res.data as Map);
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// The Schedules Direct country list, grouped by region. Each entry carries a
  /// full name, short code, and a sample/regex for the postal code.
  Future<Map<String, dynamic>> getSchedulesDirectCountries({
    required String baseUrl,
    required String token,
  }) async {
    try {
      final res = await _dio.get(
        '$baseUrl/LiveTv/ListingProviders/SchedulesDirect/Countries',
        options: _authed(token),
      );
      final data = res.data;
      // The server proxies Schedules Direct's raw payload, which may arrive as
      // a JSON string rather than a decoded object.
      if (data is String) {
        return Map<String, dynamic>.from(jsonDecode(data) as Map);
      }
      return Map<String, dynamic>.from(data as Map);
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// Available lineups for a saved provider at a country + postal code.
  Future<List<({String id, String name})>> getListingProviderLineups({
    required String baseUrl,
    required String token,
    required String providerId,
    required String country,
    required String location,
    String type = 'SchedulesDirect',
  }) async {
    try {
      final res = await _dio.get(
        '$baseUrl/LiveTv/ListingProviders/Lineups',
        queryParameters: {
          'id': providerId,
          'type': type,
          'location': location,
          'country': country,
        },
        options: _authed(token),
      );
      final list = (res.data as List?) ?? const [];
      return [
        for (final e in list.whereType<Map>())
          (id: '${e['Id'] ?? ''}', name: '${e['Name'] ?? e['Id'] ?? ''}'),
      ];
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// Removes a guide provider by id (admin only).
  Future<void> deleteListingProvider({
    required String baseUrl,
    required String token,
    required String id,
  }) async {
    try {
      await _dio.delete(
        '$baseUrl/LiveTv/ListingProviders',
        queryParameters: {'id': id},
        options: _authed(token),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

// ---- DVR: recordings, timers, and series rules ----

  /// Scheduled one-off recording timers.
  Future<List<Map<String, dynamic>>> getTimers({
    required String baseUrl,
    required String token,
  }) async {
    final res = await _dio.get(
      '$baseUrl/LiveTv/Timers',
      options: _authed(token),
    );
    return _itemsOf(res.data);
  }

/// Series recording rules.
  Future<List<Map<String, dynamic>>> getSeriesTimers({
    required String baseUrl,
    required String token,
  }) async {
    final res = await _dio.get(
      '$baseUrl/LiveTv/SeriesTimers',
      options: _authed(token),
    );
    return _itemsOf(res.data);
  }

/// A pre-filled timer for a program (channel, times, and default padding),
  /// ready to tweak and POST back as a one-off or series recording.
  Future<Map<String, dynamic>> getTimerDefaults({
    required String baseUrl,
    required String token,
    required String programId,
  }) async {
    try {
      final res = await _dio.get(
        '$baseUrl/LiveTv/Timers/Defaults',
        queryParameters: {'programId': programId},
        options: _authed(token),
      );
      return Map<String, dynamic>.from(res.data as Map);
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

Future<void> createTimer({
    required String baseUrl,
    required String token,
    required Map<String, dynamic> timer,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/LiveTv/Timers',
        data: timer,
        options: Options(
          headers: {
            'Authorization': authHeader(token: token),
            'Content-Type': 'application/json',
          },
        ),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

Future<void> createSeriesTimer({
    required String baseUrl,
    required String token,
    required Map<String, dynamic> timer,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/LiveTv/SeriesTimers',
        data: timer,
        options: Options(
          headers: {
            'Authorization': authHeader(token: token),
            'Content-Type': 'application/json',
          },
        ),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

Future<void> updateSeriesTimer({
    required String baseUrl,
    required String token,
    required String id,
    required Map<String, dynamic> timer,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/LiveTv/SeriesTimers/$id',
        data: timer,
        options: Options(
          headers: {
            'Authorization': authHeader(token: token),
            'Content-Type': 'application/json',
          },
        ),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

Future<void> cancelSeriesTimer({
    required String baseUrl,
    required String token,
    required String id,
  }) async {
    try {
      await _dio.delete(
        '$baseUrl/LiveTv/SeriesTimers/$id',
        options: _authed(token),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

Future<void> deleteRecording({
    required String baseUrl,
    required String token,
    required String id,
  }) async {
    try {
      await _dio.delete('$baseUrl/Items/$id', options: _authed(token));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

List<Map<String, dynamic>> _itemsOf(dynamic data) {
    final items = data is Map ? (data['Items'] as List? ?? const []) : const [];
    return items
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
}
