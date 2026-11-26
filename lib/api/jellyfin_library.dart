part of 'jellyfin_client.dart';

/// Browsing and editing the library: views, items, playlists, artists, and the per-item actions (played, favourite, delete).
extension JellyfinLibraryApi on JellyfinClient {
/// The user's libraries (Movies, TV Shows, Music, Live TV, ...).
  Future<List<BaseItemDto>> getUserViews({
    required String baseUrl,
    required String userId,
    required String token,
  }) async {
    return _getItems('$baseUrl/UserViews', token,
        query: {'userId': userId},
        legacyUrl: '$baseUrl/Users/$userId/Views');
  }

/// "Continue Watching" — partially played video items.
  Future<List<BaseItemDto>> getResumeItems({
    required String baseUrl,
    required String userId,
    required String token,
    int limit = 20,
  }) async {
    final items = await _getItems(
      '$baseUrl/UserItems/Resume',
      token,
      legacyUrl: '$baseUrl/Users/$userId/Items/Resume',
      query: {
        'userId': userId,
        'Limit': '$limit',
        'MediaTypes': 'Video',
        'Fields': 'PrimaryImageAspectRatio,Overview',
        'EnableImageTypes': 'Primary,Backdrop,Thumb,Logo',
      },
    );
    return items;
  }

/// The user's global Next Up queue (next episodes across all series).
  Future<List<BaseItemDto>> getNextUpItems({
    required String baseUrl,
    required String userId,
    required String token,
    int limit = 20,
  }) {
    return _getItems(
      '$baseUrl/Shows/NextUp',
      token,
      query: {
        'UserId': userId,
        'Limit': '$limit',
        'Fields': 'PrimaryImageAspectRatio,Overview,DateCreated',
        'EnableImageTypes': 'Primary,Backdrop,Thumb,Logo',
      },
    );
  }

