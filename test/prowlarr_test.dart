import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fathom/api/arr_client.dart';
import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/models/arr.dart';
import 'package:fathom/models/session.dart';
import 'package:fathom/screens/arr_activity_screens.dart';
import 'package:fathom/screens/arr_screen.dart';
import 'package:fathom/screens/arr_settings_screen.dart';
import 'package:fathom/screens/prowlarr_screen.dart';
import 'package:fathom/services/settings_backup.dart';
import 'package:fathom/services/tv_mode.dart';
import 'package:fathom/state/arr_providers.dart';
import 'package:fathom/state/preferences.dart';
import 'package:fathom/state/session_controller.dart';
import 'package:fathom/theme/app_theme.dart';
import 'package:fathom/widgets/app_spinner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// Prowlarr in the Manage section: its indexers (on, off, failing, tested),
// a search across them, its counts and its history, and its health beside
// the apps'. The answers are Prowlarr 3.0's own, saved from the rig: one
// indexer that works and one it holds back after failures.

Object? _fixture(String name) =>
    jsonDecode(File('test/fixtures/arr/$name.json').readAsStringSync());

List<Map<String, dynamic>> _list(String name) => [
  for (final m in _fixture(name)! as List) Map<String, dynamic>.from(m as Map),
];

typedef _Asked = ({
  String method,
  String path,
  Map<String, List<String>> query,
  Object? body,
});

class _Prowlarr implements HttpClientAdapter {
  final List<_Asked> asked = [];
  final Map<String, ResponseBody Function()> answers;

  /// Held until completed: Test All, mid-run.
  Completer<void>? hold;
  _Prowlarr([this.answers = const {}]);

  static ResponseBody _json(Object? data, [int code = 200]) =>
      ResponseBody.fromString(
        jsonEncode(data),
        code,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    final path = o.uri.path.replaceFirst(RegExp(r'^.*/api/v1/'), '');
    asked.add((
      method: o.method,
      path: path,
      query: o.uri.queryParametersAll,
      body: o.data,
    ));
    if (path == 'indexer/testall') await hold?.future;
    final custom = answers[path];
    if (custom != null) return custom();
    return switch ((o.method, path)) {
      ('GET', 'indexer') => _json(_fixture('prowlarr_indexers')),
      ('GET', 'indexerstatus') => _json(_fixture('prowlarr_indexerstatus')),
      ('GET', 'indexerstats') => _json(_fixture('prowlarr_indexerstats')),
      ('GET', 'history') => _json(_fixture('prowlarr_history')),
      ('GET', 'search') => _json(_fixture('prowlarr_search')),
      ('GET', 'health') => _json(_fixture('prowlarr_health')),
      ('GET', 'system/status') => _json({
        'appName': 'Prowlarr',
        'version': '3.0.2.5780',
      }),
      // As Prowlarr answers: 400 when any fails, the results still in it.
      ('POST', 'indexer/testall') => _json(_fixture('prowlarr_testall'), 400),
      ('POST', 'indexer/test') =>
        (o.data as Map)['id'] == 2
            ? _json(
                (_fixture('prowlarr_testall')! as List)[1]['validationFailures'],
                400,
              )
            : _json(const {}),
      _ => _json(const {}),
    };
  }

  @override
  void close({bool force = false}) {}

  List<_Asked> sent(String method, String path) => [
    for (final a in asked)
      if (a.method == method && a.path == path) a,
  ];
}

ProwlarrClient _client(_Prowlarr s) => ProwlarrClient(
  'http://prowlarr:9696',
  'k',
  dio: Dio()..httpClientAdapter = s,
);

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

Widget _app(_Prowlarr? prowlarr, {required Widget home, bool radarr = false}) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, _) => home),
      GoRoute(
        path: '/arr/indexers',
        builder: (_, s) {
          _visited.add(s.uri.toString());
          return const ProwlarrScreen();
        },
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      prowlarrClientProvider.overrideWithValue(
        prowlarr == null ? null : _client(prowlarr),
      ),
      sonarrClientProvider.overrideWithValue(null),
      radarrClientProvider.overrideWithValue(
        radarr
            ? RadarrClient(
                'http://r',
                'k',
                dio: Dio()..httpClientAdapter = _Prowlarr(),
              )
            : null,
      ),
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
  Size size = const Size(1000, 1400),
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(app);
  await _settle(t);
}

