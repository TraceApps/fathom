import 'package:dio/dio.dart';

import '../models/download_client.dart';
import 'arr_client.dart' show ArrException;

/// A download client behind Sonarr, Radarr and Lidarr, spoken to directly:
/// its list, its speed, pausing and removing, and adding a link.
abstract class DownloadClient {
  DownloadClientKind get kind;
  String get appName => kind.appName;

  /// The version, after checking the address really is this client and it
  /// takes the sign-in. Throws otherwise.
  Future<String> version();

  /// Its downloads and how it's doing as a whole.
  Future<DownloadClientState> load();

  Future<void> pause(DownloadItem item);
  Future<void> resume(DownloadItem item);

  /// Takes it off the list, and with [deleteFiles] off the disk too.
  Future<void> remove(DownloadItem item, {required bool deleteFiles});

  Future<void> pauseAll();
  Future<void> resumeAll();

  /// The categories a new download can go in.
  Future<List<String>> categories();

  /// Adds a magnet link, or a link to a .torrent or an NZB.
  Future<void> add(String url, {String? category});
}

/// What a client's refusal or silence means, in a sentence.
String downloadErrorMessage(String app, DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionError:
    case DioExceptionType.connectionTimeout:
      return 'Could not reach $app.';
    case DioExceptionType.receiveTimeout:
      return '$app took too long to answer.';
    default:
      break;
  }
  final code = e.response?.statusCode;
  final data = e.response?.data;
  if (data is Map && data['error'] is String) {
    return '$app: ${data['error']}';
  }
  if (code == 404) return "$app isn't at this address (404).";
  return '$app error (${code ?? 'unknown'}).';
}

// -------------------------------------------------------------- qBittorrent

/// qBittorrent's Web API (v2). It signs in with a username and password and
/// keeps the session in a cookie, renewed when it runs out.
class QbitClient extends DownloadClient {
  final String baseUrl;
  final String username;
  final String password;
  final Dio _dio;

  /// "QBT_SID_8080=..." (5.x names it by port) or "SID=..." (4.x).
  String? _cookie;

  /// Why qBittorrent refused the sign-in, once it has. It isn't asked
  /// again with the same username and password: after a few failures in a
  /// row it bans the device for an hour (its browser too), and the page
  /// asks every few seconds. New settings make a new client.
  String? _refused;

  /// The sign-in under way, shared by everything asked meanwhile.
  Future<void>? _signingIn;

