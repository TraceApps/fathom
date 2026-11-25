import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fathom/api/download_clients.dart';
import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/models/download_client.dart';
import 'package:fathom/models/session.dart';
import 'package:fathom/screens/arr_screen.dart';
import 'package:fathom/screens/arr_settings_screen.dart';
import 'package:fathom/screens/download_clients_screen.dart';
import 'package:fathom/services/settings_backup.dart';
import 'package:fathom/state/arr_providers.dart';
import 'package:fathom/state/download_providers.dart';
import 'package:fathom/state/preferences.dart';
import 'package:fathom/state/session_controller.dart';
import 'package:fathom/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// The download clients in the Manage section: qBittorrent (Web API 2.16,
// 5.3) and SABnzbd (5.1), from their own answers saved from the rig. On
// qBittorrent: one torrent seeding, one with no peers, one stopped magnet
// link. On SABnzbd: one job downloading at High, one paused, one failed in
// the history.

Object? _fixture(String name) =>
    jsonDecode(File('test/fixtures/arr/$name.json').readAsStringSync());

typedef _Asked = ({
  String method,
  String path,
  Map<String, List<String>> query,
  Object? body,
  String? cookie,
});

ResponseBody _json(Object? data, [int code = 200]) => ResponseBody.fromString(
  jsonEncode(data),
  code,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

ResponseBody _text(String s, [int code = 200, Map<String, List<String>>? h]) =>
    ResponseBody.fromString(
      s,
      code,
      headers: {
        Headers.contentTypeHeader: ['text/plain; charset=UTF-8'],
        ...?h,
      },
    );

/// qBittorrent as 5.3 answers: a sign-in that sets QBT_SID_8080, 403 for
/// anything asked without it, 404 for the 4.x names of pause and resume.
class _Qbit implements HttpClientAdapter {
  final List<_Asked> asked = [];

  /// How the sign-in goes: 204 and a cookie, 401, or 4.x's 200 "Fails.".
  String login = 'ok';

  /// 4.x: "stop" and "start" don't exist yet; "pause" and "resume" do.
  bool legacy = false;

  /// A proxy sets a cookie of its own with the sign-in's.
  bool proxyCookie = false;

  /// The session runs out after this many answers (null: never), until the
  /// next sign-in.
  int? expireAfter;
  int _served = 0;
  int logins = 0;

  /// What sync/maindata answers with.
  Map<String, dynamic> maindata = Map<String, dynamic>.from(
    _fixture('qbit_maindata')! as Map,
  );

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    final path = o.uri.path.replaceFirst(RegExp(r'^.*/api/v2/'), '');
    final cookie = o.headers['Cookie'] as String?;
    asked.add((
      method: o.method,
      path: path,
      query: o.uri.queryParametersAll,
      body: o.data,
      cookie: cookie,
    ));
    if (path == 'auth/login') {
      logins++;
      _served = 0;
      expireAfter = null;
      return switch (login) {
        '401' => _text('Unauthorized', 401),
        'fails' => _text('Fails.'),
        _ => _text('', 204, {
          'set-cookie': [
            // A proxy in front can set its own first.
            if (proxyCookie) 'PHPSESSID=proxy; path=/',
            'QBT_SID_8080=sid$logins; HttpOnly; SameSite=Lax; path=/',
          ],
        }),
      };
    }
    final expired = expireAfter != null && _served >= expireAfter!;
    if (cookie != 'QBT_SID_8080=sid$logins' || expired) {
      return _text('Forbidden', 403);
    }
    _served++;
    return switch ((o.method, path)) {
      ('GET', 'app/version') => _text('v5.3.0'),
      ('GET', 'sync/maindata') => _json(maindata),
      ('GET', 'torrents/categories') => _json(_fixture('qbit_categories')),
      ('POST', 'torrents/stop' || 'torrents/start') when legacy => _text(
        'Not Found',
        404,
      ),
      ('POST', 'torrents/pause' || 'torrents/resume') when !legacy => _text(
        'Not Found',
        404,
      ),
      ('POST', 'torrents/add')
          when !(((o.data as Map)['urls'] as String).startsWith('magnet:')) =>
        legacy ? _text('Fails.') : _text('Conflict', 409),
      ('POST', _) => _text(''),
      _ => _text('Not Found', 404),
    };
  }

  @override
  void close({bool force = false}) {}

  List<_Asked> sent(String path) => [
    for (final a in asked)
      if (a.path == path) a,
  ];
}

/// SABnzbd as 5.1 answers: everything at /api by mode, the key in the
/// query, 403 "API Key Incorrect" for a wrong one.
class _Sab implements HttpClientAdapter {
  final List<_Asked> asked = [];

  /// SABnzbd's line speed setting, as it writes it ("100M"; "" for none).
  String lineSpeed = '';
  Map<String, dynamic> history = Map<String, dynamic>.from(
    _fixture('sab_history')! as Map,
  );
  Map<String, dynamic> queue = Map<String, dynamic>.from(
    _fixture('sab_queue')! as Map,
  );

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    final q = o.uri.queryParameters;
    asked.add((
      method: o.method,
      path: q['mode'] ?? '',
      query: o.uri.queryParametersAll,
      body: o.data,
      cookie: null,
    ));
    if (q['apikey'] != 'skey') return _text('API Key Incorrect', 403);
    return switch (q['mode']) {
      'queue' when q['name'] == null => _json(queue),
      'history' when q['name'] == null => _json(history),
      'get_cats' => _json(_fixture('sab_categories')),
      'get_config' => _json({
        'config': {
          'misc': {'bandwidth_max': lineSpeed},
        },
      }),
      'switch' => _json({
        'result': {'position': 0, 'priority': 0},
      }),
      _ => _json({'status': true}),
    };
  }

  @override
  void close({bool force = false}) {}

  List<Map<String, String>> sent(String mode) => [
    for (final a in asked)
      if (a.path == mode)
        {for (final e in a.query.entries) e.key: e.value.first},
  ];
}

QbitClient _qbit(_Qbit s, {String user = 'admin', String pass = 'pw'}) =>
    QbitClient(
      'http://qbit:8080',
      user,
      pass,
      dio: Dio()..httpClientAdapter = s,
    );

SabClient _sab(_Sab s, {String key = 'skey'}) =>
    SabClient('http://sab:8085', key, dio: Dio()..httpClientAdapter = s);

