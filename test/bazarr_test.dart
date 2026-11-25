import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fathom/api/arr_client.dart';
import 'package:fathom/api/bazarr_client.dart';
import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/models/session.dart';
import 'package:fathom/screens/arr_screen.dart';
import 'package:fathom/screens/arr_settings_screen.dart';
import 'package:fathom/screens/bazarr_screen.dart';
import 'package:fathom/services/settings_backup.dart';
import 'package:fathom/state/arr_providers.dart';
import 'package:fathom/state/download_providers.dart';
import 'package:fathom/state/preferences.dart';
import 'package:fathom/state/session_controller.dart';
import 'package:fathom/theme/app_theme.dart';
import 'package:fathom/widgets/app_spinner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Bazarr in the Manage section: what's missing subtitles, a search or a
// manual one, what it did, and its providers. The answers are Bazarr
// 1.6.2's own, saved from the rig (The Matrix downloaded by search and by
// hand from yifysubtitles; tvsubtitles failing).

Object? _fixture(String name) =>
    jsonDecode(File('test/fixtures/arr/$name.json').readAsStringSync());

typedef _Asked = ({
  String method,
  String path,
  Map<String, String> query,
  Object? form,
});

class _Bazarr implements HttpClientAdapter {
  final List<_Asked> asked = [];

  /// Answers of the test's own, by path, over Bazarr's.
  final Map<String, Object?> answers;
  _Bazarr([this.answers = const {}]);

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    final path = o.uri.path.replaceFirst(RegExp(r'^.*/api/'), '');
    asked.add((
      method: o.method,
      path: path,
      query: o.uri.queryParameters,
      form: o.data,
    ));
    if (o.headers['X-API-KEY'] != 'bkey') {
      return ResponseBody.fromString('Unauthorized', 401);
    }
    final data = o.method == 'GET' && answers.containsKey(path)
        ? answers[path]
        : switch ((o.method, path)) {
            ('GET', 'system/status') => _fixture('bazarr_status'),
            ('GET', 'system/health') => _fixture('bazarr_health'),
            ('GET', 'episodes/wanted') => _fixture('bazarr_episodes_wanted'),
            ('GET', 'movies/wanted') => _fixture('bazarr_movies_wanted'),
            ('GET', 'movies/history') => _fixture('bazarr_movies_history'),
            ('GET', 'episodes/history') => {'data': [], 'total': 0},
            ('GET', 'providers') => _fixture('bazarr_providers'),
            ('GET', 'providers/movies') => _fixture('bazarr_movies_manual'),
            ('GET', 'providers/episodes') => {'data': [], 'total': 0},
            _ => null,
          };
    return data == null
        ? ResponseBody.fromString('', 204)
        : ResponseBody.fromString(
            jsonEncode(data),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
  }

  @override
  void close({bool force = false}) {}

  List<_Asked> sent(String method, String path) => [
    for (final a in asked)
      if (a.method == method && a.path == path) a,
  ];
}

BazarrClient _client(_Bazarr s) => BazarrClient(
  'http://bazarr:6767',
  'bkey',
  dio: Dio()..httpClientAdapter = s,
);

/// Bazarr whose manual search fails while [fail] says so.
class _Flaky extends _Bazarr {
  final bool Function() fail;
  _Flaky(this.fail);

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) {
    if (o.uri.path.endsWith('providers/movies') &&
        o.method == 'GET' &&
        fail()) {
      return Future.value(ResponseBody.fromString('Bad Gateway', 502));
    }
    return super.fetch(o, body, cancel);
  }
}