  QbitClient(String baseUrl, this.username, this.password, {Dio? dio})
    : baseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), ''),
      _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
            ),
          );

  @override
  DownloadClientKind get kind => DownloadClientKind.qbittorrent;

  String _api(String path) => '$baseUrl/api/v2/$path';

  /// Signs in. A client set to let this network in without one answers
  /// everything anyway, so a blank username skips it.
  Future<void> _login() {
    final refused = _refused;
    if (refused != null) return Future.error(ArrException(refused));
    return _signingIn ??= _signIn().whenComplete(() => _signingIn = null);
  }

  Future<void> _signIn() async {
    if (username.isEmpty && password.isEmpty) return;
    final Response<dynamic> r;
    try {
      r = await _dio.post(
        _api('auth/login'),
        data: {'username': username, 'password': password},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
        ),
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401) {
        // 5.x refuses a wrong password, and a Host header it doesn't
        // expect, the same way.
        throw ArrException(
          _refused =
              "qBittorrent refused the sign-in. Check the username and "
              "password. Behind a reverse proxy or a mapped port, turn off "
              "Host header validation in qBittorrent's Options > WebUI.",
        );
      }
      if (code == 403) {
        throw ArrException(
          _refused =
              'qBittorrent has blocked this device after too many failed '
              'sign-ins. Try again later.',
        );
      }
      throw ArrException(downloadErrorMessage(appName, e));
    }
    // 4.x answers 200 either way, "Fails." for a wrong password.
    if ('${r.data}'.trim() == 'Fails.') {
      throw ArrException(
        _refused =
            'qBittorrent refused the sign-in. Check the username and password.',
      );
    }
    final cookies = r.headers['set-cookie'] ?? const <String>[];
    for (final c in cookies) {
      final pair = c.split(';').first.trim();
      // Its own cookie, not one a proxy in front of it sets.
      if (RegExp(r'^(QBT_)?SID(_\d+)?=').hasMatch(pair)) {
        _cookie = pair;
        return;
      }
    }
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? form,
    Map<String, dynamic>? query,
    bool again = true,
  }) async {
    if (_cookie == null) await _login();
    try {
      final r = await _dio.request(
        _api(path),
        data: form,
        queryParameters: query,
        options: Options(
          method: method,
          contentType: form == null ? null : Headers.formUrlEncodedContentType,
          headers: {'Cookie': ?_cookie},
        ),
      );
      return r.data;
    } on DioException catch (e) {
      // The session ran out: sign in again, once.
      if (e.response?.statusCode == 403 && again) {
        _cookie = null;
        await _login();
        return _send(method, path, form: form, query: query, again: false);
      }
      if (e.response?.statusCode == 403) {
        throw ArrException(
          'qBittorrent wants a sign-in. Add the username and password in '
          'Settings.',
        );
      }
      if (e.response?.statusCode == 409 && path == 'torrents/add') {
        throw ArrException(
          "qBittorrent couldn't add it: it's already there, or the link "
          "isn't a torrent.",
        );
      }
      throw ArrException(downloadErrorMessage(appName, e));
    }
  }

  @override
  Future<String> version() async {
    final v = '${await _send('GET', 'app/version')}'.trim();
    // "v5.3.0": anything else at this address isn't qBittorrent.
    if (!RegExp(r'^v?\d+\.\d+').hasMatch(v)) {
      throw ArrException("This address doesn't answer as qBittorrent.");
    }
    return v.startsWith('v') ? v.substring(1) : v;
  }

  /// Everything at once: its torrents, speeds and state (sync/maindata).
  @override
  Future<DownloadClientState> load() async {
    final data = await _send('GET', 'sync/maindata', query: {'rid': 0});
    if (data is! Map) {
      throw ArrException('qBittorrent sent something unexpected.');
    }
    final s = data['server_state'] is Map
        ? Map<String, dynamic>.from(data['server_state'] as Map)
        : const <String, dynamic>{};
    final torrents = data['torrents'] is Map
        ? Map<String, dynamic>.from(data['torrents'] as Map)
        : const <String, dynamic>{};
    final items =
        [
            for (final e in torrents.entries)
              if (e.value is Map)
                DownloadItem.fromQbit({
                  ...Map<String, dynamic>.from(e.value as Map),
                  'hash': e.key,
                }),
          ]
          // The newest first, as it has no order of its own to keep: the
          // answer's order can change from one ask to the next.
          ..sort((a, b) {
            final none = DateTime(0);
            final at = (b.added ?? none).compareTo(a.added ?? none);
            return at != 0 ? at : a.name.compareTo(b.name);
          });
    return (
      summary: DownloadClientSummary(
        client: kind,
        downSpeed: downloadInt(s['dl_info_speed']),
        upSpeed: downloadInt(s['up_info_speed']),
        slowMode: s['use_alt_speed_limits'] == true,
        freeSpace: s['free_space_on_disk'] == null
            ? null
            : downloadInt(s['free_space_on_disk']),
        connection: s['connection_status'] as String?,
      ),
      items: items,
    );
  }

  /// 5.x calls pausing "stop"; earlier versions answer only to "pause".
  Future<void> _either(String now, String before, String hashes) async {
    try {
      await _send('POST', 'torrents/$now', form: {'hashes': hashes});
    } on ArrException catch (e) {
      if (!e.message.contains('(404)')) rethrow;
      await _send('POST', 'torrents/$before', form: {'hashes': hashes});
    }
  }

  @override
  Future<void> pause(DownloadItem item) => _either('stop', 'pause', item.id);

  @override
  Future<void> resume(DownloadItem item) => _either('start', 'resume', item.id);

  @override
  Future<void> pauseAll() => _either('stop', 'pause', 'all');

  @override
  Future<void> resumeAll() => _either('start', 'resume', 'all');

  @override
  Future<void> remove(DownloadItem item, {required bool deleteFiles}) => _send(
    'POST',
    'torrents/delete',
    form: {'hashes': item.id, 'deleteFiles': '$deleteFiles'},
  );

  /// Turns the alternative speed limits on or off.
  Future<void> toggleSlowMode() =>
      _send('POST', 'transfer/toggleSpeedLimitsMode');

  @override
  Future<List<String>> categories() async {
    final data = await _send('GET', 'torrents/categories');
    final names = data is Map ? [for (final k in data.keys) '$k'] : <String>[];
    return names..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  @override
  Future<void> add(String url, {String? category}) async {
    final r = await _send(
      'POST',
      'torrents/add',
      form: {'urls': url, 'category': ?category},
    );
    // 4.x answers 200 either way, "Fails." for a link it couldn't add.
    if ('$r'.trim() == 'Fails.') {
      throw ArrException(
        "qBittorrent couldn't add it: it's already there, or the link "
        "isn't a torrent.",
      );
    }
  }

  /// Starts [items] again: Resume All for what was stopped part way, not
  /// the finished torrents a ratio limit stopped.
  Future<void> resumeItems(List<DownloadItem> items) =>
      _either('start', 'resume', [for (final i in items) i.id].join('|'));
}