  /// Episodes you finished, newest first. Each carries the date it was
  /// played, which is the only reliable "when did I last watch this show":
  /// measured on a 12.0 server, the series items' own LastPlayedDate is always
  /// empty, and the Next Up and resume endpoints return orders that don't
  /// follow viewing at all.
  Future<List<BaseItemDto>> getRecentlyFinishedEpisodes({
    required String baseUrl,
    required String userId,
    required String token,
    int limit = 60,
    /// Only this show's episodes.
    String? seriesId,
  }) async {
    final res = await getItems(
      baseUrl: baseUrl,
      userId: userId,
      token: token,
      parentId: seriesId,
      filters: 'IsPlayed',
      includeItemTypes: 'Episode',
      recursive: true,
      sortBy: 'DatePlayed',
      sortOrder: 'Descending',
      limit: limit,
    );
    return res.items;
  }

/// "Recently Added" — newest items, optionally scoped to one library.
  Future<List<BaseItemDto>> getLatestItems({
    required String baseUrl,
    required String userId,
    required String token,
    String? parentId,
    int limit = 20,
  }) async {
    return _getItems(
      '$baseUrl/Items/Latest',
      token,
      legacyUrl: '$baseUrl/Users/$userId/Items/Latest',
      query: {
        'userId': userId,
        'Limit': '$limit',
        'Fields': 'Overview,PrimaryImageAspectRatio',
        'EnableImageTypes': 'Primary,Backdrop,Thumb,Logo',
        'ParentId': ?parentId,
      },
    );
  }

Future<List<BaseItemDto>> _getItems(
    String url,
    String token, {
    Map<String, dynamic>? query,
    String? typeOverride,
    // The per-user route to try on a server that hasn't got [url]; see
    // requestWithFallback.
    String? legacyUrl,
    Map<String, dynamic>? legacyQuery,
  }) async {
    try {
      final res = legacyUrl == null
          ? await _dio.get(url, queryParameters: query, options: _authed(token))
          : await requestWithFallback('GET',
              url: url,
              legacyUrl: legacyUrl,
              token: token,
              query: query,
              legacyQuery: legacyQuery);
      final data = res.data;
      final rawList = data is List
          ? data
          : (data is Map ? (data['Items'] as List? ?? const []) : const []);
      return rawList.whereType<Map>().map((e) {
        final m = Map<String, dynamic>.from(e);
        // Recordings come back typed as their content (Movie/Video/Episode);
        // stamp the kind so the app can treat them uniformly as recordings.
        if (typeOverride != null) m['Type'] = typeOverride;
        return BaseItemDto.fromJson(m);
      }).toList();
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// General item query used for library browsing and search. Returns a page
  /// of items plus the total count so callers can page with [startIndex].
  Future<ItemsResult> getItems({
    required String baseUrl,
    required String userId,
    required String token,
    String? parentId,
    String? searchTerm,
    String? includeItemTypes,
    String? genres,
    String? studios,
    String? albumArtistIds,
    String? personIds,
    String? filters,
    bool? isFavorite,
    String sortBy = 'SortName',
    String sortOrder = 'Ascending',
    bool recursive = false,
    int startIndex = 0,
    int limit = 100,
  }) async {
    try {
      final res = await requestWithFallback(
        'GET',
        url: '$baseUrl/Items',
        legacyUrl: '$baseUrl/Users/$userId/Items',
        token: token,
        query: {
          'userId': userId,
          'ParentId': ?parentId,
          'SearchTerm': ?searchTerm,
          'IncludeItemTypes': ?includeItemTypes,
          'Genres': ?genres,
          'Studios': ?studios,
          'AlbumArtistIds': ?albumArtistIds,
          'PersonIds': ?personIds,
          'Filters': ?filters,
          'IsFavorite': isFavorite == null ? null : '$isFavorite',
          'SortBy': sortBy,
          'SortOrder': sortOrder,
          'Recursive': '$recursive',
          'StartIndex': '$startIndex',
          'Limit': '$limit',
          'Fields': 'PrimaryImageAspectRatio,ProductionYear',
          'ImageTypeLimit': '1',
          'EnableImageTypes': 'Primary,Backdrop,Thumb',
        },
      );
      final data = Map<String, dynamic>.from(res.data as Map);
      final items = (data['Items'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => BaseItemDto.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      return ItemsResult(
        items: items,
        totalRecordCount:
            (data['TotalRecordCount'] as num?)?.toInt() ?? items.length,
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// Several specific items at once, with the detail fields list views skip
  /// (genres, synopsis, trailers) plus watched state and runtime.
  Future<List<BaseItemDto>> getItemsByIds({
    required String baseUrl,
    required String userId,
    required String token,
    required List<String> ids,
  }) {
    if (ids.isEmpty) return Future.value(const []);
    return _getItems(
      '$baseUrl/Items',
      token,
      legacyUrl: '$baseUrl/Users/$userId/Items',
      query: {
        'userId': userId,
        'Ids': ids.join(','),
        'Fields': 'Genres,Overview,RemoteTrailers,ProductionYear',
        'EnableUserData': 'true',
      },
    );
  }

  /// The id of the movie or show that carries one of [providerIds] (named
  /// as the server names them: Tmdb, Tvdb, Imdb), or null when the library
  /// hasn't got it.
  ///
  /// The server's item query has no filter for a provider id, so this asks
  /// by name, which finds nearly every title in one small answer. A library
  /// can hold a title under another name (a translated one, say): with
  /// [byYear] the titles of the years around [year] are gone through as
  /// well, which is a bigger answer, so it's only worth asking for a title
  /// that's known to be on disk.
  Future<String?> findItemIdByProviderIds({
    required String baseUrl,
    required String userId,
    required String token,
    required String itemType, // Movie, Series
    required String title,
    required Map<String, String> providerIds,
    int? year,
    bool byYear = false,
  }) async {
    final wanted = {
      for (final e in providerIds.entries)
        if (e.value.isNotEmpty) e.key.toLowerCase(): e.value.toLowerCase(),
    };
    if (wanted.isEmpty) return null;
    Future<String?> among(Map<String, dynamic> by) async {
      final res = await requestWithFallback(
        'GET',
        url: '$baseUrl/Items',
        legacyUrl: '$baseUrl/Users/$userId/Items',
        token: token,
        query: {
          'userId': userId,
          'IncludeItemTypes': itemType,
          'Recursive': 'true',
          'Fields': 'ProviderIds',
          'EnableImages': 'false',
          'EnableUserData': 'false',
          'EnableTotalRecordCount': 'false',
          ...by,
        },
      );
      final data = res.data;
      final items = data is Map ? (data['Items'] as List? ?? const []) : const [];
      for (final item in items.whereType<Map>()) {
        final ids = item['ProviderIds'];
        if (ids is! Map) continue;
        for (final e in ids.entries) {
          final want = wanted['${e.key}'.toLowerCase()];
          if (want != null && want == '${e.value}'.toLowerCase()) {
            return item['Id'] as String?;
          }
        }
      }
      return null;
    }

    try {
      final byName = title.trim().isEmpty
          ? null
          : await among({'SearchTerm': title, 'Limit': '50'});
      if (byName != null || !byYear || year == null) return byName;
      // Its own year first: most often that's the one, and half the
      // titles of three years is a long list on a large library.
      return await among({'Years': '$year', 'Limit': '2000'}) ??
          await among({'Years': '${year - 1},${year + 1}', 'Limit': '2000'});
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// All genres present in the user's libraries.
  Future<List<BaseItemDto>> getGenres({
    required String baseUrl,
    required String userId,
    required String token,
    String? parentId,
  }) {
    return _getItems(
      '$baseUrl/Genres',
      token,
      query: {
        'UserId': userId,
        'ParentId': ?parentId,
        'SortBy': 'SortName',
        'Recursive': 'true',
      },
    );
  }

/// The user's playlists.
  Future<List<BaseItemDto>> getPlaylists({
    required String baseUrl,
    required String userId,
    required String token,
  }) {
    return _getItems(
      '$baseUrl/Items',
      token,
      legacyUrl: '$baseUrl/Users/$userId/Items',
      query: {
        'userId': userId,
        'IncludeItemTypes': 'Playlist',
        'Recursive': 'true',
        'SortBy': 'SortName',
        'Fields': 'ChildCount,PrimaryImageAspectRatio',
      },
    );
  }

/// The items inside a playlist, in playlist order. Each carries a
  /// `PlaylistItemId` used to remove it.
  Future<List<BaseItemDto>> getPlaylistItems({
    required String baseUrl,
    required String userId,
    required String token,
    required String playlistId,
  }) {
    return _getItems(
      '$baseUrl/Playlists/$playlistId/Items',
      token,
      query: {
        'UserId': userId,
        'Fields': 'PrimaryImageAspectRatio,ProductionYear',
      },
    );
  }

/// Create a playlist, optionally seeded with items. Returns the new id.
  Future<String> createPlaylist({
    required String baseUrl,
    required String userId,
    required String token,
    required String name,
    List<String> itemIds = const [],
  }) async {
    try {
      final res = await _dio.post(
        '$baseUrl/Playlists',
        data: {
          'Name': name,
          'UserId': userId,
          if (itemIds.isNotEmpty) 'Ids': itemIds,
        },
        options: _authed(token),
      );
      return (res.data as Map?)?['Id'] as String? ?? '';
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

Future<void> addToPlaylist({
    required String baseUrl,
    required String userId,
    required String token,
    required String playlistId,
    required List<String> itemIds,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/Playlists/$playlistId/Items',
        queryParameters: {'Ids': itemIds.join(','), 'UserId': userId},
        options: _authed(token),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// Remove entries from a playlist. [entryIds] are the per-entry
  /// `PlaylistItemId`s, not the underlying item ids.
  Future<void> removeFromPlaylist({
    required String baseUrl,
    required String token,
    required String playlistId,
    required List<String> entryIds,
  }) async {
    try {
      await _dio.delete(
        '$baseUrl/Playlists/$playlistId/Items',
        queryParameters: {'EntryIds': entryIds.join(',')},
        options: _authed(token),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

Future<void> deletePlaylist({
    required String baseUrl,
    required String token,
    required String playlistId,
  }) => deleteItem(baseUrl: baseUrl, token: token, itemId: playlistId);

/// Move a playlist entry to a new index. [entryId] is the per-entry
  /// PlaylistItemId (not the underlying item id).
  Future<void> movePlaylistItem({
    required String baseUrl,
    required String token,
    required String playlistId,
    required String entryId,
    required int newIndex,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/Playlists/$playlistId/Items/$entryId/Move/$newIndex',
        options: _authed(token),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// All studios/networks across the user's libraries.
  Future<List<BaseItemDto>> getStudios({
    required String baseUrl,
    required String userId,
    required String token,
  }) {
    return _getItems(
      '$baseUrl/Studios',
      token,
      query: {'UserId': userId, 'SortBy': 'SortName', 'Recursive': 'true'},
    );
  }

/// All music artists.
  Future<List<BaseItemDto>> getArtists({
    required String baseUrl,
    required String userId,
    required String token,
  }) {
    return _getItems(
      '$baseUrl/Artists',
      token,
      query: {
        'UserId': userId,
        'SortBy': 'SortName',
        'Recursive': 'true',
        'Fields': 'PrimaryImageAspectRatio',
      },
    );
  }

/// The signed-in user, including their live policy (admin / delete rights).
  Future<UserDto> getCurrentUser({
    required String baseUrl,
    required String token,
  }) async {
    try {
      final res = await _dio.get('$baseUrl/Users/Me', options: _authed(token));
      return UserDto.fromJson(Map<String, dynamic>.from(res.data as Map));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// Full details for a single item (Overview, Genres, runtime, resume, ...).
  /// Subtitles the server's providers (OpenSubtitles and the like, set up as
  /// server plugins) have for this title, best first.
  ///
  /// The server does the searching: Fathom never talks to a provider, so
  /// nothing here depends on which provider is installed.
  Future<List<RemoteSubtitle>> searchRemoteSubtitles({
    required String baseUrl,
    required String token,
    required String itemId,
    required String language,
  }) async {
    try {
      final res = await _dio.get(
        '$baseUrl/Items/$itemId/RemoteSearch/Subtitles/$language',
        options: _authed(token),
      );
      final list = (res.data as List?) ?? const [];
      final out = [
        for (final e in list.whereType<Map>())
          RemoteSubtitle.fromJson(Map<String, dynamic>.from(e)),
      ];
      return sortRemoteSubtitles(out);
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

  /// Downloads one of those onto the server, beside the video. It then shows
  /// up as an ordinary external subtitle track for every client.
  Future<void> downloadRemoteSubtitle({
    required String baseUrl,
    required String token,
    required String itemId,
    required String subtitleId,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/Items/$itemId/RemoteSearch/Subtitles/$subtitleId',
        options: _authed(token),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

  Future<BaseItemDto> getItem({
    required String baseUrl,
    required String userId,
    required String token,
    required String itemId,
  }) async {
    try {
      final res = await requestWithFallback(
        'GET',
        url: '$baseUrl/Items/$itemId',
        legacyUrl: '$baseUrl/Users/$userId/Items/$itemId',
        token: token,
        query: {'userId': userId},
      );
      return BaseItemDto.fromJson(Map<String, dynamic>.from(res.data as Map));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// The raw item JSON (full detail: overview, people, genres, images), so a
  /// downloaded item's detail can be stored and rebuilt offline. Returns null on
  /// failure; best-effort.
  Future<Map<String, dynamic>?> getItemJson({
    required String baseUrl,
    required String userId,
    required String token,
    required String itemId,
  }) async {
    try {
      final res = await requestWithFallback(
        'GET',
        url: '$baseUrl/Items/$itemId',
        legacyUrl: '$baseUrl/Users/$userId/Items/$itemId',
        token: token,
        query: {'userId': userId},
      );
      return Map<String, dynamic>.from(res.data as Map);
    } catch (_) {
      return null;
    }
  }

/// Titles similar to [itemId] ("More Like This").
  Future<List<BaseItemDto>> getSimilar({
    required String baseUrl,
    required String userId,
    required String token,
    required String itemId,
    int limit = 16,
  }) async {
    return _getItems(
      '$baseUrl/Items/$itemId/Similar',
      token,
      query: {
        'UserId': userId,
        'Limit': '$limit',
        'Fields': 'PrimaryImageAspectRatio',
      },
    );
  }

/// Deletes an item from the server (requires delete permission).
  Future<void> deleteItem({
    required String baseUrl,
    required String token,
    required String itemId,
  }) async {
    try {
      await _dio.delete('$baseUrl/Items/$itemId', options: _authed(token));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// Triggers a metadata refresh for an item (requires permission).
  Future<void> refreshItem({
    required String baseUrl,
    required String token,
    required String itemId,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/Items/$itemId/Refresh',
        queryParameters: {
          'metadataRefreshMode': 'FullRefresh',
          'imageRefreshMode': 'FullRefresh',
        },
        options: _authed(token),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// Marks an item played or unplayed.
  Future<void> setPlayed({
    required String baseUrl,
    required String userId,
    required String token,
    required String itemId,
    required bool played,
  }) async {
    try {
      await requestWithFallback(
        played ? 'POST' : 'DELETE',
        url: '$baseUrl/UserPlayedItems/$itemId',
        legacyUrl: '$baseUrl/Users/$userId/PlayedItems/$itemId',
        token: token,
        query: {'userId': userId},
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// A title's bonus material: behind the scenes, deleted scenes, interviews,
  /// featurettes and the like, plus any trailer files held on the server (which
  /// are separate from the RemoteTrailers URL the detail page's trailer button
  /// uses). Theme songs and theme videos are dropped: they're background audio
  /// for a detail page, not something to sit and watch, and every other client
  /// hides them too.
  Future<List<BaseItemDto>> getExtras({
    required String baseUrl,
    required String userId,
    required String token,
    required String itemId,
  }) async {
    Future<List<BaseItemDto>> fetch(String kind) async {
      List<dynamic> raw;
      try {
        final res = await _dio.get(
          '$baseUrl/Items/$itemId/$kind',
          queryParameters: {'userId': userId},
          options: _authed(token),
        );
        raw = (res.data as List?) ?? const [];
      } on DioException catch (e) {
        // The route moved in 10.10; older servers only have the per-user one.
        if (e.response?.statusCode != 404) {
          throw JellyfinException(_friendlyDioError(e), cause: e);
        }
        try {
          final res = await _dio.get(
            '$baseUrl/Users/$userId/Items/$itemId/$kind',
            options: _authed(token),
          );
          raw = (res.data as List?) ?? const [];
        } on DioException catch (e2) {
          throw JellyfinException(_friendlyDioError(e2), cause: e2);
        }
      }
      return raw
          .whereType<Map>()
          .map((e) => BaseItemDto.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    final lists = await Future.wait(
        [fetch('SpecialFeatures'), fetch('LocalTrailers')]);
    final seen = <String>{};
    final out = <BaseItemDto>[];
    for (final item in [...lists[1], ...lists[0]]) {
      const themes = {'ThemeSong', 'ThemeVideo'};
      if (themes.contains(item.extraType)) continue;
      if (seen.add(item.id)) out.add(item);
    }
    return out;
  }

/// Clears an item's resume position, which is what takes it out of Continue
  /// Watching: that row is simply the items whose position is above zero.
  ///
  /// The played flag is left alone, matching Jellyfin's own web client, so the
  /// title is not silently marked watched and comes back if it's played again.
  Future<void> clearResumePosition({
    required String baseUrl,
    required String userId,
    required String token,
    required String itemId,
  }) async {
    const body = {'PlaybackPositionTicks': 0};
    try {
      await _dio.post(
        '$baseUrl/UserItems/$itemId/UserData',
        queryParameters: {'userId': userId},
        data: body,
        options: _authed(token),
      );
    } on DioException catch (e) {
      // The route moved in 10.10; older servers only have the per-user one.
      if (e.response?.statusCode == 404) {
        try {
          await _dio.post(
            '$baseUrl/Users/$userId/Items/$itemId/UserData',
            data: body,
            options: _authed(token),
          );
          return;
        } on DioException catch (e2) {
          throw JellyfinException(_friendlyDioError(e2), cause: e2);
        }
      }
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// Adds or removes an item from favorites.
  Future<void> setFavorite({
    required String baseUrl,
    required String userId,
    required String token,
    required String itemId,
    required bool favorite,
  }) async {
    try {
      await requestWithFallback(
        favorite ? 'POST' : 'DELETE',
        url: '$baseUrl/UserFavoriteItems/$itemId',
        legacyUrl: '$baseUrl/Users/$userId/FavoriteItems/$itemId',
        token: token,
        query: {'userId': userId},
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// Skippable media segments (intro/credits/…) for an item. Empty when the
  /// server has no Media Segments provider — degrade gracefully, never throw.
  Future<List<MediaSegment>> getMediaSegments({
    required String baseUrl,
    required String token,
    required String itemId,
  }) async {
    try {
      // The endpoint filters by includeSegmentTypes. ASP.NET binds an omitted
      // `IReadOnlyList<MediaSegmentType>` to an EMPTY (non-null) list, so leaving
      // it off makes the server filter to nothing and return zero segments —
      // which is why Skip Intro/Credits never appeared. Ask for every type we
      // can skip, sent as repeated query keys (ListFormat.multi), which is what
      // the server's list binder expects.
      final res = await _dio.get(
        '$baseUrl/MediaSegments/$itemId',
        queryParameters: const {
          'includeSegmentTypes': [
            'Intro',
            'Outro',
            'Recap',
            'Preview',
            'Commercial',
          ],
        },
        options: _authed(token).copyWith(listFormat: ListFormat.multi),
      );
      final items = (res.data['Items'] as List? ?? const []);
      return items
          .whereType<Map>()
          .map((e) => MediaSegment.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on DioException catch (e) {
      // Don't blind-swallow: a real failure should be distinguishable from a
      // server that simply has no Media Segments provider (empty success).
      Diagnostics.instance.add(
        'jellyfin',
        'MediaSegments $itemId failed: ${e.response?.statusCode ?? e.type}',
      );
      return const [];
    }
  }

/// The next episode to watch for a series, or null if none.
  Future<BaseItemDto?> getNextUp({
    required String baseUrl,
    required String userId,
    required String token,
    required String seriesId,
  }) async {
    try {
      final res = await _dio.get(
        '$baseUrl/Shows/NextUp',
        queryParameters: {
          'UserId': userId,
          'SeriesId': seriesId,
          'Limit': '1',
          'Fields': 'Overview,PrimaryImageAspectRatio',
        },
        options: _authed(token),
      );
      final items = (res.data['Items'] as List? ?? const []);
      if (items.isEmpty) return null;
      return BaseItemDto.fromJson(
        Map<String, dynamic>.from(items.first as Map),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// Episodes for a series (optionally a single season), in order.
  Future<List<BaseItemDto>> getEpisodes({
    required String baseUrl,
    required String userId,
    required String token,
    required String seriesId,
    String? seasonId,
  }) async {
    return _getItems(
      '$baseUrl/Shows/$seriesId/Episodes',
      token,
      query: {
        'UserId': userId,
        'SeasonId': ?seasonId,
        // ChannelId is retained on recorded episodes (a DVR marker a normal
        // library episode never has), so downloads can classify recordings.
        'Fields': 'Overview,PrimaryImageAspectRatio,ChannelId',
      },
    );
  }
}