/// Any other app: nothing in it.
class _Empty implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async => ResponseBody.fromString(
    o.uri.path.endsWith('system/status')
        ? '{"appName": "Radarr", "version": "6"}'
        : '[]',
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

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

Widget _app(_Bazarr? b, {Widget home = const BazarrScreen()}) => ProviderScope(
  overrides: [
    bazarrClientProvider.overrideWithValue(b == null ? null : _client(b)),
    sonarrClientProvider.overrideWithValue(null),
    radarrClientProvider.overrideWithValue(null),
    lidarrClientProvider.overrideWithValue(null),
    prowlarrClientProvider.overrideWithValue(null),
    qbitClientProvider.overrideWithValue(null),
    sabClientProvider.overrideWithValue(null),
    preferencesProvider.overrideWith(() => _FakePrefs(const Prefs())),
    sessionControllerProvider.overrideWith(_SignedOut.new),
  ],
  child: MaterialApp(
    theme: AppTheme.dark(const Color(0xFF8AB4F8)),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  ),
);

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _open(WidgetTester t, Widget app) async {
  t.view.physicalSize = const Size(1000, 2000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(app);
  await _settle(t);
}

void main() {
  group('Bazarr\'s answers, read', () {
    test('wanted: episodes and movies, the languages missing', () async {
      final w = await _client(_Bazarr()).wanted();
      final eps = (_fixture('bazarr_episodes_wanted')! as Map)['data'] as List;
      final movies = (_fixture('bazarr_movies_wanted')! as Map)['data'] as List;
      expect(w.items, hasLength(eps.length + movies.length));
      final first = w.items.first;
      final e = eps.first as Map;
      expect(first.isEpisode, isTrue);
      expect(first.title, e['seriesTitle']);
      expect(first.seriesId, e['sonarrSeriesId']);
      expect(first.episodeId, e['sonarrEpisodeId']);
      expect(first.missing.single.code, 'en');
      final m = w.items.firstWhere((x) => !x.isEpisode);
      expect(m.movieId, (movies.first as Map)['radarrId']);
      expect(bazarrEpisodeCode('1x1'), 'S01E01');
      expect(bazarrEpisodeCode('12x105'), 'S12E105');
      expect(bazarrEpisodeCode('special'), isNull);
    });

    test('history: what it did, by whom, how well, when', () async {
      final page = await _client(_Bazarr()).history();
      final h = page.items;
      expect(page.total, 2);
      expect(
        [for (final x in h) x.action],
        [BazarrAction.downloaded, BazarrAction.manual],
      );
      expect(h.first.provider, 'yifysubtitles');
      expect(h.first.score, '90.56%');
      expect(h.first.time, DateTime(2026, 11, 23, 7, 34));
      // The newest first.
      expect(h.first.time!.isAfter(h.last.time!), isTrue);
      expect(bazarrTime('1/2/26 3:04:05'), DateTime(2026, 1, 2, 3, 4, 5));
      expect(bazarrTime('yesterday'), isNull);
      // A day first (23/11/26) is no date, not a wrong one.
      expect(bazarrTime('23/11/26 07:34:00'), isNull);
      expect(BazarrAction.of(7), BazarrAction.extracted);
      expect(BazarrAction.of(99), BazarrAction.other);
    });

    test('providers, a failing one with when it\'s tried again', () async {
      final p = await _client(_Bazarr()).providers();
      final bad = p.firstWhere((x) => !x.good);
      expect(bad.name, 'tvsubtitles');
      expect(bad.retry, startsWith('in '));
      expect(p.firstWhere((x) => x.good).retry, isNull);
    });

    test('a manual search, the best first', () async {
      final r = await _client(
        _Bazarr(),
      ).manualSearch(const BazarrWanted(movieId: 18, title: 'The Matrix'));
      expect(r, isNotEmpty);
      for (var i = 1; i < r.length; i++) {
        expect(r[i - 1].score, greaterThanOrEqualTo(r[i].score));
      }
      expect(r.first.subtitle, isNotEmpty);
      expect(r.first.releaseInfo, isNotEmpty);
    });

    // Both answers are a real Bazarr 1.6's, for Breaking Bad S01E01 off the
    // rig's Sonarr: Gestdown downloaded it, and a manual search for it.
    test('an episode, as a real Bazarr answers for one', () async {
      final b = _Bazarr({
        'episodes/history': _fixture('bazarr_episodes_history'),
        'providers/episodes': _fixture('bazarr_episodes_manual'),
      });
      final h = (await _client(b).history(movies: false)).items.single;
      expect(h.action, BazarrAction.downloaded);
      expect(h.title, 'Breaking Bad');
      expect(h.episodeCode, 'S01E01');
      expect(h.episodeTitle, 'Pilot');
      expect(h.provider, 'gestdown');
      expect(h.score, '93.89%');
      expect(h.language?.code, 'en');
      expect(h.seriesId, 1);
      expect(h.time, DateTime(2026, 11, 23, 13, 8, 2));

      const ep = BazarrWanted(
        seriesId: 1,
        episodeId: 19,
        title: 'Breaking Bad',
      );
      final r = await _client(b).manualSearch(ep);
      expect(r, hasLength(6));
      expect(b.asked.last.query, {'episodeid': '19'});
      expect(r.first.provider, 'gestdown');
      expect(r.first.score, 93);
      expect(r.last.score, 86);
      expect(r.first.language, 'en');
      expect(r.first.hi, isFalse);
      expect(r.first.subtitle, isNotEmpty);
    });

    test('health: what it\'s about and what\'s wrong', () async {
      final h = await _client(_Bazarr()).health();
      expect(h.single.message, startsWith('/tv: '));
      expect(h.single.isProblem, isTrue);
    });

    test('another app at the address isn\'t taken for Bazarr', () async {
      final radarr = _Bazarr({
        'system/status': {'appName': 'Radarr', 'version': '6.0.4'},
      });
      await expectLater(
        _client(radarr).version(),
        throwsA(predicate((e) => '$e'.contains("doesn't answer as Bazarr"))),
      );
    });

    test('a manual search out of order comes back best first', () async {
      final data =
          ((_fixture('bazarr_movies_manual')! as Map)['data'] as List).reversed;
      final r = await _client(
        _Bazarr({
          'providers/movies': {'data': data.toList()},
        }),
      ).manualSearch(const BazarrWanted(movieId: 18, title: 'The Matrix'));
      for (var i = 1; i < r.length; i++) {
        expect(r[i - 1].score, greaterThanOrEqualTo(r[i].score));
      }
    });

    test('a wrong key, and another app at the address', () async {
      await expectLater(
        BazarrClient(
          'http://b',
          'nope',
          dio: Dio()..httpClientAdapter = _Bazarr(),
        ).version(),
        throwsA(predicate((e) => '$e' == 'Bazarr rejected the API key.')),
      );
      expect(await _client(_Bazarr()).version(), '1.6.2');
    });
  });

  group('what Bazarr is asked', () {
    test('search: per language, as Bazarr reads True and False', () async {
      final s = _Bazarr();
      final c = _client(s);
      await c.search(
        const BazarrWanted(seriesId: 5, episodeId: 1160, title: 'The Office'),
        const BazarrLanguage(name: 'English', code: 'en', hi: true),
      );
      await c.search(
        const BazarrWanted(movieId: 18, title: 'The Matrix'),
        const BazarrLanguage(name: 'English', code: 'en'),
      );
      expect(s.sent('PATCH', 'episodes/subtitles').single.query, {
        'seriesid': '5',
        'episodeid': '1160',
        'language': 'en',
        'forced': 'False',
        'hi': 'True',
      });
      expect(s.sent('PATCH', 'movies/subtitles').single.query, {
        'radarrid': '18',
        'language': 'en',
        'forced': 'False',
        'hi': 'False',
      });
    });

    test('download what a manual search found, as a form', () async {
      final s = _Bazarr();
      final c = _client(s);
      const w = BazarrWanted(movieId: 18, title: 'The Matrix');
      final r = (await c.manualSearch(w)).first;
      await c.download(w, r);
      final a = s.sent('POST', 'providers/movies').single;
      expect(a.query, {'radarrid': '18'});
      expect(a.form, {
        'hi': r.hi ? 'True' : 'False',
        'forced': 'False',
        'original_format': 'False',
        'provider': r.provider,
        'subtitle': r.subtitle,
      });
    });

    test('history: those without a time go last, in any order', () async {
      final undated = {'action': 1, 'title': 'Undated', 'parsed_timestamp': ''};
      final movies = Map<String, dynamic>.from(
        _fixture('bazarr_movies_history')! as Map,
      );
      final data = [undated, ...(movies['data'] as List), undated];
      final h = await _client(
        _Bazarr({
          'movies/history': {'data': data, 'total': data.length},
        }),
      ).history();
      expect([for (final x in h.items) x.title].last, 'Undated');
      expect(h.items[1].title, 'The Matrix');
      expect(h.items.first.time!.isAfter(h.items[1].time!), isTrue);
    });

    test('Search All: Bazarr\'s two tasks; providers reset', () async {
      final s = _Bazarr();
      final c = _client(s);
      await c.searchAllWanted();
      await c.resetProviders();
      expect(
        [for (final a in s.sent('POST', 'system/tasks')) a.query['taskid']],
        [
          'wanted_search_missing_subtitles_series',
          'wanted_search_missing_subtitles_movies',
        ],
      );
      expect(s.sent('POST', 'providers').single.query, {'action': 'reset'});
    });

    test('every call is one Bazarr serves', () async {
      final routes = {
        for (final line in File(
          'test/fixtures/bazarr_routes.txt',
        ).readAsLinesSync())
          if (line.isNotEmpty && !line.startsWith('#')) line,
      };
      final s = _Bazarr();
      final c = _client(s);
      const ep = BazarrWanted(seriesId: 1, episodeId: 2, title: 't');
      const mv = BazarrWanted(movieId: 3, title: 't');
      const en = BazarrLanguage(name: 'English', code: 'en');
      await c.version();
      await c.health();
      await c.wanted();
      await c.history();
      await c.providers();
      await c.resetProviders();
      await c.search(ep, en);
      await c.search(mv, en);
      await c.manualSearch(ep);
      final r = (await c.manualSearch(mv)).first;
      await c.download(ep, r);
      await c.download(mv, r);
      await c.searchAllWanted();
      for (final a in s.asked) {
        expect(routes, contains('${a.method} /api/${a.path}'));
      }
    });

    test('the key stays out of backups', () {
      expect(secretPrefKeys, contains('bazarrApiKey'));
    });
  });

  group('the Subtitles page', () {
    testWidgets('Wanted: each, what\'s missing, Search', (t) async {
      final s = _Bazarr();
      await _open(t, _app(s));
      expect(find.text('The Office (US) S01E01 · Pilot'), findsOneWidget);
      expect(find.text('The Matrix'), findsNothing);
      final total =
          ((_fixture('bazarr_episodes_wanted')! as Map)['total'] as int) +
          ((_fixture('bazarr_movies_wanted')! as Map)['total'] as int);
      expect(find.text('$total missing subtitles'), findsOneWidget);
      await t.tap(find.byTooltip('Search').first);
      await _settle(t);
      expect(s.sent('PATCH', 'episodes/subtitles'), hasLength(1));
      expect(
        find.textContaining('Bazarr is searching for English'),
        findsOneWidget,
      );
      // The row says so until Bazarr is done.
      expect(find.text('Searching'), findsOneWidget);
      // Asked again a moment later, to see it done.
      final n = s.sent('GET', 'episodes/wanted').length;
      await t.pump(const Duration(seconds: 5));
      await _settle(t);
      expect(s.sent('GET', 'episodes/wanted').length, greaterThan(n));
      await t.pump(const Duration(seconds: 10));
      await _settle(t);
    });

    testWidgets('Manual Search: scored results, Download', (t) async {
      final s = _Bazarr();
      await _open(t, _app(s));
      final movie = find.byWidgetPredicate(
        (w) => w is Text && (w.data ?? '').startsWith('Inception'),
      );
      await t.scrollUntilVisible(
        movie,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await t.tap(
        find.descendant(
          of: find.ancestor(of: movie, matching: find.byType(Row)).first,
          matching: find.byTooltip('Manual Search'),
        ),
      );
      await _settle(t);
      expect(find.byType(AlertDialog), findsOneWidget);
      final best = BazarrRelease.fromJson(
        Map<String, dynamic>.from(
          ((_fixture('bazarr_movies_manual')! as Map)['data'] as List).first
              as Map,
        ),
      );
      expect(find.text('${best.score}%'), findsWidgets);
      await t.tap(find.byTooltip('Download').first);
      await _settle(t);
      expect(s.sent('POST', 'providers/movies'), hasLength(1));
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Bazarr is downloading it'), findsOneWidget);
      await t.pump(const Duration(seconds: 15));
      await _settle(t);
    });

    testWidgets('more than shown: the count is all, and Load More', (t) async {
      final eps = Map<String, dynamic>.from(
        _fixture('bazarr_episodes_wanted')! as Map,
      )..['total'] = 120;
      await _open(t, _app(_Bazarr({'episodes/wanted': eps})));
      final movies = (_fixture('bazarr_movies_wanted')! as Map)['total'] as int;
      expect(find.text('${120 + movies} missing subtitles'), findsOneWidget);
      await t.scrollUntilVisible(
        find.text('Load More'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Load More'), findsOneWidget);
    });

    testWidgets('two languages missing: both searched; HI said', (t) async {
      final s = _Bazarr({
        'episodes/wanted': {
          'data': [
            {
              'seriesTitle': 'Severance',
              'episode_number': '1x1',
              'episodeTitle': 'Good News About Hell',
              'sonarrSeriesId': 3,
              'sonarrEpisodeId': 992,
              'missing_subtitles': [
                {'name': 'English', 'code2': 'en', 'forced': false, 'hi': true},
                {'name': 'French', 'code2': 'fr', 'forced': false, 'hi': false},
              ],
            },
          ],
          'total': 1,
        },
        'movies/wanted': {'data': [], 'total': 0},
      });
      await _open(t, _app(s));
      expect(find.text('English HI'), findsOneWidget);
      expect(find.text('French'), findsOneWidget);
      await t.tap(find.byTooltip('Search'));
      await _settle(t);
      expect(
        [
          for (final a in s.sent('PATCH', 'episodes/subtitles'))
            (a.query['language'], a.query['hi']),
        ],
        [('en', 'True'), ('fr', 'False')],
      );
      await t.pump(const Duration(seconds: 15));
      await _settle(t);
    });

    test('Bazarr alone puts Manage in the navigation', () {
      final c = ProviderContainer(
        overrides: [
          bazarrClientProvider.overrideWithValue(_client(_Bazarr())),
          sonarrClientProvider.overrideWithValue(null),
          radarrClientProvider.overrideWithValue(null),
          lidarrClientProvider.overrideWithValue(null),
          prowlarrClientProvider.overrideWithValue(null),
          qbitClientProvider.overrideWithValue(null),
          sabClientProvider.overrideWithValue(null),
        ],
      );
      addTearDown(c.dispose);
      expect(c.read(arrConfiguredProvider), isTrue);
    });

    testWidgets('pressing a row: Search and Manual Search by name', (t) async {
      await _open(t, _app(_Bazarr()));
      await t.tap(find.text('The Office (US) S01E01 · Pilot'));
      await _settle(t);
      expect(find.text('Search'), findsWidgets);
      expect(find.text('Manual Search'), findsOneWidget);
    });

    testWidgets('Searching goes once Bazarr has had time, found or not', (
      t,
    ) async {
      final s = _Bazarr();
      await _open(t, _app(s));
      await t.tap(find.byTooltip('Search').first);
      await _settle(t);
      expect(find.text('Searching'), findsOneWidget);
      await t.pump(const Duration(seconds: 13));
      await _settle(t);
      // Bazarr found nothing (it's still wanted): it says so no longer.
      expect(find.text('Searching'), findsNothing);
      expect(find.text('The Office (US) S01E01 · Pilot'), findsOneWidget);
    });

    testWidgets('Load More keeps the list up while it asks', (t) async {
      final eps = Map<String, dynamic>.from(
        _fixture('bazarr_episodes_wanted')! as Map,
      )..['total'] = 120;
      final s = _Bazarr({'episodes/wanted': eps});
      await _open(t, _app(s));
      await t.scrollUntilVisible(
        find.text('Load More'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await t.tap(find.text('Load More'));
      await t.pump();
      expect(find.byType(AppSpinner), findsNothing);
      await _settle(t);
      expect(s.sent('GET', 'episodes/wanted').last.query['length'], '100');
    });

    testWidgets('History: Load More only with more to show', (t) async {
      // 30 of each: 60 shown, 60 in all, nothing more.
      final one =
          ((_fixture('bazarr_movies_history')! as Map)['data'] as List).first;
      final thirty = {
        'data': [for (var i = 0; i < 30; i++) one],
        'total': 30,
      };
      await _open(
        t,
        _app(_Bazarr({'movies/history': thirty, 'episodes/history': thirty})),
      );
      // Tall enough that the list's end is built.
      t.view.physicalSize = const Size(1000, 8000);
      await t.tap(find.text('History'));
      await _settle(t);
      expect(find.text('Load More'), findsNothing);
      // With more there, it shows.
      await _open(
        t,
        _app(
          _Bazarr({
            'movies/history': {...thirty, 'total': 31},
            'episodes/history': thirty,
          }),
        ),
      );
      t.view.physicalSize = const Size(1000, 8000);
      await t.tap(find.text('History'));
      await _settle(t);
      expect(find.text('Load More'), findsOneWidget);
    });

    testWidgets('Manual Search that fails can be tried again', (t) async {
      var calls = 0;
      final s = _Flaky(() => calls++ == 0);
      await _open(t, _app(s));
      final movie = find.byWidgetPredicate(
        (w) => w is Text && (w.data ?? '').startsWith('Inception'),
      );
      await t.scrollUntilVisible(
        movie,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await t.tap(
        find.descendant(
          of: find.ancestor(of: movie, matching: find.byType(Row)).first,
          matching: find.byTooltip('Manual Search'),
        ),
      );
      await _settle(t);
      expect(find.text('Retry'), findsOneWidget);
      await t.tap(find.text('Retry'));
      await _settle(t);
      expect(find.byTooltip('Download'), findsWidgets);
    });

    testWidgets('Search All', (t) async {
      final s = _Bazarr();
      await _open(t, _app(s));
      await t.tap(find.text('Search All'));
      await _settle(t);
      expect(s.sent('POST', 'system/tasks'), hasLength(2));
      await t.pump(const Duration(seconds: 15));
      await _settle(t);
    });

    testWidgets('History and Providers', (t) async {
      final s = _Bazarr();
      await _open(t, _app(s));
      await t.tap(find.text('History'));
      await _settle(t);
      expect(
        find.textContaining(
          RegExp(r'^Downloaded · English · yifysubtitles · 90\.56%'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Downloaded by Hand'), findsOneWidget);
      await t.tap(find.text('Providers'));
      await _settle(t);
      expect(find.text('tvsubtitles'), findsOneWidget);
      expect(find.textContaining('Tried again in'), findsOneWidget);
      expect(find.text('Working'), findsOneWidget);
      await t.tap(find.text('Try All Again'));
      await _settle(t);
      expect(s.sent('POST', 'providers'), hasLength(1));
    });

    testWidgets('in Manage: the Subtitles button; on its own, the page', (
      t,
    ) async {
      await _open(t, _app(_Bazarr(), home: const ArrScreen()));
      expect(find.byType(BazarrScreen), findsOneWidget);
    });

    testWidgets('Settings: Add Connection > Bazarr, saved on its own', (t) async {
      final tried = <ConnApp>{};
      final container = ProviderContainer(
        overrides: [
          preferencesProvider.overrideWith(() => _FakePrefs(const Prefs())),
          connTesterProvider.overrideWithValue((app, url, user, key) async {
            tried.add(app);
            return '2.0.1';
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
      await t.tap(find.text('Add Connection'));
      await _settle(t);
      await t.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Bazarr'),
        ),
      );
      await _settle(t);
      // Its own page, with its usual address as the hint.
      expect(find.text('http://192.168.1.10:6767'), findsOneWidget);
      final fields = find.byType(TextField);
      await t.enterText(fields.at(0), '10.0.0.5:6767');
      await t.enterText(fields.at(1), 'bkey');
      await t.tap(find.text('Save & Test'));
      await _settle(t);
      // The check is Bazarr's, and it's saved on its own.
      expect(tried, {ConnApp.bazarr});
      expect(find.text('Connected to Bazarr 2.0.1'), findsOneWidget);
      final p = container.read(preferencesProvider).requireValue;
      expect((p.bazarrUrl, p.bazarrApiKey), ('http://10.0.0.5:6767', 'bkey'));
      expect(p.prowlarrUrl, isEmpty);
    });

    for (final phone in [true, false]) {
      testWidgets('the places behind the apps; on a phone, in More: $phone', (
        t,
      ) async {
        t.view.physicalSize = phone
            ? const Size(400, 900)
            : const Size(1200, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(
          ProviderScope(
            overrides: [
              bazarrClientProvider.overrideWithValue(_client(_Bazarr())),
              radarrClientProvider.overrideWithValue(
                RadarrClient(
                  'http://r',
                  'k',
                  dio: Dio()..httpClientAdapter = _Empty(),
                ),
              ),
              prowlarrClientProvider.overrideWithValue(
                ProwlarrClient(
                  'http://p',
                  'k',
                  dio: Dio()..httpClientAdapter = _Empty(),
                ),
              ),
              sonarrClientProvider.overrideWithValue(null),
              lidarrClientProvider.overrideWithValue(null),
              qbitClientProvider.overrideWithValue(null),
              sabClientProvider.overrideWithValue(null),
              preferencesProvider.overrideWith(() => _FakePrefs(const Prefs())),
              sessionControllerProvider.overrideWith(_SignedOut.new),
            ],
            child: MaterialApp(
              theme: AppTheme.dark(const Color(0xFF8AB4F8)),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const ArrScreen(),
            ),
          ),
        );
        await _settle(t);
        // The section keeps its name.
        expect(find.text('Manage'), findsOneWidget);
        if (phone) {
          expect(find.byTooltip('Subtitles'), findsNothing);
          await t.tap(
            find.descendant(
              of: find.byType(AppBar),
              matching: find.byTooltip('More'),
            ),
          );
          await _settle(t);
          expect(find.text('Indexers'), findsOneWidget);
          expect(find.text('Subtitles'), findsOneWidget);
        } else {
          expect(find.byTooltip('Indexers'), findsOneWidget);
          expect(find.byTooltip('Subtitles'), findsOneWidget);
          expect(
            find.descendant(
              of: find.byType(AppBar),
              matching: find.byTooltip('More'),
            ),
            findsNothing,
          );
        }
      });
    }

    testWidgets('not connected', (t) async {
      await _open(t, _app(null));
      expect(find.text('Bazarr isn\'t connected'), findsOneWidget);
    });
  });
}