// ------------------------------------------------------------------ SABnzbd

/// SABnzbd's API: one address, the action in `mode`, the key in the query.
class SabClient extends DownloadClient {
  final String baseUrl;
  final String apiKey;
  final Dio _dio;

  /// The line speed set in SABnzbd (Config > General), bytes a second, 0
  /// for none; asked now and then, as the queue doesn't say it.
  int? _lineSpeed;
  DateTime? _lineSpeedAt;

  SabClient(String baseUrl, this.apiKey, {Dio? dio})
    : baseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), ''),
      _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
            ),
          );

  @override
  DownloadClientKind get kind => DownloadClientKind.sabnzbd;

  Future<dynamic> _api(
    String mode, [
    Map<String, dynamic> more = const {},
  ]) async {
    try {
      final r = await _dio.get(
        '$baseUrl/api',
        queryParameters: {
          'mode': mode,
          ...more,
          'output': 'json',
          'apikey': apiKey,
        },
      );
      final data = r.data;
      // A wrong key is a 403 in 5.x, or "API Key Incorrect" text in 200.
      if (data is String && data.toLowerCase().contains('api key')) {
        throw ArrException('SABnzbd rejected the API key.');
      }
      if (data is Map && data['status'] == false && data['error'] is String) {
        throw ArrException('SABnzbd: ${data['error']}');
      }
      return data;
    } on DioException catch (e) {
      final body = '${e.response?.data ?? ''}'.toLowerCase();
      if (e.response?.statusCode == 403 || body.contains('api key')) {
        throw ArrException('SABnzbd rejected the API key.');
      }
      throw ArrException(downloadErrorMessage(appName, e));
    }
  }

  @override
  Future<String> version() async {
    // The queue needs the key; the version alone doesn't.
    final data = await _api('queue', {'limit': 1});
    final q = data is Map ? data['queue'] : null;
    if (q is! Map) {
      throw ArrException("This address doesn't answer as SABnzbd.");
    }
    return '${q['version'] ?? ''}';
  }

  @override
  Future<DownloadClientState> load() async {
    final data = await _api('queue');
    final q = data is Map ? data['queue'] : null;
    if (q is! Map) {
      throw ArrException('SABnzbd sent something unexpected.');
    }
    final paused = q['paused'] == true;
    final free = downloadDouble(q['diskspace1']);
    final line = await _lineSpeedNow();
    final abs = downloadInt(q['speedlimit_abs']);
    return (
      summary: DownloadClientSummary(
        client: kind,
        downSpeed: (downloadDouble(q['kbpersec']) * 1024).round(),
        paused: paused,
        // With a line speed set, "no limit" reads as that speed.
        speedLimit: line > 0 && abs >= line ? 0 : abs,
        // In GB (1024^3).
        freeSpace: free > 0 ? (free * 1024 * 1024 * 1024).round() : null,
      ),
      items: [
        for (final s in (q['slots'] as List?) ?? const [])
          if (s is Map)
            DownloadItem.fromSab(
              Map<String, dynamic>.from(s),
              queuePaused: paused,
            ),
      ],
    );
  }

  Future<int> _lineSpeedNow() async {
    final at = _lineSpeedAt;
    if (_lineSpeed != null &&
        at != null &&
        DateTime.now().difference(at) < const Duration(minutes: 1)) {
      return _lineSpeed!;
    }
    final data = await _api('get_config', {
      'section': 'misc',
      'keyword': 'bandwidth_max',
    });
    final misc = data is Map && data['config'] is Map
        ? (data['config'] as Map)['misc']
        : null;
    _lineSpeedAt = DateTime.now();
    return _lineSpeed = sabSpeed(misc is Map ? misc['bandwidth_max'] : null);
  }

  /// The newest [limit] finished jobs.
  Future<List<DownloadHistoryItem>> history({int limit = 50}) async {
    final data = await _api('history', {'limit': limit});
    final h = data is Map ? data['history'] : null;
    return [
      if (h is Map)
        for (final s in (h['slots'] as List?) ?? const [])
          if (s is Map)
            DownloadHistoryItem.fromSab(Map<String, dynamic>.from(s)),
    ];
  }

  @override
  Future<void> pause(DownloadItem item) =>
      _api('queue', {'name': 'pause', 'value': item.id});

  @override
  Future<void> resume(DownloadItem item) =>
      _api('queue', {'name': 'resume', 'value': item.id});

  @override
  Future<void> pauseAll() => _api('pause');

  @override
  Future<void> resumeAll() => _api('resume');

  @override
  Future<void> remove(DownloadItem item, {required bool deleteFiles}) => _api(
    'queue',
    {'name': 'delete', 'value': item.id, 'del_files': deleteFiles ? 1 : 0},
  );

  Future<void> removeHistory(
    DownloadHistoryItem item, {
    required bool deleteFiles,
  }) => _api('history', {
    'name': 'delete',
    'value': item.id,
    'del_files': deleteFiles ? 1 : 0,
  });

  Future<void> retry(DownloadHistoryItem item) =>
      _api('retry', {'value': item.id});

  /// Puts a job first in the queue.
  Future<void> moveToTop(DownloadItem item) =>
      _api('switch', {'value': item.id, 'value2': 0});

  /// Limits the download speed to [bytesPerSecond], or lifts it with 0.
  /// SABnzbd takes "5M" as megabytes a second.
  Future<void> setSpeedLimit(int bytesPerSecond) => _api('config', {
    'name': 'speedlimit',
    'value': bytesPerSecond <= 0
        ? 0
        : '${(bytesPerSecond / (1024 * 1024)).round()}M',
  });

  @override
  Future<List<String>> categories() async {
    final data = await _api('get_cats');
    final list = data is Map ? data['categories'] : null;
    return [
      for (final c in (list as List?) ?? const [])
        if (c is String && c != '*') c,
    ];
  }

  @override
  Future<void> add(String url, {String? category}) =>
      _api('addurl', {'name': url, 'cat': ?category});
}

/// SABnzbd's speeds as it writes them: "100M", "500K", "1G", or bytes;
/// 0 for none.
int sabSpeed(Object? v) {
  final m = RegExp(
    r'^\s*([\d.]+)\s*([KMG]?)',
    caseSensitive: false,
  ).firstMatch('${v ?? ''}');
  if (m == null) return 0;
  final n = double.tryParse(m[1]!) ?? 0;
  final unit = switch (m[2]!.toUpperCase()) {
    'K' => 1024,
    'M' => 1024 * 1024,
    'G' => 1024 * 1024 * 1024,
    _ => 1,
  };
  return (n * unit).round();
}