void main() {
  setUp(_visited.clear);

  group('Prowlarr\'s answers, read', () {
    test('an indexer: protocol, privacy, priority, the kinds it has', () {
      final i = ProwlarrIndexer.fromJson(_list('prowlarr_indexers').first);
      expect(i.name, isNotEmpty);
      expect(i.protocol, 'usenet');
      expect(i.privacy, 'private');
      expect(i.enable, isTrue);
      expect(i.definitionName, 'Newznab');
      // Newznab's own categories only, not the site's copies (100000+).
      expect(i.categories, containsAll(['Movies', 'TV', 'Audio']));
      expect(i.categories.any((c) => c.contains('/')), isFalse);
      expect(i.raw['id'], i.id);
    });

    test('a failing indexer: until when it\'s held back', () {
      final s = ProwlarrIndexerStatus.fromJson(
        _list('prowlarr_indexerstatus').single,
      );
      expect(s.indexerId, 2);
      expect(s.disabledTill, isNotNull);
      expect(s.disabledAt(s.disabledTill!.subtract(const Duration(minutes: 1))), isTrue);
      expect(s.disabledAt(s.disabledTill!.add(const Duration(minutes: 1))), isFalse);
    });

    test('counts, history and a release', () {
      final stats = [
        for (final m in ((_fixture('prowlarr_indexerstats')! as Map)['indexers'] as List))
          ProwlarrIndexerStats.fromJson(Map<String, dynamic>.from(m as Map)),
      ];
      expect(stats.first.queries, greaterThan(0));
      final flaky = stats.firstWhere((s) => s.indexerId == 2);
      expect(flaky.failures, greaterThan(0));
      final h = ProwlarrHistoryItem.fromJson(
        Map<String, dynamic>.from(
          ((_fixture('prowlarr_history')! as Map)['records'] as List).first
              as Map,
        ),
      );
      expect(h.eventType, 'indexerQuery');
      expect(h.query, isNotNull);
      expect(h.source, 'Prowlarr');
      expect(h.results, isNotNull);
      final r = ProwlarrRelease.fromJson(_list('prowlarr_search').first);
      expect(r.title, startsWith('Portishead'));
      expect(r.indexer, 'Rig Usenet');
      expect(r.protocol, 'usenet');
      expect(r.size, greaterThan(0));
      expect(r.categories, isNot(contains(predicate<String>((c) => c.startsWith('1')))));
    });

    test('the API key is kept out of backups, as the others are', () {
      expect(secretPrefKeys, contains('prowlarrApiKey'));
      final p = Prefs.fromJson(
        const Prefs(prowlarrUrl: 'http://p', prowlarrApiKey: 'x').toJson(),
      );
      expect(p.prowlarrUrl, 'http://p');
      expect(p.prowlarrApiKey, 'x');
    });
  });

  group('what Prowlarr is asked', () {
    test('on and off, several at once, in one call', () async {
      final s = _Prowlarr();
      await _client(s).setEnabled([1, 2], false);
      expect(s.sent('PUT', 'indexer/bulk').single.body, {
        'ids': [1, 2],
        'enable': false,
      });
    });

    test('Test All: the results even when Prowlarr says 400', () async {
      final got = await _client(_Prowlarr()).testAll();
      expect([for (final r in got) (r.id, r.ok)], [(1, true), (2, false)]);
      expect(got[1].problems.single, contains('Unable to connect'));
      // The indexer's key in the quoted address stays hidden.
      expect(got[1].problems.single, contains('apikey=…]'));
      expect(got[1].problems.single, isNot(contains('flaky]')));
    });

    test('a test\'s warnings aren\'t problems, and keys stay hidden', () async {
      final s = _Prowlarr({
        'indexer/testall': () => _Prowlarr._json([
          {
            'id': 1,
            'isValid': false,
            'validationFailures': [
              {'errorMessage': 'Slow to answer', 'isWarning': true},
              {'errorMessage': 'Also slow', 'severity': 'warning'},
              {
                'errorMessage': 'Refused at [https://x/api?t=caps&passkey=abc123&x=1]',
                'severity': 'error',
              },
            ],
          },
        ], 400),
      });
      final got = await _client(s).testAll();
      expect(got.single.problems, ['Refused at [https://x/api?t=caps&passkey=…&x=1]']);
      expect(arrHideKeys('a?api_key=s3cret b?token=t&q=1 key=k'), 'a?api_key=… b?token=…&q=1 key=…');
      expect(arrHideKeys('no keys here'), 'no keys here');
    });

    test('one indexer\'s test: fine, or what\'s wrong', () async {
      final s = _Prowlarr();
      final c = _client(s);
      final all = [
        for (final m in _list('prowlarr_indexers')) ProwlarrIndexer.fromJson(m),
      ];
      expect(await c.test(all.firstWhere((i) => i.id == 1)), isNull);
      final bad = await c.test(all.firstWhere((i) => i.id == 2));
      expect(bad!.single, contains('Unable to connect'));
      // The indexer goes back as Prowlarr keeps it.
      expect((s.sent('POST', 'indexer/test').first.body! as Map)['id'], 1);
    });

    test('a search across indexers, and a grab', () async {
      final s = _Prowlarr();
      final c = _client(s);
      final found = await c.search(
        'portishead',
        categories: const [3000],
        indexerIds: const [1],
      );
      expect(found, hasLength(6));
      expect(s.sent('GET', 'search').single.query, {
        'query': ['portishead'],
        'type': ['search'],
        'limit': ['100'],
        'offset': ['0'],
        'categories': ['3000'],
        'indexerIds': ['1'],
      });
      await c.grab(found.first);
      expect(s.sent('POST', 'search').single.body, {
        'guid': found.first.guid,
        'indexerId': found.first.indexerId,
      });
    });

    test('Sync App Indexers is Prowlarr\'s own command', () async {
      final s = _Prowlarr();
      await _client(s).syncApps();
      expect(s.sent('POST', 'command').single.body, {
        'name': 'ApplicationIndexerSync',
      });
    });

    test('another app at Prowlarr\'s address is caught', () async {
      final s = _Prowlarr({
        'system/status': () => _Prowlarr._json({
          'appName': 'Radarr',
          'version': '6',
        }),
      });
      await expectLater(
        _client(s).status(),
        throwsA(
          isA<ArrException>().having(
            (e) => e.message,
            'message',
            'This address is Radarr, not Prowlarr.',
          ),
        ),
      );
    });

    test('a refusal says it\'s Prowlarr\'s', () async {
      final s = _Prowlarr({
        'indexer': () => _Prowlarr._json({'message': 'Nope'}, 500),
      });
      await expectLater(
        _client(s).indexers(),
        throwsA(
          isA<ArrException>().having(
            (e) => e.message,
            'message',
            'Prowlarr: Nope',
          ),
        ),
      );
    });
  });

  group('the Indexers page', () {
    testWidgets('each indexer: what it is, on or failing, its switch', (
      t,
    ) async {
      // The flaky one held back a little longer (today, whenever this runs
      // but the last minute of the day).
      final until = DateTime.now().toUtc().add(const Duration(seconds: 30));
      final s = _Prowlarr({
        'indexerstatus': () => _Prowlarr._json([
          {
            ..._list('prowlarr_indexerstatus').single,
            'disabledTill': until.toIso8601String(),
          },
        ]),
      });
      await _open(t, _app(s, home: const ProwlarrScreen()));
      expect(find.text('Rig Usenet'), findsOneWidget);
      expect(find.text('Flaky Usenet'), findsOneWidget);
      expect(find.text('Newznab · Private · Priority 25'), findsOneWidget);
      // Held back after failures, and when it's tried again.
      expect(find.textContaining('Failing, back at'), findsOneWidget);
      // Off: one switch, one call.
      await t.tap(find.byType(Switch).first);
      await _settle(t);
      expect(s.sent('PUT', 'indexer/bulk').single.body, {
        'ids': [1],
        'enable': false,
      });
      expect(find.text('Rig Usenet is off'), findsOneWidget);
    });

    testWidgets('held back past today: the day is said too', (t) async {
      final until = DateTime.now().toUtc().add(const Duration(days: 1, hours: 1));
      final s = _Prowlarr({
        'indexerstatus': () => _Prowlarr._json([
          {
            ..._list('prowlarr_indexerstatus').single,
            'disabledTill': until.toIso8601String(),
          },
        ]),
      });
      await _open(t, _app(s, home: const ProwlarrScreen()));
      expect(find.textContaining(RegExp(r'^Failing, back .+ at ')), findsOneWidget);
    });

    testWidgets('Test All marks each, and says how many failed', (t) async {
      final s = _Prowlarr();
      await _open(t, _app(s, home: const ProwlarrScreen()));
      await t.tap(find.text('Test All'));
      await _settle(t);
      expect(find.text('1 of 2 indexers failed the test'), findsOneWidget);
      expect(find.text('Works'), findsOneWidget);
      expect(find.textContaining('Unable to connect'), findsWidgets);
    });

    testWidgets('one indexer\'s Test', (t) async {
      final s = _Prowlarr();
      await _open(t, _app(s, home: const ProwlarrScreen()));
      await t.tap(find.byTooltip('Test').first);
      await _settle(t);
      expect(s.sent('POST', 'indexer/test'), hasLength(1));
      expect(find.text('Rig Usenet works'), findsOneWidget);
    });

    testWidgets('Search: a category, the results, a grab', (t) async {
      final s = _Prowlarr();
      await _open(t, _app(s, home: const ProwlarrScreen()));
      await t.tap(find.text('Search').first);
      await _settle(t);
      await t.tap(find.text('Music'));
      await _settle(t);
      // Nothing typed: nothing asked.
      expect(s.sent('GET', 'search'), isEmpty);
      await t.enterText(find.byType(TextField), 'portishead');
      await t.testTextInput.receiveAction(TextInputAction.search);
      await _settle(t);
      expect(s.sent('GET', 'search').single.query['categories'], ['3000']);
      expect(find.text('6 results'), findsOneWidget);
      final first = ProwlarrRelease.fromJson(_list('prowlarr_search').first);
      expect(find.text(first.title), findsOneWidget);
      await t.tap(find.byTooltip('Grab').first);
      await _settle(t);
      expect(s.sent('POST', 'search'), hasLength(1));
      expect(find.byTooltip('Grabbed'), findsOneWidget);
    });

    testWidgets('Test All: none on, and one of one', (t) async {
      final none = _Prowlarr({'indexer/testall': () => _Prowlarr._json([])});
      await _open(t, _app(none, home: const ProwlarrScreen()));
      await t.tap(find.text('Test All'));
      await _settle(t);
      expect(find.text('No indexers are on to test'), findsOneWidget);
    });

    testWidgets('Test All, one failing of one', (t) async {
      final s = _Prowlarr({
        'indexer/testall': () => _Prowlarr._json([
          (_fixture('prowlarr_testall')! as List)[1],
        ], 400),
      });
      await _open(t, _app(s, home: const ProwlarrScreen()));
      await t.tap(find.text('Test All'));
      await _settle(t);
      expect(find.text('The indexer failed the test'), findsOneWidget);
    });

    testWidgets('Test All marks only the indexers that are on', (t) async {
      final s = _Prowlarr({
        'indexer': () => _Prowlarr._json([
          for (final m in _list('prowlarr_indexers'))
            {...m, 'enable': m['id'] == 1},
        ]),
      })..hold = Completer();
      await _open(t, _app(s, home: const ProwlarrScreen()));
      await t.tap(find.text('Test All'));
      await _settle(t);
      // While it runs: the row that's on is testing, the one that's off isn't
      // (Prowlarr's Test All leaves it out).
      expect(find.text('Testing'), findsOneWidget);
      final testing = find.ancestor(
        of: find.text('Testing'),
        matching: find.byType(Column),
      );
      expect(
        find.descendant(of: testing.first, matching: find.text('Rig Usenet')),
        findsOneWidget,
      );
      s.hold!.complete();
      await _settle(t);
      expect(find.text('Testing'), findsNothing);
    });

    testWidgets('results stay across tabs; tests refresh the list', (t) async {
      final s = _Prowlarr();
      await _open(t, _app(s, home: const ProwlarrScreen()));
      final before = s.sent('GET', 'indexer').length;
      await t.tap(find.byTooltip('Test').first);
      await _settle(t);
      // One indexer's test asks for the list again (it can be back in use).
      expect(s.sent('GET', 'indexer').length, greaterThan(before));
      expect(find.text('Works'), findsOneWidget);
      await t.tap(find.text('Stats'));
      await _settle(t);
      await t.tap(find.text('Indexers').first);
      await _settle(t);
      expect(find.text('Works'), findsOneWidget);
    });

    testWidgets('a held-back indexer is asked about again when it\'s due', (
      t,
    ) async {
      final until = DateTime.now().toUtc().add(const Duration(seconds: 3));
      final s = _Prowlarr({
        'indexerstatus': () => _Prowlarr._json([
          {
            ..._list('prowlarr_indexerstatus').single,
            'disabledTill': until.toIso8601String(),
          },
        ]),
      });
      await _open(t, _app(s, home: const ProwlarrScreen()));
      final before = s.sent('GET', 'indexerstatus').length;
      await t.pump(const Duration(seconds: 1));
      expect(s.sent('GET', 'indexerstatus').length, before);
      await t.pump(const Duration(seconds: 5));
      await _settle(t);
      expect(s.sent('GET', 'indexerstatus').length, greaterThan(before));
    });

    testWidgets('Search: an empty box drops the old results', (t) async {
      final s = _Prowlarr();
      await _open(t, _app(s, home: const ProwlarrScreen()));
      await t.tap(find.text('Search').first);
      await _settle(t);
      await t.enterText(find.byType(TextField), 'portishead');
      await t.testTextInput.receiveAction(TextInputAction.search);
      await _settle(t);
      expect(find.text('6 results'), findsOneWidget);
      await t.enterText(find.byType(TextField), '');
      await t.tap(find.text('Music'));
      await _settle(t);
      expect(find.text('6 results'), findsNothing);
      expect(s.sent('GET', 'search'), hasLength(1));
    });

    testWidgets('Search: the same guid from two indexers, grabbed once', (
      t,
    ) async {
      final two = _list('prowlarr_search').take(2).toList();
      final s = _Prowlarr({
        'search': () => _Prowlarr._json([
          {...two[0], 'guid': 'same', 'indexerId': 1, 'title': 'A copy'},
          {...two[1], 'guid': 'same', 'indexerId': 2, 'title': 'B copy'},
        ]),
      });
      await _open(t, _app(s, home: const ProwlarrScreen()));
      await t.tap(find.text('Search').first);
      await _settle(t);
      await t.enterText(find.byType(TextField), 'x');
      await t.testTextInput.receiveAction(TextInputAction.search);
      await _settle(t);
      await t.tap(find.byTooltip('Grab').first);
      await _settle(t);
      expect(find.byTooltip('Grabbed'), findsOneWidget);
      expect(find.byTooltip('Grab'), findsOneWidget);
    });

    testWidgets('History: Load More keeps the list up while it asks', (
      t,
    ) async {
      var calls = 0;
      final s = _Prowlarr({
        'history': () {
          calls++;
          return _Prowlarr._json(_fixture('prowlarr_history'));
        },
      });
      await _open(t, _app(s, home: const ProwlarrScreen()));
      await t.tap(find.text('History'));
      await _settle(t);
      final h = ((_fixture('prowlarr_history')! as Map)['records'] as List).first as Map;
      final q = (h['data'] as Map)['query'] as String;
      expect(find.text(q), findsWidgets);
      final asked = calls;
      await t.tap(find.text('Load More'));
      await t.pump();
      expect(find.text(q), findsWidgets);
      expect(find.byType(AppSpinner), findsNothing);
      await _settle(t);
      expect(calls, greaterThan(asked));
      expect(s.sent('GET', 'history').last.query['pageSize'], ['100']);
    });

    testWidgets('Stats and History', (t) async {
      final s = _Prowlarr();
      await _open(t, _app(s, home: const ProwlarrScreen()));
      await t.tap(find.text('Stats'));
      await _settle(t);
      expect(find.textContaining('queries'), findsWidgets);
      expect(find.textContaining('failed request'), findsOneWidget);
      await t.tap(find.text('History'));
      await _settle(t);
      final h = ((_fixture('prowlarr_history')! as Map)['records'] as List).first as Map;
      expect(find.text((h['data'] as Map)['query'] as String), findsWidgets);
    });
  });

  group('on a TV', () {
    for (final onTv in [true, false]) {
      testWidgets('an indexer\'s switch shows the remote is on it: $onTv', (
        t,
      ) async {
        isTvDevice = onTv;
        addTearDown(() => isTvDevice = false);
        await _open(t, _app(_Prowlarr(), home: const ProwlarrScreen()));
        final theme = Theme.of(t.element(find.byType(Switch).first)).switchTheme;
        final focused = {WidgetState.focused, WidgetState.selected};
        expect(
          theme.trackOutlineWidth?.resolve(focused),
          onTv ? 3 : isNull,
        );
        expect(
          theme.overlayColor?.resolve(focused)?.a,
          onTv ? closeTo(0.34, 0.01) : isNull,
        );
        // Not when it isn't focused.
        expect(theme.trackOutlineWidth?.resolve({WidgetState.selected}), isNull);
      });
    }
  });

  group('around it', () {
    testWidgets('Manage has the Indexers button with Prowlarr there', (t) async {
      await _open(t, _app(_Prowlarr(), home: const ArrScreen(), radarr: true));
      await t.tap(find.byTooltip('Indexers'));
      await _settle(t);
      expect(_visited.single, '/arr/indexers');
    });

    test('Prowlarr on its own puts Manage in the navigation', () {
      ProviderContainer only(ProwlarrClient? p) => ProviderContainer(
        overrides: [
          prowlarrClientProvider.overrideWithValue(p),
          sonarrClientProvider.overrideWithValue(null),
          radarrClientProvider.overrideWithValue(null),
          lidarrClientProvider.overrideWithValue(null),
        ],
      );
      final on = only(_client(_Prowlarr()));
      final off = only(null);
      addTearDown(on.dispose);
      addTearDown(off.dispose);
      expect(on.read(arrConfiguredProvider), isTrue);
      expect(off.read(arrConfiguredProvider), isFalse);
    });

    testWidgets('Manage with only Prowlarr opens on its indexers', (t) async {
      await _open(t, _app(_Prowlarr(), home: const ArrScreen()));
      expect(find.text('Rig Usenet'), findsOneWidget);
      expect(find.byType(ProwlarrScreen), findsOneWidget);
    });

    testWidgets('and not without it', (t) async {
      await _open(t, _app(null, home: const ArrScreen(), radarr: true));
      expect(find.byTooltip('Indexers'), findsNothing);
    });

    testWidgets('Health shows Prowlarr after the apps', (t) async {
      await _open(t, _app(_Prowlarr(), home: const ArrHealthScreen(), radarr: true));
      expect(find.text('Prowlarr 3.0.2.5780'), findsOneWidget);
      expect(
        find.textContaining('Indexers unavailable due to failures'),
        findsOneWidget,
      );
      final radarrAt = t.getTopLeft(find.textContaining('Radarr')).dy;
      final prowlarrAt = t.getTopLeft(find.text('Prowlarr 3.0.2.5780')).dy;
      expect(prowlarrAt, greaterThan(radarrAt));
    });

    testWidgets('Settings has a Prowlarr card, saved on its own', (t) async {
      final container = ProviderContainer(
        overrides: [
          preferencesProvider.overrideWith(() => _FakePrefs(const Prefs())),
        ],
      );
      addTearDown(container.dispose);
      t.view.physicalSize = const Size(900, 3200);
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
      expect(find.text('Prowlarr'), findsOneWidget);
      expect(find.text('http://192.168.1.10:9696'), findsOneWidget);
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(8));
      await t.enterText(fields.at(6), '10.0.0.5:9696');
      await t.enterText(fields.at(7), 'pkey');
      await t.tap(find.text('Save & Test').last);
      await _settle(t);
      final p = container.read(preferencesProvider).requireValue;
      expect(p.prowlarrUrl, 'http://10.0.0.5:9696');
      expect(p.prowlarrApiKey, 'pkey');
      expect(p.lidarrUrl, isEmpty);
      // The check is Prowlarr's.
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.textContaining('Prowlarr'),
        ),
        findsOneWidget,
      );
    });
  });
}
