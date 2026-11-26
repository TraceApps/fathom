part of 'jellyfin_client.dart';

/// Other devices: remote control of a session, and SyncPlay groups.
extension JellyfinSessionsApi on JellyfinClient {
/// Sessions this user can remote-control (other Jellyfin players).
  Future<List<Map<String, dynamic>>> getControllableSessions({
    required String baseUrl,
    required String userId,
    required String token,
  }) async {
    final all = await _getList(
      '$baseUrl/Sessions',
      token,
      query: {'ControllableByUserId': userId, 'ActiveWithinSeconds': '600'},
    );
    return all.where((s) => s['SupportsRemoteControl'] == true).toList();
  }

/// Starts playback of an item on another device.
  Future<void> playOnSession({
    required String baseUrl,
    required String token,
    required String sessionId,
    required String itemId,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/Sessions/$sessionId/Playing',
        queryParameters: {'playCommand': 'PlayNow', 'itemIds': itemId},
        options: _authed(token),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// Sends a playstate command (PlayPause, Stop, NextTrack, …) to a device.
  Future<void> sessionPlaystate({
    required String baseUrl,
    required String token,
    required String sessionId,
    required String command,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/Sessions/$sessionId/Playing/$command',
        options: _authed(token),
      );
    } on DioException {
      // Best-effort remote command.
    }
  }

// --- SyncPlay (watch together) ---

  Future<List<Map<String, dynamic>>> getSyncPlayGroups({
    required String baseUrl,
    required String token,
  }) async {
    try {
      final res = await _dio.get(
        '$baseUrl/SyncPlay/List',
        options: _authed(token),
      );
      final data = res.data;
      final listRaw = data is List ? data : const [];
      return listRaw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

Future<void> syncPlayNew({
    required String baseUrl,
    required String token,
    required String groupName,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/SyncPlay/New',
        data: {'GroupName': groupName},
        options: _authed(token),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

Future<void> syncPlayJoin({
    required String baseUrl,
    required String token,
    required String groupId,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/SyncPlay/Join',
        data: {'GroupId': groupId},
        options: _authed(token),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

Future<void> syncPlayLeave({
    required String baseUrl,
    required String token,
  }) async {
    try {
      await _dio.post('$baseUrl/SyncPlay/Leave', options: _authed(token));
    } on DioException {
      // Best-effort.
    }
  }

/// Group playback controls. These tell the SERVER what this client did, and
  /// the server broadcasts the coordinated command to every member (including
  /// us). All best-effort: a dropped control just misses one sync tick.
  Future<void> _syncPost(
    String baseUrl,
    String path,
    String token, [
    Object? data,
  ]) async {
    try {
      await _dio.post(
        '$baseUrl/SyncPlay/$path',
        data: data,
        options: _authed(token),
      );
    } on DioException {
      // Best-effort; SyncPlay tolerates a missed message.
    }
  }

Future<void> syncPlayPause({
    required String baseUrl,
    required String token,
  }) => _syncPost(baseUrl, 'Pause', token);

Future<void> syncPlayUnpause({
    required String baseUrl,
    required String token,
  }) => _syncPost(baseUrl, 'Unpause', token);

Future<void> syncPlaySeek({
    required String baseUrl,
    required String token,
    required int positionTicks,
  }) => _syncPost(baseUrl, 'Seek', token, {'PositionTicks': positionTicks});

/// Set the group's queue to [itemId] at [startPositionTicks]. This is how a
  /// client tells the group WHAT to watch; every member then opens it. Without
  /// this the group has no shared content and pause/seek are meaningless.
  Future<void> syncPlaySetNewQueue({
    required String baseUrl,
    required String token,
    required List<String> playingQueue,
    required int playingItemPosition,
    required int startPositionTicks,
  }) => _syncPost(baseUrl, 'SetNewQueue', token, {
    'PlayingQueue': playingQueue,
    'PlayingItemPosition': playingItemPosition,
    'StartPositionTicks': startPositionTicks,
  });

/// Report that this client began buffering (so the group waits for it).
  Future<void> syncPlayBuffering({
    required String baseUrl,
    required String token,
    required int positionTicks,
    required bool isPlaying,
    required String whenIso,
    String? playlistItemId,
  }) => _syncPost(baseUrl, 'Buffering', token, {
    'When': whenIso,
    'PositionTicks': positionTicks,
    'IsPlaying': isPlaying,
    'PlaylistItemId': ?playlistItemId,
  });

/// Report that this client is ready to resume at [positionTicks].
  Future<void> syncPlayReady({
    required String baseUrl,
    required String token,
    required int positionTicks,
    required bool isPlaying,
    required String whenIso,
    String? playlistItemId,
  }) => _syncPost(baseUrl, 'Ready', token, {
    'When': whenIso,
    'PositionTicks': positionTicks,
    'IsPlaying': isPlaying,
    'PlaylistItemId': ?playlistItemId,
  });

/// Report this client's measured round-trip ping (ms) so the server can
  /// schedule commands accounting for its latency.
  Future<void> syncPlayPing({
    required String baseUrl,
    required String token,
    required int pingMs,
  }) => _syncPost(baseUrl, 'Ping', token, {'Ping': pingMs});

/// The server's clock, with reception/transmission stamps, for estimating the
  /// client-server time offset that SyncPlay's `When` scheduling needs.
  Future<Map<String, dynamic>?> getUtcTime({
    required String baseUrl,
    required String token,
  }) async {
    try {
      final res = await _dio.get(
        '$baseUrl/GetUtcTime',
        options: _authed(token),
      );
      return Map<String, dynamic>.from(res.data as Map);
    } on DioException {
      return null;
    }
  }

// --- Administration (all require the user to be an administrator) ---

  Future<List<Map<String, dynamic>>> _getList(
    String url,
    String token, {
    Map<String, dynamic>? query,
    String? itemsKey,
  }) async {
    try {
      final res = await _dio.get(
        url,
        queryParameters: query,
        options: _authed(token),
      );
      final data = res.data;
      final list = itemsKey != null
          ? ((data as Map)[itemsKey] as List? ?? const [])
          : (data as List? ?? const []);
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }
}