class _FakePrefs extends PreferencesController {
  _FakePrefs(this.initial);
  final Prefs initial;

  @override
  Future<Prefs> build() async => initial;

  @override
  Future<void> edit(Prefs Function(Prefs) change) async {
    state = AsyncData(change(state.asData?.value ?? initial));
  }
}

class _SignedOut extends SessionController {
  @override
  Future<Session?> build() async => null;
}

final _visited = <String>[];

Widget _app({_Qbit? qbit, _Sab? sab, required Widget home}) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, _) => home),
      GoRoute(
        path: '/arr/clients',
        builder: (_, s) {
          _visited.add(s.uri.toString());
          return const DownloadClientsScreen();
        },
      ),
      GoRoute(
        path: '/arr-settings',
        builder: (_, s) {
          _visited.add(s.uri.toString());
          return const SizedBox();
        },
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      qbitClientProvider.overrideWithValue(qbit == null ? null : _qbit(qbit)),
      sabClientProvider.overrideWithValue(sab == null ? null : _sab(sab)),
      prowlarrClientProvider.overrideWithValue(null),
      sonarrClientProvider.overrideWithValue(null),
      radarrClientProvider.overrideWithValue(null),
      lidarrClientProvider.overrideWithValue(null),
      preferencesProvider.overrideWith(() => _FakePrefs(const Prefs())),
      sessionControllerProvider.overrideWith(_SignedOut.new),
    ],
    child: MaterialApp.router(
      theme: AppTheme.dark(const Color(0xFF8AB4F8)),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _open(
  WidgetTester t,
  Widget app, {
  Size size = const Size(1000, 2000),
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(app);
  await _settle(t);
}

/// The row of the download named [name].
Finder _row(String name) => find.ancestor(
  of: find.text(downloadShownName(name)),
  matching: find.byWidgetPredicate(
    (w) =>
        w.key is ValueKey<String> &&
        '${(w.key as ValueKey).value}'.contains(':'),
  ),
);

const _album = 'Rig.Album.2024.FLAC';
const _movie = 'Rig.Movie.2023.1080p.mkv';
const _magnet = 'Rig.Show.S01E01.720p';
const _sabMovie = 'Rig.Movie.2022.2160p.UHD';
const _sabShow = 'Rig.Show.S02E03.1080p.WEB';

/// A download's name as its row shows it.
Finder _name(String name) => find.text(downloadShownName(name));

void main() {
  setUp(_visited.clear);

  group('qBittorrent, read', () {
    test('its torrents, speeds and space, from one maindata', () async {
      final s = _Qbit();
      final got = await _qbit(s).load();
      final by = {for (final i in got.items) i.name: i};
      expect(by[_album]!.state, DownloadState.seeding);
      expect(by[_album]!.progress, 1);
      expect(by[_album]!.size, 3000000);
      expect(by[_album]!.category, 'lidarr');
      expect(by[_movie]!.state, DownloadState.stalled);
      // 8640000 is qBittorrent's "never".
      expect(by[_movie]!.eta, isNull);
      expect(by[_magnet]!.state, DownloadState.paused);
      // A magnet link's size is -1 until its details come in.
      expect(by[_magnet]!.size, 0);
      // The hash is the map's key, not a field.
      expect(by[_movie]!.id, 'd5c4db4321eb911238ac748fe6028bfeceb74c74');
      expect(got.summary.connection, 'connected');
      expect(got.summary.slowMode, isFalse);
      expect(got.summary.freeSpace, greaterThan(0));
      expect(s.sent('sync/maindata').single.query['rid'], ['0']);
      // Added together: by name.
      expect([for (final i in got.items) i.name], [_album, _movie, _magnet]);
      // The newest first, whatever order the answer has.
      final torrents = s.maindata['torrents'] as Map;
      final movie = torrents['d5c4db4321eb911238ac748fe6028bfeceb74c74'] as Map;
      movie['added_on'] = (movie['added_on'] as int) + 60;
      final later = await _qbit(s).load();
      expect([for (final i in later.items) i.name], [_movie, _album, _magnet]);
    });

    test('after the first answer, only what changed: put together', () async {
      // qBittorrent 5.3's own answers, one after another: everything; then a
      // torrent stopped (its state alone); then one removed.
      final steps = [
        for (final n in ['full', 'partial', 'removed'])
          Map<String, dynamic>.from(_fixture('qbit_sync_$n')! as Map),
      ];
      final s = _Qbit();
      final c = _qbit(s);
      final got = <DownloadClientState>[];
      for (final step in steps) {
        s.maindata = step;
        got.add(await c.load());
      }
      // Each ask says where the last answer got to.
      expect([for (final a in s.sent('sync/maindata')) a.query['rid']], [
        ['0'],
        ['${steps[0]['rid']}'],
        ['${steps[1]['rid']}'],
      ]);
      final full = got[0].items;
      expect(full, hasLength(2));
      final movie = full.firstWhere((i) => i.name.contains('Movie'));
      expect(movie.state, DownloadState.stalled);
      // The stopped one keeps everything else it had (its name, size,
      // category) with its new state.
      final stopped = got[1].items.firstWhere((i) => i.id == movie.id);
      expect(stopped.state, DownloadState.paused);
      expect((stopped.name, stopped.size), (movie.name, movie.size));
      expect(got[1].items, hasLength(2));
      // The removed one is gone; the other stays.
      expect([for (final i in got[2].items) i.id], [movie.id]);
      // Speeds and space: what the server state last said of each.
      expect(got[2].summary.freeSpace, got[0].summary.freeSpace);
      expect(got[2].summary.connection, got[0].summary.connection);
    });

    test('an answer in full starts afresh (a new session, a lost place)', () async {
      final s = _Qbit();
      final c = _qbit(s);
      s.maindata = Map<String, dynamic>.from(_fixture('qbit_sync_full')! as Map);
      await c.load();
      // Everything again, without one of them: it's gone, not kept.
      final full = Map<String, dynamic>.from(_fixture('qbit_maindata')! as Map);
      s.maindata = full;
      final got = await c.load();
      expect(
        {for (final i in got.items) i.id},
        {for (final h in (full['torrents'] as Map).keys) h},
      );
    });

    test('every state, 5.x names and 4.x ones', () {
      expect(qbitState('stoppedDL'), DownloadState.paused);
      expect(qbitState('pausedDL'), DownloadState.paused);
      expect(qbitState('stoppedUP'), DownloadState.done);
      expect(qbitState('pausedUP'), DownloadState.done);
      expect(qbitState('stalledUP'), DownloadState.seeding);
      expect(qbitState('forcedUP'), DownloadState.seeding);
      expect(qbitState('metaDL'), DownloadState.fetching);
      expect(qbitState('forcedDL'), DownloadState.downloading);
      expect(qbitState('queuedUP'), DownloadState.queued);
      expect(qbitState('checkingResumeData'), DownloadState.checking);
      expect(qbitState('moving'), DownloadState.moving);
      expect(qbitState('missingFiles'), DownloadState.failed);
      expect(qbitState('error'), DownloadState.failed);
      expect(qbitState('somethingNew'), DownloadState.queued);
      // A magnet link without its details yet says -1.
      expect(DownloadItem.fromQbit({'size': -1}).size, 0);
      final missing = DownloadItem.fromQbit({
        'hash': 'h',
        'name': 'n',
        'state': 'missingFiles',
      });
      expect(missing.problem, 'missingFiles');
      expect(missing.paused, isFalse);
      expect(DownloadItem.fromQbit({'state': 'stoppedUP'}).paused, isTrue);
    });
  });

  group('qBittorrent, signed in', () {
    test('signs in once, and its cookie goes with each ask', () async {
      final s = _Qbit();
      final c = _qbit(s);
      expect(await c.version(), '5.3.0');
      await c.load();
      expect(s.logins, 1);
      final login = s.sent('auth/login').single;
      expect(login.body, {'username': 'admin', 'password': 'pw'});
      expect(s.sent('sync/maindata').single.cookie, 'QBT_SID_8080=sid1');
    });

    test('a session that runs out is renewed, once', () async {
      final s = _Qbit();
      final c = _qbit(s);
      await c.load();
      s.expireAfter = 0;
      await expectLater(c.load(), completes);
      expect(s.logins, 2);
    });

    test('a wrong password says what to check, host header too', () async {
      final s = _Qbit()..login = '401';
      await expectLater(
        _qbit(s).version(),
        throwsA(
          predicate(
            (e) =>
                '$e'.contains('refused the sign-in') &&
                '$e'.contains('Host header validation'),
          ),
        ),
      );
      final old = _Qbit()..login = 'fails';
      await expectLater(
        _qbit(old).version(),
        throwsA(predicate((e) => '$e'.contains('refused the sign-in'))),
      );
    });

    test('refused once: not asked again (it would ban the device)', () async {
      final s = _Qbit()..login = '401';
      final c = _qbit(s);
      for (var i = 0; i < 4; i++) {
        await expectLater(
          c.load(),
          throwsA(predicate((e) => '$e'.contains('refused the sign-in'))),
        );
      }
      expect(s.logins, 1);
    });

    test('asked several things at once: one sign-in', () async {
      final s = _Qbit();
      final c = _qbit(s);
      await Future.wait([c.load(), c.categories(), c.version()]);
      expect(s.logins, 1);
    });

    test('its own cookie, not a proxy\'s', () async {
      final s = _Qbit()..proxyCookie = true;
      final c = _qbit(s);
      await c.load();
      expect(s.sent('sync/maindata').single.cookie, 'QBT_SID_8080=sid1');
    });

    test('4.x: a link it couldn\'t add says so', () async {
      final s = _Qbit()..legacy = true;
      await expectLater(
        _qbit(s).add('https://x/dup.torrent'),
        throwsA(predicate((e) => '$e'.contains('already there'))),
      );
    });

    test('no username: no sign-in, and a refusal says to add one', () async {
      final s = _Qbit();
      await expectLater(
        _qbit(s, user: '', pass: '').version(),
        throwsA(predicate((e) => '$e'.contains('wants a sign-in'))),
      );
      expect(s.logins, 0);
    });

    test('version: only qBittorrent passes', () async {
      final c = QbitClient(
        'http://x',
        '',
        '',
        dio: Dio()..httpClientAdapter = _Html(),
      );
      await expectLater(
        c.version(),
        throwsA(
          predicate((e) => '$e'.contains("doesn't answer as qBittorrent")),
        ),
      );
    });
  });

  group('qBittorrent, asked', () {
    test('pause and resume: stop and start, or 4.x pause and resume', () async {
      final s = _Qbit();
      final c = _qbit(s);
      final item = (await c.load()).items.first;
      await c.pause(item);
      await c.resume(item);
      expect(s.sent('torrents/stop').single.body, {'hashes': item.id});
      expect(s.sent('torrents/start').single.body, {'hashes': item.id});
      expect(s.sent('torrents/pause'), isEmpty);
      final old = _Qbit()..legacy = true;
      final o = _qbit(old);
      await o.pause(item);
      await o.resumeAll();
      expect(old.sent('torrents/pause').single.body, {'hashes': item.id});
      expect(old.sent('torrents/resume').single.body, {'hashes': 'all'});
    });

    test('remove, with or without the files', () async {
      final s = _Qbit();
      final c = _qbit(s);
      final item = (await c.load()).items.first;
      await c.remove(item, deleteFiles: true);
      await c.remove(item, deleteFiles: false);
      expect(
        [for (final a in s.sent('torrents/delete')) a.body],
        [
          {'hashes': item.id, 'deleteFiles': 'true'},
          {'hashes': item.id, 'deleteFiles': 'false'},
        ],
      );
    });

    test('add a link to a category; a refused one says why', () async {
      final s = _Qbit();
      final c = _qbit(s);
      await c.add('magnet:?xt=urn:btih:abc', category: 'radarr');
      await c.add('magnet:?xt=urn:btih:def');
      expect(
        [for (final a in s.sent('torrents/add')) a.body],
        [
          {'urls': 'magnet:?xt=urn:btih:abc', 'category': 'radarr'},
          {'urls': 'magnet:?xt=urn:btih:def'},
        ],
      );
      await expectLater(
        c.add('notalink'),
        throwsA(predicate((e) => '$e'.contains('already there'))),
      );
      expect(await c.categories(), ['lidarr', 'radarr', 'sonarr']);
    });
  });

  group('SABnzbd', () {
    test('its queue: jobs, priority, sizes, a paused one', () async {
      final s = _Sab();
      final got = await _sab(s).load();
      final by = {for (final i in got.items) i.name: i};
      expect(by[_sabMovie]!.state, DownloadState.downloading);
      expect(by[_sabMovie]!.priority, 'High');
      expect(by[_sabMovie]!.category, 'movies');
      expect(by[_sabShow]!.state, DownloadState.paused);
      // MB as SABnzbd counts them, 1024 x 1024.
      final mb = double.parse(
        ((s.queue['queue'] as Map)['slots'] as List).first['mb'] as String,
      );
      expect(by[_sabMovie]!.size, (mb * 1024 * 1024).round());
      expect(got.summary.paused, isFalse);
      expect(got.summary.speedLimit, 0);
      expect(got.summary.freeSpace, greaterThan(0));
      expect(s.sent('queue').single['apikey'], 'skey');
    });

    test('the whole queue paused holds every job', () async {
      final s = _Sab();
      (s.queue['queue'] as Map)['paused'] = true;
      final got = await _sab(s).load();
      expect(got.summary.paused, isTrue);
      expect(
        got.items.firstWhere((i) => i.name == _sabMovie).state,
        DownloadState.queued,
      );
    });

    test('a line speed set: "no limit" isn\'t read as a limit', () async {
      final s = _Sab()..lineSpeed = '100M';
      final q = s.queue['queue'] as Map;
      q['speedlimit_abs'] = '104857600';
      expect((await _sab(s).load()).summary.speedLimit, 0);
      q['speedlimit_abs'] = '5242880';
      expect((await _sab(s).load()).summary.speedLimit, 5242880);
      // Without a line speed, the limit reads as itself.
      final none = _Sab();
      (none.queue['queue'] as Map)['speedlimit_abs'] = '5242880';
      expect((await _sab(none).load()).summary.speedLimit, 5242880);
      expect(sabSpeed('100M'), 104857600);
      expect(sabSpeed('500K'), 512000);
      expect(sabSpeed('1G'), 1073741824);
      expect(sabSpeed(''), 0);
      expect(sabSpeed('2048'), 2048);
    });

    test('its time left, days and all', () {
      expect(sabDuration('0:12:34'), const Duration(minutes: 12, seconds: 34));
      expect(
        sabDuration('2:01:02:03'),
        const Duration(days: 2, hours: 1, minutes: 2, seconds: 3),
      );
      expect(sabDuration('0:00:00'), isNull);
      expect(sabDuration('soon'), isNull);
      expect(sabDuration(null), isNull);
    });

    test('its history: failed and why, and whether it can retry', () async {
      final got = await _sab(_Sab()).history();
      final h = got.single;
      expect(h.failed, isTrue);
      expect(h.problem, contains('URL Fetching failed'));
      expect(h.canRetry, isTrue);
      expect(h.category, 'audio');
    });

    test('a refusal in its answer, and an address that isn\'t it', () async {
      final c = SabClient(
        'http://sab',
        'k',
        dio: Dio()
          ..httpClientAdapter = _Html(
            jsonEncode({'status': false, 'error': 'not allowed'}),
          ),
      );
      await expectLater(
        c.add('https://x/a.nzb'),
        throwsA(predicate((e) => '$e' == 'SABnzbd: not allowed')),
      );
      final page = SabClient(
        'http://router',
        'k',
        dio: Dio()..httpClientAdapter = _Html('{"something": "else"}'),
      );
      await expectLater(
        page.version(),
        throwsA(predicate((e) => '$e'.contains("doesn't answer as SABnzbd"))),
      );
    });

    test('a wrong key, as 403 or as text', () async {
      await expectLater(
        _sab(_Sab(), key: 'wrong').version(),
        throwsA(predicate((e) => '$e' == 'SABnzbd rejected the API key.')),
      );
      final c = SabClient(
        'http://sab',
        'k',
        dio: Dio()..httpClientAdapter = _Html('API Key Incorrect'),
      );
      await expectLater(
        c.load(),
        throwsA(predicate((e) => '$e' == 'SABnzbd rejected the API key.')),
      );
    });

    test('what it\'s asked', () async {
      final s = _Sab();
      final c = _sab(s);
      final items = (await c.load()).items;
      final item = items.first;
      await c.pause(item);
      await c.resume(item);
      await c.remove(item, deleteFiles: true);
      await c.moveToTop(item);
      await c.setSpeedLimit(5 * 1024 * 1024);
      await c.setSpeedLimit(0);
      await c.pauseAll();
      await c.resumeAll();
      final h = (await c.history()).single;
      await c.retry(h);
      await c.removeHistory(h, deleteFiles: false);
      await c.add('https://indexer/getnzb/1.nzb', category: 'tv');
      final queue = s.sent('queue').where((q) => q['name'] != null).toList();
      expect(
        [for (final q in queue) (q['name'], q['value'], q['del_files'])],
        [
          ('pause', item.id, null),
          ('resume', item.id, null),
          ('delete', item.id, '1'),
        ],
      );
      expect(s.sent('switch').single['value'], item.id);
      expect(s.sent('switch').single['value2'], '0');
      expect([for (final q in s.sent('config')) q['value']], ['5M', '0']);
      expect(s.sent('pause'), hasLength(1));
      expect(s.sent('resume'), hasLength(1));
      expect(s.sent('retry').single['value'], h.id);
      final hd = s.sent('history').firstWhere((q) => q['name'] == 'delete');
      expect(hd['value'], h.id);
      expect(hd['del_files'], '0');
      final add = s.sent('addurl').single;
      expect(add['name'], 'https://indexer/getnzb/1.nzb');
      expect(add['cat'], 'tv');
      expect(await c.categories(), ['movies', 'tv', 'audio', 'software']);
    });
  });

  group('around them', () {
    test('a release name can wrap after its dots, and reads the same', () {
      final shown = downloadShownName('Show.S01E01.WEB');
      expect(shown, 'Show.\u200BS01E01.\u200BWEB');
      expect(shown.replaceAll('\u200B', ''), 'Show.S01E01.WEB');
    });

    test('a link goes to the client its look says', () {
      expect(
        downloadClientForLink('magnet:?xt=urn:btih:x'),
        DownloadClientKind.qbittorrent,
      );
      expect(
        downloadClientForLink('https://x/a.torrent'),
        DownloadClientKind.qbittorrent,
      );
      expect(
        downloadClientForLink('https://x/a.nzb?apikey=1'),
        DownloadClientKind.sabnzbd,
      );
      expect(
        downloadClientForLink('https://x/api?t=get&id=1'),
        DownloadClientKind.sabnzbd,
      );
      expect(downloadClientForLink('https://x/thing'), isNull);
    });

    test('the password and the key stay out of backups', () {
      expect(secretPrefKeys, containsAll(['qbitPassword', 'sabApiKey']));
      const p = Prefs(
        qbitUrl: 'http://q',
        qbitUsername: 'u',
        qbitPassword: 'pw',
        sabUrl: 'http://s',
        sabApiKey: 'k',
      );
      final back = Prefs.fromJson(p.toJson());
      expect(
        (
          back.qbitUrl,
          back.qbitUsername,
          back.qbitPassword,
          back.sabUrl,
          back.sabApiKey,
        ),
        ('http://q', 'u', 'pw', 'http://s', 'k'),
      );
    });

    test('a client alone puts Manage in the navigation', () {
      ProviderContainer only({QbitClient? q, SabClient? s}) =>
          ProviderContainer(
            overrides: [
              qbitClientProvider.overrideWithValue(q),
              sabClientProvider.overrideWithValue(s),
              prowlarrClientProvider.overrideWithValue(null),
              sonarrClientProvider.overrideWithValue(null),
              radarrClientProvider.overrideWithValue(null),
              lidarrClientProvider.overrideWithValue(null),
            ],
          );
      final a = only(q: _qbit(_Qbit()));
      final b = only(s: _sab(_Sab()));
      final none = only();
      for (final c in [a, b, none]) {
        addTearDown(c.dispose);
      }
      expect(a.read(arrConfiguredProvider), isTrue);
      expect(b.read(arrConfiguredProvider), isTrue);
      expect(none.read(arrConfiguredProvider), isFalse);
    });

    test('settings make the clients: blank qBittorrent sign-in is fine', () {
      ProviderContainer with_(Prefs p) => ProviderContainer(
        overrides: [preferencesProvider.overrideWith(() => _FakePrefs(p))],
      );
      // A username without its password, as a backup restores it: none.
      final restored = with_(
        const Prefs(qbitUrl: 'http://q', qbitUsername: 'admin'),
      );
      addTearDown(restored.dispose);
      restored.listen(preferencesProvider, (_, _) {});
      final c = with_(const Prefs(qbitUrl: 'http://q', sabUrl: 'http://s'));
      addTearDown(c.dispose);
      c.listen(preferencesProvider, (_, _) {});
      return Future.wait([
        c.read(preferencesProvider.future),
        restored.read(preferencesProvider.future),
      ]).then((_) {
        expect(restored.read(qbitClientProvider), isNull);
        expect(c.read(qbitClientProvider), isNotNull);
        // SABnzbd needs its key.
        expect(c.read(sabClientProvider), isNull);
        expect(
          [for (final x in c.read(downloadClientsProvider)) x.kind],
          [DownloadClientKind.qbittorrent],
        );
      });
    });
  });

  group('the page', () {
    testWidgets('both clients: each one\'s list, speeds and states', (t) async {
      await _open(
        t,
        _app(qbit: _Qbit(), sab: _Sab(), home: const DownloadClientsScreen()),
      );
      expect(find.text('qBittorrent'), findsOneWidget);
      expect(find.text('SABnzbd'), findsOneWidget);
      for (final n in [_album, _movie, _magnet, _sabMovie, _sabShow]) {
        expect(_name(n), findsOneWidget);
      }
      expect(
        find.descendant(of: _row(_album), matching: find.text('Seeding')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _row(_movie), matching: find.text('Stalled')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _row(_sabShow), matching: find.text('Paused')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _row(_sabMovie), matching: find.text('High')),
        findsOneWidget,
      );
      // qBittorrent's speeds both ways, its free space.
      expect(
        find.textContaining(RegExp(r'^↓ .+/s · ↑ .+/s · .+ free$')),
        findsOneWidget,
      );
      // SABnzbd has Move to Top, for what isn't paused; qBittorrent doesn't.
      expect(
        find.descendant(
          of: _row(_sabMovie),
          matching: find.byTooltip('Move to Top'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _row(_sabShow),
          matching: find.byTooltip('Move to Top'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: _row(_movie),
          matching: find.byTooltip('Move to Top'),
        ),
        findsNothing,
      );
    });

    testWidgets('filters: paused, finished', (t) async {
      await _open(
        t,
        _app(qbit: _Qbit(), sab: _Sab(), home: const DownloadClientsScreen()),
      );
      await t.tap(find.widgetWithText(ChoiceChip, 'Paused'));
      await _settle(t);
      expect(_name(_magnet), findsOneWidget);
      expect(_name(_sabShow), findsOneWidget);
      expect(_name(_album), findsNothing);
      expect(_name(_movie), findsNothing);
      await t.tap(find.widgetWithText(ChoiceChip, 'Finished'));
      await _settle(t);
      expect(_name(_album), findsOneWidget);
      // SABnzbd has nothing finished in its queue.
      expect(find.text('Nothing matches'), findsOneWidget);
    });

    testWidgets('pause shows at once, before qBittorrent says so', (t) async {
      final q = _Qbit();
      await _open(t, _app(qbit: q, home: const DownloadClientsScreen()));
      await t.tap(
        find.descendant(of: _row(_movie), matching: find.byTooltip('Pause')),
      );
      await _settle(t);
      expect(q.sent('torrents/stop').single.body, {
        'hashes': 'd5c4db4321eb911238ac748fe6028bfeceb74c74',
      });
      // The answer still says stalled; the row says paused, with Resume.
      expect(
        find.descendant(of: _row(_movie), matching: find.text('Paused')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _row(_movie), matching: find.byTooltip('Resume')),
        findsOneWidget,
      );
      // Asked again soon after, to catch qBittorrent's own answer.
      final asked = q.sent('sync/maindata').length;
      await t.pump(const Duration(seconds: 2));
      await _settle(t);
      expect(q.sent('sync/maindata').length, greaterThan(asked));
      // qBittorrent never says so: after a while, its word stands.
      await t.pump(const Duration(seconds: 9));
      await _settle(t);
      expect(
        find.descendant(of: _row(_movie), matching: find.text('Stalled')),
        findsOneWidget,
      );
    });

    testWidgets('resumed: the client\'s own word once it agrees', (t) async {
      final q = _Qbit();
      await _open(t, _app(qbit: q, home: const DownloadClientsScreen()));
      await t.tap(
        find.descendant(of: _row(_magnet), matching: find.byTooltip('Resume')),
      );
      await _settle(t);
      expect(
        find.descendant(of: _row(_magnet), matching: find.text('Queued')),
        findsOneWidget,
      );
      final torrents = q.maindata['torrents'] as Map;
      final key = torrents.keys.firstWhere(
        (k) => (torrents[k] as Map)['name'] == _magnet,
      );
      torrents[key] = {...(torrents[key] as Map), 'state': 'metaDL'};
      await t.pump(const Duration(seconds: 2));
      await _settle(t);
      expect(
        find.descendant(of: _row(_magnet), matching: find.text('Fetching')),
        findsOneWidget,
      );
    });

    testWidgets('an action asks again two seconds on', (t) async {
      final q = _Qbit();
      await _open(t, _app(qbit: q, home: const DownloadClientsScreen()));
      // Just past a regular ask (every 3 s), so the next is a while off.
      await t.pump(const Duration(milliseconds: 2700));
      await t.tap(
        find.descendant(of: _row(_movie), matching: find.byTooltip('Pause')),
      );
      await _settle(t);
      final n = q.sent('sync/maindata').length;
      await t.pump(const Duration(milliseconds: 2100));
      expect(q.sent('sync/maindata').length, n + 1);
    });

    testWidgets('qBittorrent all stopped: Resume All', (t) async {
      final q = _Qbit();
      final torrents = q.maindata['torrents'] as Map;
      // Two stopped part way, one finished and stopped at its ratio.
      final keys = torrents.keys.toList();
      for (final k in keys) {
        torrents[k] = {
          ...(torrents[k] as Map),
          'state': (torrents[k] as Map)['name'] == _album
              ? 'stoppedUP'
              : 'stoppedDL',
        };
      }
      await _open(t, _app(qbit: q, home: const DownloadClientsScreen()));
      await t.tap(find.byTooltip('Resume All'));
      await _settle(t);
      // The finished one isn't started seeding again.
      final hashes =
          ((q.sent('torrents/start').single.body! as Map)['hashes'] as String)
              .split('|');
      final albumKey = keys.firstWhere(
        (k) => (torrents[k] as Map)['name'] == _album,
      );
      expect(hashes, hasLength(2));
      expect(hashes, isNot(contains(albumKey)));
    });

    testWidgets('everything finished and stopped isn\'t "paused"', (t) async {
      final q = _Qbit();
      final torrents = q.maindata['torrents'] as Map;
      for (final k in torrents.keys.toList()) {
        torrents[k] = {...(torrents[k] as Map), 'state': 'stoppedUP'};
      }
      await _open(t, _app(qbit: q, home: const DownloadClientsScreen()));
      expect(find.byTooltip('Resume All'), findsNothing);
      expect(find.byTooltip('Pause All'), findsOneWidget);
    });

    testWidgets('the lists wait while History shows', (t) async {
      final q = _Qbit();
      await _open(t, _app(qbit: q, sab: _Sab(), home: const DownloadClientsScreen()));
      await t.tap(find.text('History'));
      await _settle(t);
      final n = q.sent('sync/maindata').length;
      await t.pump(const Duration(seconds: 7));
      await _settle(t);
      expect(q.sent('sync/maindata').length, n);
    });

    testWidgets('a finished job\'s files stay: no box for them', (t) async {
      final s = _Sab();
      await _open(t, _app(sab: s, home: const DownloadClientsScreen()));
      await t.tap(find.text('History'));
      await _settle(t);
      // The rig's one job failed: its files can go.
      await t.tap(find.byTooltip('Remove'));
      await _settle(t);
      expect(find.text('Also Delete Its Files'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await _settle(t);
      // The same job finished: SABnzbd wouldn't delete its files.
      final slot = ((s.history['history'] as Map)['slots'] as List).single as Map;
      slot['status'] = 'Completed';
      slot['fail_message'] = '';
      await t.pump(const Duration(seconds: 10));
      await _settle(t);
      await t.tap(find.byTooltip('Remove'));
      await _settle(t);
      expect(find.text('Remove ${slot['name']}?'), findsOneWidget);
      expect(find.text('Also Delete Its Files'), findsNothing);
    });

    testWidgets('remove asks first, and can take the files', (t) async {
      final q = _Qbit();
      await _open(t, _app(qbit: q, home: const DownloadClientsScreen()));
      await t.tap(
        find.descendant(of: _row(_movie), matching: find.byTooltip('Remove')),
      );
      await _settle(t);
      expect(find.text('Remove $_movie?'), findsOneWidget);
      await t.tap(find.text('Also Delete Its Files'));
      await _settle(t);
      await t.tap(find.widgetWithText(FilledButton, 'Remove'));
      await _settle(t);
      expect(q.sent('torrents/delete').single.body, {
        'hashes': 'd5c4db4321eb911238ac748fe6028bfeceb74c74',
        'deleteFiles': 'true',
      });
      // Cancel sends nothing.
      await t.tap(
        find.descendant(of: _row(_album), matching: find.byTooltip('Remove')),
      );
      await _settle(t);
      await t.tap(find.text('Cancel'));
      await _settle(t);
      expect(q.sent('torrents/delete'), hasLength(1));
    });

    testWidgets('a client as a whole: pause all, speed limits', (t) async {
      final q = _Qbit();
      final s = _Sab();
      await _open(
        t,
        _app(qbit: q, sab: s, home: const DownloadClientsScreen()),
      );
      // Not everything is stopped: Pause All.
      await t.tap(find.byTooltip('Pause All').first);
      await _settle(t);
      expect(q.sent('torrents/stop').single.body, {'hashes': 'all'});
      await t.tap(find.byTooltip('Pause All').last);
      await _settle(t);
      expect(s.sent('pause'), hasLength(1));
      await t.tap(find.byTooltip('Alternative Speed Limits'));
      await _settle(t);
      expect(q.sent('transfer/toggleSpeedLimitsMode'), hasLength(1));
      expect(find.text('Alternative speed limits on'), findsOneWidget);
      await t.tap(find.byTooltip('Speed Limit'));
      await _settle(t);
      await t.tap(find.text('5 MB/s').last);
      await _settle(t);
      expect(s.sent('config').single['value'], '5M');
    });

    testWidgets('SABnzbd paused: Resume All, and its jobs held', (t) async {
      final s = _Sab();
      (s.queue['queue'] as Map)['paused'] = true;
      await _open(t, _app(sab: s, home: const DownloadClientsScreen()));
      await t.tap(find.byTooltip('Resume All'));
      await _settle(t);
      expect(s.sent('resume'), hasLength(1));
      expect(
        find.descendant(of: _row(_sabMovie), matching: find.text('Queued')),
        findsOneWidget,
      );
    });

    testWidgets('Move to Top', (t) async {
      final s = _Sab();
      await _open(t, _app(sab: s, home: const DownloadClientsScreen()));
      await t.tap(
        find.descendant(
          of: _row(_sabMovie),
          matching: find.byTooltip('Move to Top'),
        ),
      );
      await _settle(t);
      expect(s.sent('switch').single['value2'], '0');
    });

    testWidgets('History: why it failed, and Retry', (t) async {
      final s = _Sab();
      await _open(
        t,
        _app(qbit: _Qbit(), sab: s, home: const DownloadClientsScreen()),
      );
      await t.tap(find.text('History'));
      await _settle(t);
      expect(find.textContaining('URL Fetching failed'), findsOneWidget);
      await t.tap(find.byTooltip('Retry'));
      await _settle(t);
      expect(s.sent('retry'), hasLength(1));
      expect(find.textContaining('back to the queue'), findsOneWidget);
    });

    testWidgets('pressing a row: its actions by name', (t) async {
      final s = _Sab();
      await _open(t, _app(sab: s, home: const DownloadClientsScreen()));
      await t.tap(_name(_sabMovie));
      await _settle(t);
      // The sheet (a phone or a TV) names what its buttons do.
      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('Move to Top'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
      await t.tap(find.text('Move to Top'));
      await _settle(t);
      expect(s.sent('switch'), hasLength(1));
      // A paused one offers Resume, and no Move to Top.
      await t.tap(_name(_sabShow));
      await _settle(t);
      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('Move to Top'), findsNothing);
      await t.tap(find.text('Resume'));
      await _settle(t);
      expect(s.sent('queue').where((q) => q['name'] == 'resume'), hasLength(1));
    });

    testWidgets('pressing a client: all of it, and its speed', (t) async {
      final q = _Qbit();
      final s = _Sab();
      await _open(t, _app(qbit: q, sab: s, home: const DownloadClientsScreen()));
      await t.tap(find.text('qBittorrent'));
      await _settle(t);
      expect(find.text('Pause All'), findsOneWidget);
      await t.tap(find.text('Alternative Speed Limits'));
      await _settle(t);
      expect(q.sent('transfer/toggleSpeedLimitsMode'), hasLength(1));
      await t.tap(find.text('SABnzbd'));
      await _settle(t);
      expect(find.text('No Limit'), findsOneWidget);
      await t.tap(find.text('Speed limit 25 MB/s'));
      await _settle(t);
      expect(s.sent('config').single['value'], '25M');
    });

    testWidgets('pressing a finished job: Retry and Remove', (t) async {
      final s = _Sab();
      await _open(t, _app(sab: s, home: const DownloadClientsScreen()));
      await t.tap(find.text('History'));
      await _settle(t);
      await t.tap(_name('http://172.17.0.1:19696/missing.nzb'));
      await _settle(t);
      await t.tap(find.text('Retry'));
      await _settle(t);
      expect(s.sent('retry'), hasLength(1));
    });

    testWidgets('History is asked again now and then', (t) async {
      final s = _Sab();
      await _open(t, _app(sab: s, home: const DownloadClientsScreen()));
      await t.tap(find.text('History'));
      await _settle(t);
      final n = s.sent('history').length;
      await t.pump(const Duration(seconds: 10));
      await _settle(t);
      expect(s.sent('history').length, greaterThan(n));
    });

    testWidgets('no History without SABnzbd', (t) async {
      await _open(t, _app(qbit: _Qbit(), home: const DownloadClientsScreen()));
      expect(find.text('History'), findsNothing);
    });

    testWidgets('Add: a magnet to qBittorrent, an NZB to SABnzbd', (t) async {
      final q = _Qbit();
      final s = _Sab();
      await _open(
        t,
        _app(qbit: q, sab: s, home: const DownloadClientsScreen()),
      );
      await t.tap(find.byTooltip('Add Download'));
      await _settle(t);
      await t.enterText(find.byType(TextField), 'https://indexer/getnzb/9.nzb');
      await _settle(t);
      // The client follows the link.
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('SABnzbd'),
        ),
        findsOneWidget,
      );
      await t.tap(find.text('None'));
      await _settle(t);
      await t.tap(find.text('tv').last);
      await _settle(t);
      await t.tap(find.widgetWithText(FilledButton, 'Add'));
      await _settle(t);
      expect(s.sent('addurl').single['cat'], 'tv');
      expect(find.byType(AlertDialog), findsNothing);
      await t.tap(find.byTooltip('Add Download'));
      await _settle(t);
      await t.enterText(find.byType(TextField), 'magnet:?xt=urn:btih:abc');
      await _settle(t);
      await t.tap(find.widgetWithText(FilledButton, 'Add'));
      await _settle(t);
      expect(q.sent('torrents/add').single.body, {
        'urls': 'magnet:?xt=urn:btih:abc',
      });
    });

    testWidgets('a refused add keeps the dialog, with why', (t) async {
      final q = _Qbit();
      await _open(t, _app(qbit: q, home: const DownloadClientsScreen()));
      await t.tap(find.byTooltip('Add Download'));
      await _settle(t);
      await t.enterText(find.byType(TextField), 'https://x/dup.torrent');
      await _settle(t);
      await t.tap(find.widgetWithText(FilledButton, 'Add'));
      await _settle(t);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('already there'), findsOneWidget);
    });

    testWidgets('asked again every few seconds while it shows', (t) async {
      final q = _Qbit();
      await _open(t, _app(qbit: q, home: const DownloadClientsScreen()));
      final first = q.sent('sync/maindata').length;
      await t.pump(const Duration(seconds: 3));
      await _settle(t);
      expect(q.sent('sync/maindata').length, greaterThan(first));
      // A new answer moves the row.
      final torrents = q.maindata['torrents'] as Map;
      torrents['d5c4db4321eb911238ac748fe6028bfeceb74c74'] = {
        ...(torrents['d5c4db4321eb911238ac748fe6028bfeceb74c74'] as Map),
        'state': 'downloading',
        'dlspeed': 2 * 1024 * 1024,
        'progress': 0.5,
        'amount_left': 2500000,
        'eta': 125,
      };
      await t.pump(const Duration(seconds: 3));
      await _settle(t);
      expect(
        find.descendant(of: _row(_movie), matching: find.text('Downloading')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _row(_movie),
          matching: find.textContaining('↓ 2 MB/s'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _row(_movie),
          matching: find.textContaining('2m left'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a client that can\'t be reached says so, the other shows', (
      t,
    ) async {
      await _open(
        t,
        _app(
          qbit: _Qbit()..login = '401',
          sab: _Sab(),
          home: const DownloadClientsScreen(),
        ),
      );
      expect(find.textContaining('refused the sign-in'), findsOneWidget);
      expect(_name(_sabMovie), findsOneWidget);
    });

    testWidgets('nothing connected: the way to Settings', (t) async {
      await _open(t, _app(home: const DownloadClientsScreen()));
      expect(find.text('No download client connected'), findsOneWidget);
    });
  });

  group('in Manage', () {
    testWidgets('only a client: Manage opens on it', (t) async {
      await _open(t, _app(sab: _Sab(), home: const ArrScreen()));
      expect(find.byType(DownloadClientsScreen), findsOneWidget);
      expect(_name(_sabMovie), findsOneWidget);
    });

    testWidgets('Settings: a refused qBittorrent sign-in is asked once, '
        'through the app\'s own client', (t) async {
      final server = _Qbit()..login = '401';
      var tested = 0;
      final container = ProviderContainer(
        overrides: [
          preferencesProvider.overrideWith(
            () => _FakePrefs(
              const Prefs(
                qbitUrl: 'http://qbit:8080',
                qbitUsername: 'admin',
                qbitPassword: 'wrong',
              ),
            ),
          ),
          qbitClientProvider.overrideWithValue(
            _qbit(server, pass: 'wrong'),
          ),
          connTesterProvider.overrideWithValue((_, _, _, _) async {
            tested++;
            return '5.1.0';
          }),
        ],
      );
      addTearDown(container.dispose);
      t.view.physicalSize = const Size(500, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(const Color(0xFF8AB4F8)),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ArrSettingsScreen(),
          ),
        ),
      );
      await _settle(t);
      expect(find.text("Can't connect"), findsOneWidget);
      // Long enough for any retry to have come and gone.
      for (var i = 0; i < 30; i++) {
        await t.pump(const Duration(seconds: 1));
      }
      expect(server.logins, 1);
      expect(tested, 0);
      // Its page shares the same answer: no second sign-in.
      await t.tap(find.text('qBittorrent'));
      await _settle(t);
      expect(server.logins, 1);
    });

    testWidgets('Settings: qBittorrent and SABnzbd, saved on their own', (
      t,
    ) async {
      final tried = <(ConnApp, String, String)>[];
      final container = ProviderContainer(
        overrides: [
          preferencesProvider.overrideWith(() => _FakePrefs(const Prefs())),
          connTesterProvider.overrideWithValue((app, url, user, key) async {
            tried.add((app, user, key));
            return '5.1.0';
          }),
          // The rows ask qBittorrent through the app's own client.
          qbitClientProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);
      t.view.physicalSize = const Size(500, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(const Color(0xFF8AB4F8)),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ArrSettingsScreen(),
          ),
        ),
      );
      await _settle(t);
      Future<void> add(String app) async {
        await t.tap(find.text('Add Connection'));
        await _settle(t);
        await t.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text(app),
          ),
        );
        await _settle(t);
      }

      final fields = find.byType(TextField);
      // qBittorrent with no sign-in: an address is enough.
      await add('qBittorrent');
      expect(find.text('http://192.168.1.10:8080'), findsOneWidget);
      expect(fields, findsNWidgets(3));
      await t.enterText(fields.at(0), '10.0.0.5:8080');
      await t.tap(find.text('Save & Test'));
      await _settle(t);
      var p = container.read(preferencesProvider).requireValue;
      expect(p.qbitUrl, 'http://10.0.0.5:8080');
      expect(p.qbitUsername, isEmpty);
      expect(tried.first, (ConnApp.qbittorrent, '', ''));
      await t.pageBack();
      await _settle(t);
      // SABnzbd without its key isn't saved. Its address starts on the
      // same computer, at SABnzbd's port.
      await add('SABnzbd');
      expect(
        t.widget<TextField>(fields.at(0)).controller!.text,
        'http://10.0.0.5:8085',
      );
      await t.tap(find.text('Save & Test'));
      await _settle(t);
      expect(
        find.text('Enter the server address and the API key'),
        findsOneWidget,
      );
      expect(container.read(preferencesProvider).requireValue.sabUrl, isEmpty);
      await t.enterText(fields.at(1), ' skey ');
      await t.tap(find.text('Save & Test'));
      await _settle(t);
      p = container.read(preferencesProvider).requireValue;
      expect(p.sabUrl, 'http://10.0.0.5:8085');
      expect(p.sabApiKey, 'skey');
      await t.pageBack();
      await _settle(t);
      // Both under Download Clients.
      expect(find.text('Download Clients'), findsOneWidget);
      expect(find.text('10.0.0.5:8080 · 5.1.0'), findsOneWidget);
      expect(find.text('10.0.0.5:8085 · 5.1.0'), findsOneWidget);
      // A password keeps its spaces.
      await t.tap(find.text('qBittorrent'));
      await _settle(t);
      await t.enterText(fields.at(1), 'admin');
      await t.enterText(fields.at(2), ' pass word ');
      await t.tap(find.text('Save & Test'));
      await _settle(t);
      p = container.read(preferencesProvider).requireValue;
      expect((p.qbitUsername, p.qbitPassword), ('admin', ' pass word '));
      // Add Connection knows they're there: they open, not again.
      await t.pageBack();
      await _settle(t);
      await add('SABnzbd');
      expect(find.text('Disconnect'), findsOneWidget);
      expect(
        t.widget<TextField>(fields.at(1)).controller!.text,
        'skey',
      );
    });
  });
}

/// A server that isn't the client asked for: a web page, or a bare text.
class _Html implements HttpClientAdapter {
  final String body;
  _Html([this.body = '<html>router login</html>']);

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async => this.body.startsWith('{')
      ? _json(jsonDecode(this.body))
      : _text(this.body);

  @override
  void close({bool force = false}) {}
}
