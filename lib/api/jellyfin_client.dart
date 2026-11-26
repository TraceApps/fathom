import 'dart:convert';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';

import '../l10n/l10n.dart';
import 'error_text.dart';
import '../models/authentication_result.dart';
import '../models/base_item.dart';
import '../models/items_result.dart';
import '../models/media_segment.dart';
import '../models/public_system_info.dart';
import '../models/user_dto.dart';
import '../models/lyrics.dart';
import '../models/remote_subtitle.dart';
import '../services/diagnostics.dart';
import '../services/tv_mode.dart';

part 'jellyfin_admin.dart';
part 'jellyfin_auth.dart';
part 'jellyfin_library.dart';
part 'jellyfin_livetv.dart';
part 'jellyfin_sessions.dart';
part 'jellyfin_streaming.dart';

/// A user-facing error carrying a message safe to show in the UI.
class JellyfinException implements Exception {
  final String message;

  /// What was caught, when this stands for a failed request: the app-wide
  /// retry rule reads it to tell a dropped connection (worth asking again)
  /// from an answer the server gave (not).
  final Object? cause;
  JellyfinException(this.message, {this.cause});
  @override
  String toString() => message;
}

/// An opened live stream: the playable URL plus the ids needed to close it and
/// release the tuner.
class LiveStreamHandle {
  final String url;
  final String? liveStreamId;
  final String? playSessionId;
  const LiveStreamHandle({
    required this.url,
    this.liveStreamId,
    this.playSessionId,
  });
}

/// Thin, typed Jellyfin API client. Grows per phase; for now it covers the
/// connect + login surface. All auth uses the MediaBrowser Authorization
/// header scheme that Jellyfin expects.

class JellyfinClient {
final String deviceId;

final String clientName;

final String clientVersion;

final Dio _dio;

/// [httpClient] is for tests, which swap in an adapter to inspect what
  /// actually goes over the wire. Production leaves it null.
  JellyfinClient({
    required this.deviceId,
    this.clientName = 'Fathom',
    this.clientVersion = '0.1.0',
    Dio? httpClient,
  }) : _dio =
           httpClient ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 20),
             ),
           ) {
    // A request the server refused for its sign-in token: whoever keeps the
    // session is told, so the app can ask to sign in again instead of showing
    // "error (401)" on every row.
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (e, handler) {
          if (e.response?.statusCode == 401) {
            final token = _tokenOf(e.requestOptions);
            if (token != null) onUnauthorized?.call(token);
          }
          handler.next(e);
        },
      ),
    );
  }

  /// Called with the sign-in token a request carried when the server answers
  /// it with 401. Not called for a sign-in itself, which carries none.
  void Function(String token)? onUnauthorized;

  static final _tokenInHeader = RegExp(r'Token="([^"]+)"');

  /// The sign-in token [o] carried, in its header or its address.
  static String? _tokenOf(RequestOptions o) {
    final header = o.headers['Authorization'];
    if (header is String) {
      final m = _tokenInHeader.firstMatch(header);
      if (m != null) return m[1];
    }
    for (final e in o.uri.queryParameters.entries) {
      final k = e.key.toLowerCase();
      if ((k == 'api_key' || k == 'apikey') && e.value.isNotEmpty) {
        return e.value;
      }
    }
    return null;
  }

  /// Whether the server no longer takes [token]: asked of the one thing any
  /// signed-in user may read, their own account. False when the server can't
  /// be reached or says anything else: only a plain 401 here means signed
  /// out (revoked, the device removed, the user's password changed).
  Future<bool> tokenRefused({
    required String baseUrl,
    required String token,
  }) async {
    try {
      final res = await _dio.get<dynamic>(
        '$baseUrl/Users/Me',
        options: Options(
          headers: {'Authorization': authHeader(token: token)},
          // Any answer is an answer: nothing here is an error to report.
          validateStatus: (_) => true,
        ),
      );
      return res.statusCode == 401;
    } catch (_) {
      return false;
    }
  }

/// Builds the `Authorization` header. Include [token] once authenticated.
  String authHeader({String? token}) {
    final parts = <String>[
      'MediaBrowser Client="$clientName"',
      'Device="Linux"',
      'DeviceId="$deviceId"',
      'Version="$clientVersion"',
    ];
    if (token != null) parts.add('Token="$token"');
    return parts.join(', ');
  }

/// Normalizes user-entered addresses: adds https:// if no scheme is given,
  /// trims whitespace and trailing slashes.
  static String normalizeBaseUrl(String input) {
    var url = input.trim();
    if (url.isEmpty) {
      throw JellyfinException(tr.errEnterAddress);
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    return url.replaceAll(RegExp(r'/+$'), '');
  }

String _friendlyDioError(DioException e, {bool connecting = false}) =>
    dioErrorText(e, connecting: connecting);

  /// Calls a route Jellyfin 12 documents, falling back to the per-user route
  /// older servers use.
  ///
  /// Jellyfin 12 dropped the whole `/Users/{userId}/...` family from its API
  /// (measured against a 12.1 server's own spec): `/Items?userId=` replaces
  /// `/Users/{id}/Items`, `/UserViews` replaces `/Users/{id}/Views`, and so on.
  /// The old routes still answer on 12.1, but they are no longer part of the
  /// API, so they can go at any point. Fathom asks for the documented one and
  /// only drops back when a server hasn't got it, which keeps 10.x working.
  Future<Response<dynamic>> requestWithFallback(
    String method, {
    required String url,
    required String legacyUrl,
    required String token,
    Map<String, dynamic>? query,
    Map<String, dynamic>? legacyQuery,
    Object? data,
  }) async {
    Future<Response<dynamic>> send(String at, Map<String, dynamic>? q) =>
        _dio.request(
          at,
          data: data,
          queryParameters: q,
          options: Options(
            method: method,
            headers: {'Authorization': authHeader(token: token)},
          ),
        );
    try {
      return await send(url, query);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code != 404 && code != 405) rethrow;
      return send(legacyUrl, legacyQuery ?? query);
    }
  }

}
