part of 'jellyfin_client.dart';

/// Server administration: users, devices, plugins, scheduled tasks, configuration, API keys and logs.
extension JellyfinAdminApi on JellyfinClient {
Future<List<Map<String, dynamic>>> getUsers({
    required String baseUrl,
    required String token,
  }) => _getList('$baseUrl/Users', token);

Future<Map<String, dynamic>> getUser({
    required String baseUrl,
    required String token,
    required String userId,
  }) async {
    try {
      final res = await _dio.get(
        '$baseUrl/Users/$userId',
        options: _authed(token),
      );
      return Map<String, dynamic>.from(res.data as Map);
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

Future<void> updateUserPolicy({
    required String baseUrl,
    required String token,
    required String userId,
    required Map<String, dynamic> policy,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/Users/$userId/Policy',
        data: policy,
        options: _authed(token),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

Future<Map<String, dynamic>> createUser({
    required String baseUrl,
    required String token,
    required String name,
    String? password,
  }) async {
    try {
      final res = await _dio.post(
        '$baseUrl/Users/New',
        data: {
          'Name': name,
          if (password != null && password.isNotEmpty) 'Password': password,
        },
        options: _authed(token),
      );
      return Map<String, dynamic>.from((res.data as Map?) ?? {});
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

Future<void> deleteUser({
    required String baseUrl,
    required String token,
    required String userId,
  }) async {
    try {
      await _dio.delete('$baseUrl/Users/$userId', options: _authed(token));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// Sets a user's password. An admin resetting someone else passes null for
  /// [newPassword] (clears it, no verification needed). A user changing their
  /// OWN password passes [newPassword] (an empty string sets no password at
  /// all — the same "remove password" the official clients allow) plus
  /// [currentPassword] ([CurrentPw]); the server verifies it and rejects the
  /// change if it's wrong or self-service is disabled for the account.
  Future<void> setUserPassword({
    required String baseUrl,
    required String token,
    required String userId,
    String? currentPassword,
    String? newPassword,
  }) async {
    try {
      await requestWithFallback(
        'POST',
        url: '$baseUrl/Users/Password',
        legacyUrl: '$baseUrl/Users/$userId/Password',
        token: token,
        query: {'userId': userId},
        data: newPassword == null
            ? {'ResetPassword': true}
            : {
                'CurrentPw': ?currentPassword,
                'NewPw': newPassword,
              },
      );
    } on DioException catch (e) {
      // A 400 here almost always means the server's password validation
      // rejected the request rather than a network/transport problem, so give
      // a specific reason instead of the generic "error (400)".
      if (e.response?.statusCode == 400) {
        if (newPassword != null && newPassword.isEmpty) {
          throw JellyfinException(tr.errAdminNeedsPassword);
        }
        throw JellyfinException(tr.errPasswordChange);
      }
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

Future<List<Map<String, dynamic>>> getVirtualFolders({
    required String baseUrl,
    required String token,
  }) => _getList('$baseUrl/Library/VirtualFolders', token);

  /// The login methods the server offers for a user (admin only). Usually
  /// just the built-in one; plugins such as LDAP add more.
  Future<List<Map<String, dynamic>>> getAuthProviders({
    required String baseUrl,
    required String token,
  }) =>
      _getList('$baseUrl/Auth/Providers', token);

  /// The password reset methods the server offers (admin only).
  Future<List<Map<String, dynamic>>> getPasswordResetProviders({
    required String baseUrl,
    required String token,
  }) =>
      _getList('$baseUrl/Auth/PasswordResetProviders', token);

  /// Channels provided by server plugins, which a user's access can be
  /// limited to. Most servers have none.
  Future<List<Map<String, dynamic>>> getChannelsForAccess({
    required String baseUrl,
    required String token,
  }) =>
      _getList('$baseUrl/Channels', token, itemsKey: 'Items');

/// Client devices that have connected to the server (admin only).
  Future<List<Map<String, dynamic>>> getDevices({
    required String baseUrl,
    required String token,
  }) async {
    try {
      final res = await _dio.get('$baseUrl/Devices', options: _authed(token));
      final items = (res.data as Map)['Items'] as List? ?? const [];
      return items
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// Removes (deauthorizes) a client device by id (admin only).
  Future<void> deleteDevice({
    required String baseUrl,
    required String token,
    required String id,
  }) async {
    try {
      await _dio.delete(
        '$baseUrl/Devices',
        queryParameters: {'id': id},
        options: _authed(token),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// The server's parental rating names and their numeric scores.
  Future<List<Map<String, dynamic>>> getParentalRatings({
    required String baseUrl,
    required String token,
  }) async {
    try {
      final res = await _dio.get(
        '$baseUrl/Localization/ParentalRatings',
        options: _authed(token),
      );
      return (res.data as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// URL for an installed plugin's thumbnail image.
  ///
  /// Jellyfin 12 documents this per version (`/Plugins/{id}/{version}/Image`);
  /// the version-less route it replaced is gone from the API. Falls back to
  /// the old shape when the caller has no version to hand.
  String pluginImageUrl({
    required String baseUrl,
    required String pluginId,
    String? version,
  }) =>
      (version == null || version.isEmpty)
          ? '$baseUrl/Plugins/$pluginId/Image'
          : '$baseUrl/Plugins/$pluginId/$version/Image';

/// A plugin's own configuration object (admin only). Throws if the plugin has
  /// no editable configuration.
  Future<Map<String, dynamic>> getPluginConfiguration({
    required String baseUrl,
    required String token,
    required String pluginId,
  }) async {
    try {
      final res = await _dio.get(
        '$baseUrl/Plugins/$pluginId/Configuration',
        options: _authed(token),
      );
      final data = res.data;
      return data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{};
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// Writes back a plugin's configuration object (admin only).
  Future<void> updatePluginConfiguration({
    required String baseUrl,
    required String token,
    required String pluginId,
    required Map<String, dynamic> config,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/Plugins/$pluginId/Configuration',
        data: config,
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

/// Installed server plugins (admin).
  Future<List<Map<String, dynamic>>> getPlugins({
    required String baseUrl,
    required String token,
  }) => _getList('$baseUrl/Plugins', token);

Future<void> scanAllLibraries({
    required String baseUrl,
    required String token,
  }) async {
    try {
      await _dio.post('$baseUrl/Library/Refresh', options: _authed(token));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

Future<List<Map<String, dynamic>>> getScheduledTasks({
    required String baseUrl,
    required String token,
  }) =>
      _getList('$baseUrl/ScheduledTasks', token, query: {'isHidden': 'false'});

Future<void> runScheduledTask({
    required String baseUrl,
    required String token,
    required String taskId,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/ScheduledTasks/Running/$taskId',
        options: _authed(token),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

Future<List<Map<String, dynamic>>> getSessions({
    required String baseUrl,
    required String token,
  }) => _getList('$baseUrl/Sessions', token);

Future<List<Map<String, dynamic>>> getActivityLog({
    required String baseUrl,
    required String token,
  }) => _getList(
    '$baseUrl/System/ActivityLog/Entries',
    token,
    query: {'limit': '50'},
    itemsKey: 'Items',
  );

Future<Map<String, dynamic>> getSystemInfo({
    required String baseUrl,
    required String token,
  }) async {
    try {
      final res = await _dio.get(
        '$baseUrl/System/Info',
        options: _authed(token),
      );
      return Map<String, dynamic>.from(res.data as Map);
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// The full server configuration (admin only). Includes the Quick Connect
  /// availability flag among many other settings.
  Future<Map<String, dynamic>> getServerConfiguration({
    required String baseUrl,
    required String token,
  }) async {
    try {
      final res = await _dio.get(
        '$baseUrl/System/Configuration',
        options: _authed(token),
      );
      return Map<String, dynamic>.from(res.data as Map);
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// Writes back the full server configuration (admin only). Read it first,
  /// mutate the fields you need, then post the whole object.
  Future<void> updateServerConfiguration({
    required String baseUrl,
    required String token,
    required Map<String, dynamic> config,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/System/Configuration',
        data: config,
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

/// Available packages from the configured plugin repositories (admin only).
  Future<List<Map<String, dynamic>>> getPackages({
    required String baseUrl,
    required String token,
  }) async {
    try {
      final res = await _dio.get('$baseUrl/Packages', options: _authed(token));
      return (res.data as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// Installs a plugin package by name (admin only). [version] and
  /// [repositoryUrl] are optional; the server picks the latest compatible
  /// version when omitted.
  Future<void> installPackage({
    required String baseUrl,
    required String token,
    required String name,
    required String guid,
    String? version,
    String? repositoryUrl,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/Packages/Installed/${Uri.encodeComponent(name)}',
        queryParameters: {
          'assemblyGuid': guid,
          'version': ?version,
          'repositoryUrl': ?repositoryUrl,
        },
        options: _authed(token),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// Uninstalls an installed plugin by its id (admin only).
  Future<void> uninstallPlugin({
    required String baseUrl,
    required String token,
    required String pluginId,
  }) async {
    try {
      await _dio.delete('$baseUrl/Plugins/$pluginId', options: _authed(token));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// The configured plugin repositories (admin only).
  Future<List<Map<String, dynamic>>> getRepositories({
    required String baseUrl,
    required String token,
  }) async {
    try {
      final res = await _dio.get(
        '$baseUrl/Repositories',
        options: _authed(token),
      );
      return (res.data as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// Replaces the plugin repository list (admin only).
  Future<void> setRepositories({
    required String baseUrl,
    required String token,
    required List<Map<String, dynamic>> repositories,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/Repositories',
        data: repositories,
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

/// A named configuration section (admin only), e.g. 'network' or 'encoding'.
  /// Branding: the login disclaimer, custom CSS, and the splash screen toggle.
  ///
  /// Branding is NOT part of ServerConfiguration — it has no 'Branding' key —
  /// so it has its own read and write. Reading it from the server config just
  /// yields null and shows the admin an empty form over a configured server.
  Future<Map<String, dynamic>> getBrandingConfiguration({
    required String baseUrl,
    required String token,
  }) async {
    try {
      final res = await _dio.get(
        '$baseUrl/Branding/Configuration',
        options: _authed(token),
      );
      return Map<String, dynamic>.from(res.data as Map);
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// Writes branding back. Note the capitalised path segment: this is its own
  /// documented endpoint, not the generic named-configuration one.
  Future<void> updateBrandingConfiguration({
    required String baseUrl,
    required String token,
    required Map<String, dynamic> branding,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/System/Configuration/Branding',
        data: branding,
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

/// Lyrics for a track, timed when the source has timing.
  ///
  /// The server sources these itself — embedded .lrc, or a lyrics provider
  /// plugin (LrcLib and the like) — so there's no third-party call from here
  /// and nothing to key or rate-limit. 404 means this track simply has none,
  /// which is common and not an error.
  Future<SongLyrics?> getLyrics({
    required String baseUrl,
    required String token,
    required String itemId,
  }) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '$baseUrl/Audio/$itemId/Lyrics',
        options: Options(
          headers: {'Authorization': authHeader(token: token)},
          validateStatus: (s) => s == 200 || s == 404,
        ),
      );
      if (res.statusCode == 404 || res.data == null) return null;
      return SongLyrics.fromJson(res.data!);
    } on DioException {
      // Lyrics are a nicety; never let a failure disturb playback.
      return null;
    }
  }

Future<Map<String, dynamic>> getNamedConfiguration({
    required String baseUrl,
    required String token,
    required String key,
  }) async {
    try {
      final res = await _dio.get(
        '$baseUrl/System/Configuration/$key',
        options: _authed(token),
      );
      return Map<String, dynamic>.from(res.data as Map);
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// Writes back a named configuration section (admin only).
  Future<void> updateNamedConfiguration({
    required String baseUrl,
    required String token,
    required String key,
    required Map<String, dynamic> config,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/System/Configuration/$key',
        data: config,
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

/// The server's backups, newest first (admin only). Null when the server has
  /// no backup API: it arrived in Jellyfin 12, and older servers answer 404.
  Future<List<Map<String, dynamic>>?> getBackups({
    required String baseUrl,
    required String token,
  }) async {
    try {
      final res = await _dio.get('$baseUrl/Backup', options: _authed(token));
      final list = [
        for (final e in (res.data as List? ?? const []).whereType<Map>())
          Map<String, dynamic>.from(e),
      ];
      list.sort((a, b) =>
          '${b['DateCreated'] ?? ''}'.compareTo('${a['DateCreated'] ?? ''}'));
      return list;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// Makes a backup (admin only). The database is always included; the other
  /// parts are optional, as in the web dashboard. The request only returns
  /// once the backup is written, which on a large library takes minutes, so it
  /// gets a far longer wait than an ordinary call.
  Future<void> createBackup({
    required String baseUrl,
    required String token,
    bool metadata = false,
    bool subtitles = false,
    bool trickplay = false,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/Backup/Create',
        data: {
          'Metadata': metadata,
          'Subtitles': subtitles,
          'Trickplay': trickplay,
          'Database': true,
        },
        options: _authed(token).copyWith(
          receiveTimeout: const Duration(hours: 2),
          sendTimeout: const Duration(minutes: 1),
        ),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// Starts restoring a backup (admin only). The server restarts to apply it
  /// and is unreachable until it's done.
  Future<void> restoreBackup({
    required String baseUrl,
    required String token,
    required String archivePath,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/Backup/Restore',
        data: {'ArchiveFileName': archivePath},
        options: _authed(token),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// API keys granted to apps (admin only).
  Future<List<Map<String, dynamic>>> getApiKeys({
    required String baseUrl,
    required String token,
  }) async {
    try {
      final res = await _dio.get('$baseUrl/Auth/Keys', options: _authed(token));
      final items = (res.data as Map)['Items'] as List? ?? const [];
      return items
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// Issues a new API key for [appName] (admin only).
  Future<void> createApiKey({
    required String baseUrl,
    required String token,
    required String appName,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/Auth/Keys',
        queryParameters: {'app': appName},
        options: _authed(token),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// Revokes an API key (admin only).
  Future<void> deleteApiKey({
    required String baseUrl,
    required String token,
    required String key,
  }) async {
    try {
      await _dio.delete('$baseUrl/Auth/Keys/$key', options: _authed(token));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// Available server log files (admin only).
  Future<List<Map<String, dynamic>>> getLogFiles({
    required String baseUrl,
    required String token,
  }) async {
    try {
      final res = await _dio.get(
        '$baseUrl/System/Logs',
        options: _authed(token),
      );
      return (res.data as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// The contents of a named server log file (admin only).
  Future<String> getLogContent({
    required String baseUrl,
    required String token,
    required String name,
  }) async {
    try {
      final res = await _dio.get(
        '$baseUrl/System/Logs/Log',
        queryParameters: {'name': name},
        options: Options(
          headers: {'Authorization': authHeader(token: token)},
          responseType: ResponseType.plain,
        ),
      );
      return '${res.data}';
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// Enables or disables Quick Connect server-wide (admin only) by toggling the
  /// `QuickConnectAvailable` flag in the server configuration.
  Future<void> setQuickConnectAvailable({
    required String baseUrl,
    required String token,
    required bool available,
  }) async {
    final config = await getServerConfiguration(baseUrl: baseUrl, token: token);
    config['QuickConnectAvailable'] = available;
    await updateServerConfiguration(
      baseUrl: baseUrl,
      token: token,
      config: config,
    );
  }

Future<void> restartServer({
    required String baseUrl,
    required String token,
  }) async {
    try {
      await _dio.post('$baseUrl/System/Restart', options: _authed(token));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

Future<void> shutdownServer({
    required String baseUrl,
    required String token,
  }) async {
    try {
      await _dio.post('$baseUrl/System/Shutdown', options: _authed(token));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

Future<void> sendSessionMessage({
    required String baseUrl,
    required String token,
    required String sessionId,
    required String header,
    required String text,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/Sessions/$sessionId/Message',
        data: {'Header': header, 'Text': text, 'TimeoutMs': 5000},
        options: _authed(token),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }
}
