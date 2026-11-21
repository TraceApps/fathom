import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fathom/api/arr_client.dart';
import 'package:fathom/api/seerr_client.dart';
import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/models/arr.dart';
import 'package:fathom/models/seerr_detail.dart';
import 'package:fathom/models/seerr_request.dart';
import 'package:fathom/models/seerr_result.dart';
import 'package:fathom/screens/arr_activity_screens.dart';
import 'package:fathom/screens/arr_screen.dart';
import 'package:fathom/screens/discover_screen.dart';
import 'package:fathom/screens/seerr_detail_screen.dart';
import 'package:fathom/state/arr_providers.dart';
import 'package:fathom/state/preferences.dart';
import 'package:fathom/state/seerr_providers.dart';
import 'package:fathom/theme/app_theme.dart';
import 'package:fathom/widgets/detail_header.dart';
import 'package:fathom/widgets/hover_pill_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// Where Seerr and the Manage section meet: the requests that wait for an
// answer under Activity, and the way from a request or a title in Discover to
// its page in Fathom's own Radarr or Sonarr.

/// Radarr or Sonarr: the titles it [has], by the id Seerr knows them by.
class _App implements HttpClientAdapter {
  final ArrKind kind;

  /// The id Seerr knows a title by, to the app's own id for it.
  final Map<int, int> has;
  bool down = false;

  /// Answers with every title it has, whichever one was asked for: a server
  /// that doesn't take the filter.
  bool unfiltered = false;

  /// The ids the app was asked for, in order.
  final List<int> asked = [];

  /// What it's downloading.
  List<Map<String, Object?>> queue = [];
  _App(this.kind, [Map<int, int>? has]) : has = {...?has};

  String get _path => kind == ArrKind.radarr ? 'movie' : 'series';
  String get _id => kind == ArrKind.radarr ? 'tmdbId' : 'tvdbId';

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    final path = o.uri.path.replaceFirst(RegExp(r'^.*/api/v3/'), '');
    final q = o.uri.queryParameters;
    ResponseBody reply(Object? data, [int code = 200]) =>
        ResponseBody.fromString(
          jsonEncode(data),
          code,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
    if (path == _path && q.containsKey(_id)) {
      final id = int.parse(q[_id]!);
      asked.add(id);
      if (down) return reply({'message': 'down'}, 500);
      if (unfiltered) {
        return reply([
          for (final e in has.entries)
            {'id': e.value, 'title': 'Title ${e.value}', _id: e.key},
        ]);
      }
      final own = has[id];
      return reply([
        if (own != null) {'id': own, 'title': 'Title $own', _id: id},
      ]);
    }
    return reply(switch (path) {
      'queue' => {
        'page': 1,
        'pageSize': 50,
        'totalRecords': queue.length,
        'records': queue,
      },
      'history' || 'blocklist' || 'wanted/missing' || 'wanted/cutoff' => {
        'page': 1,
        'pageSize': 50,
        'totalRecords': 0,
        'records': const [],
      },
      'queue/status' => {'totalCount': 0, 'warnings': false, 'errors': false},
      'system/status' => {'version': '1.0.0'},
      _ => const [],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// What Seerr says, for the providers that would ask it.
class _Seerr {
  /// The account's permissions: 16 answers requests, 0 only makes them.
  int permissions = 16;

  /// How long the permissions take to arrive.
  Duration permissionsTake = Duration.zero;
  List<Map<String, dynamic>> pending;
  final Map<String, Map<String, dynamic>> titles = {};
  int pendingAsked = 0;

  /// How the requests were last asked for.
  ({int take, String filter, String sortDirection})? asked;

  /// The answers given, in order: `approve 4`.
  final List<String> answered = [];
  _Seerr({this.pending = const [], List<Map<String, dynamic>> titles = const []}) {
    for (final t in titles) {
      put(t);
    }
  }

  /// Seerr's word on a title, new or changed.
  void put(Map<String, dynamic> t) =>
      titles['${t.containsKey('name') ? 'tv' : 'movie'}:${t['id']}'] = t;
}

/// Seerr's client, with the requests and the answers to them kept by
/// [seerr] rather than sent anywhere.
class _FakeSeerr extends SeerrClient {
  final _Seerr seerr;
  _FakeSeerr(this.seerr) : super('http://seerr', 'k');

  @override
  Future<List<SeerrRequest>> requests({
    int take = 40,
    String filter = 'all',
    String mediaType = 'all',
    String sort = 'added',
    String sortDirection = 'desc',
  }) async {
    seerr.pendingAsked++;
    seerr.asked = (take: take, filter: filter, sortDirection: sortDirection);
    return [for (final r in seerr.pending) SeerrRequest.fromJson(r)];
  }

  void _answer(String how, int id) {
    seerr.answered.add('$how $id');
    seerr.pending = [
      for (final r in seerr.pending)
        if (r['id'] != id) r,
    ];
  }

  @override
  Future<void> approveRequest(int id) async => _answer('approve', id);

  @override
  Future<void> declineRequest(int id) async => _answer('decline', id);
}

Map<String, dynamic> _request(
  int id, {
  String type = 'movie',
  required int tmdbId,
  int? tvdbId,
  String by = 'ana',
  String created = '2026-11-20T10:00:00.000Z',
}) => {
  'id': id,
  'status': 1,
  'media': {
    'id': 100 + id,
    'mediaType': type,
    'tmdbId': tmdbId,
    'tvdbId': ?tvdbId,
    'status': 2,
  },
  'requestedBy': {'id': 3, 'displayName': by},
  'createdAt': created,
};

Map<String, dynamic> _download(String title) => {
  'title': title,
  'size': 4000,
  'sizeLeft': 1000,
  'status': 'downloading',
};

Map<String, dynamic> _movie(
  int tmdbId,
  String title, {
  int status = 2,
  List<Map<String, dynamic>> downloads = const [],
}) => {
  'id': tmdbId,
  'title': title,
  'releaseDate': '2010-07-16',
  'mediaInfo': {'id': 50, 'status': status, 'downloadStatus': downloads},
};

Map<String, dynamic> _show(
  int tmdbId,
  String name, {
  int? externalTvdb,
  int? mediaTvdb,
}) => {
  'id': tmdbId,
  'name': name,
  'numberOfSeasons': 5,
  'firstAirDate': '2008-01-20',
  'externalIds': {'tvdbId': ?externalTvdb},
  'mediaInfo': {'id': 51, 'status': 3, 'tvdbId': ?mediaTvdb},
};

class _FakePrefs extends PreferencesController {
  @override
  Future<Prefs> build() async => const Prefs();

  @override
  Future<void> edit(Prefs Function(Prefs) change) async {
    state = AsyncData(change(state.asData?.value ?? const Prefs()));
  }
}

const _wide = Size(1200, 900);
const _phone = Size(412, 892);

late ProviderContainer _scope;

/// The app's own font: the test font is far wider, and a row that fits in
/// the app wouldn't fit here.
Future<void> _loadInter() async {
  final loader = FontLoader('Inter');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    loader.addFont(
      Future.value(
        ByteData.sublistView(
          File('assets/fonts/Inter-$w.ttf').readAsBytesSync(),
        ),
      ),
    );
  }
  await loader.load();
}

/// True when the text drew whole: not cut short and not wrapped.
bool _whole(WidgetTester t, Finder text) {
  final p = t.renderObject<RenderParagraph>(text);
  return p.getMaxIntrinsicWidth(double.infinity) <= p.size.width + 0.5;
}

/// Opens [at] with Seerr and the apps as given. `/requests` shows the
/// waiting requests' rows on their own, at the window's width.
Future<void> _open(
  WidgetTester t,
  String at, {
  Object? extra,
  required _Seerr seerr,
  bool connected = true,
  _App? radarr,
  _App? sonarr,
  Size size = _wide,
}) async {
  await _loadInter();
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final router = GoRouter(
    initialLocation: at,
    initialExtra: extra,
    routes: [
      GoRoute(
        path: '/arr',
        builder: (_, s) => ArrScreen(tab: s.uri.queryParameters['tab']),
      ),
      GoRoute(
        path: '/requests',
        builder: (_, _) => Scaffold(
          body: ListView(
            children: [
              for (final r in seerr.pending)
                SeerrRequestTile(request: SeerrRequest.fromJson(r)),
            ],
          ),
        ),
      ),
      GoRoute(
        path: '/seerr-detail',
        builder: (_, s) => SeerrDetailScreen(result: s.extra! as SeerrResult),
      ),
      GoRoute(
        path: '/arr/movie/:id',
        builder: (_, s) =>
            Scaffold(body: Text('page: movie ${s.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/arr/series/:id',
        builder: (_, s) =>
            Scaffold(body: Text('page: series ${s.pathParameters['id']}')),
      ),
    ],
  );
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        preferencesProvider.overrideWith(_FakePrefs.new),
        seerrClientProvider.overrideWithValue(
          connected ? _FakeSeerr(seerr) : null,
        ),
        seerrPermissionsProvider.overrideWith((ref) async {
          // As the app's own: read again whenever a setting is saved.
          ref.watch(preferencesProvider);
          if (seerr.permissionsTake > Duration.zero) {
            await Future<void>.delayed(seerr.permissionsTake);
          }
          return seerr.permissions;
        }),
        seerrDetailProvider.overrideWith((ref, key) async {
          final t = seerr.titles['${key.mediaType}:${key.tmdbId}'];
          if (t == null) throw StateError('no such title');
          return SeerrDetail.fromJson(t);
        }),
        seerrProfileNamesProvider.overrideWith((ref, type) async => const {}),
        seerrSimilarProvider.overrideWith((ref, key) async => const []),
        seerrRecommendationsProvider.overrideWith((ref, key) async => const []),
        radarrClientProvider.overrideWithValue(
          radarr == null
              ? null
              : RadarrClient(
                  'http://r',
                  'k',
                  dio: Dio()..httpClientAdapter = radarr,
                ),
        ),
        sonarrClientProvider.overrideWithValue(
          sonarr == null
              ? null
              : SonarrClient(
                  'http://s',
                  'k',
                  dio: Dio()..httpClientAdapter = sonarr,
                ),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.dark(const Color(0xFF8AB4F8)),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await _move(t);
  _scope = ProviderScope.containerOf(t.element(find.byType(Navigator).first));
}

/// Lets the answers arrive and a page or a menu come in. Never
/// pumpAndSettle: the queue's reload never goes quiet.
Future<void> _move(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  await t.pump(const Duration(milliseconds: 400));
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// The Activity switch's choices, left to right.
List<String> _switch(WidgetTester t) => [
  for (final e in t.widgetList<Text>(
    find.descendant(
      of: find.byWidgetPredicate((w) => w is SegmentedButton),
      matching: find.byType(Text),
    ),
  ))
    e.data!,
];

final _bar = find.byWidgetPredicate((w) => w is SegmentedButton);

/// The dots on the switch's names.
Finder _dots() => find.descendant(of: _bar, matching: find.byType(Badge));

/// The requests listed, top to bottom, by their ids.
List<int> _rows(WidgetTester t) => [
  for (final e in t.widgetList<SeerrRequestTile>(find.byType(SeerrRequestTile)))
    e.request.id,
];

Finder _headerButton(String name) => find.byWidgetPredicate(
  (w) => w is HeaderActionButton && w.tooltip == name,
);

Finder _pill(String name) =>
    find.byWidgetPredicate((w) => w is HoverPillButton && w.label == name);

SeerrResult _result(String type, int tmdbId, String title) =>
    SeerrResult(tmdbId: tmdbId, mediaType: type, title: title);

void main() {
  group('which app is asked for a title Seerr knows', () {
    test('Radarr for a movie by its TMDB id, Sonarr for a show by TVDB', () {
      expect(arrKeyOfSeerr(mediaType: 'movie', tmdbId: 27205), (
        kind: ArrKind.radarr,
        providerId: 27205,
      ));
      expect(arrKeyOfSeerr(mediaType: 'tv', tmdbId: 1396, tvdbId: 81189), (
        kind: ArrKind.sonarr,
        providerId: 81189,
      ));
      // A movie's TVDB id means nothing to Radarr.
      expect(
        arrKeyOfSeerr(mediaType: 'movie', tmdbId: 27205, tvdbId: 5),
        (kind: ArrKind.radarr, providerId: 27205),
      );
    });

    test('neither without the id it goes by', () {
      // A show's TMDB id isn't how Sonarr knows it.
      expect(arrKeyOfSeerr(mediaType: 'tv', tmdbId: 1396), isNull);
      expect(arrKeyOfSeerr(mediaType: 'tv', tmdbId: 1396, tvdbId: 0), isNull);
      expect(arrKeyOfSeerr(mediaType: 'movie', tmdbId: 0), isNull);
    });

    test('a request carries its show\'s TVDB id', () {
      final r = SeerrRequest.fromJson(
        _request(1, type: 'tv', tmdbId: 1396, tvdbId: 81189),
      );
      expect(r.tvdbId, 81189);
      expect(r.mediaType, 'tv');
      expect(
        SeerrRequest.fromJson(_request(2, tmdbId: 27205)).tvdbId,
        isNull,
      );
    });

    test('a title carries it from either place Seerr keeps it', () {
      expect(
        SeerrDetail.fromJson(_show(1396, 'Breaking Bad', externalTvdb: 81189))
            .tvdbId,
        81189,
      );
      expect(
        SeerrDetail.fromJson(_show(1396, 'Breaking Bad', mediaTvdb: 81189))
            .tvdbId,
        81189,
      );
      // TMDB's own word comes first.
      expect(
        SeerrDetail.fromJson(
          _show(1396, 'Breaking Bad', externalTvdb: 81189, mediaTvdb: 7),
        ).tvdbId,
        81189,
      );
      expect(SeerrDetail.fromJson(_show(1396, 'Breaking Bad')).tvdbId, isNull);
    });
  });

  group('Requests under Activity', () {
    _Seerr two() => _Seerr(
      pending: [
        _request(4, tmdbId: 27205),
        _request(9, type: 'tv', tmdbId: 1396, tvdbId: 81189, by: 'ben'),
      ],
      titles: [
        _movie(27205, 'Inception'),
        _show(1396, 'Breaking Bad', externalTvdb: 81189),
      ],
    );

    testWidgets('says how many wait and lists them as Seerr gave them', (
      t,
    ) async {
      final seerr = two();
      await _open(
        t,
        '/arr?tab=activity',
        seerr: seerr,
        radarr: _App(ArrKind.radarr),
      );
      expect(_switch(t), ['Queue', 'History', 'Blocklist', 'Requests (2)']);
      // Only the ones waiting, whoever asked first on top.
      expect(seerr.asked, (take: 100, filter: 'pending', sortDirection: 'asc'));
      // The queue is still what Activity opens on.
      expect(find.byType(ArrRequestsView), findsNothing);

      await t.tap(find.text('Requests (2)'));
      await _move(t);
      expect(find.byType(ArrRequestsView), findsOneWidget);
      expect(_rows(t), [4, 9]);
      expect(find.text('Inception'), findsOneWidget);
      expect(find.text('Breaking Bad'), findsOneWidget);
    });

    testWidgets('whoever asked first is on top, whatever order Seerr gave', (
      t,
    ) async {
      // An older Seerr doesn't take the direction: newest first.
      final seerr = _Seerr(
        pending: [
          _request(12, tmdbId: 27205, created: '2026-11-20T18:00:00.000Z'),
          _request(11, tmdbId: 27205, created: '2026-11-19T09:30:00.000Z'),
          // Two of one moment stay as Seerr had them.
          _request(8, tmdbId: 27205, created: '2026-11-19T09:30:00.000Z'),
          _request(3, tmdbId: 27205, created: '2026-10-02T07:00:00.000Z'),
        ],
        titles: [_movie(27205, 'Inception')],
      );
      await _open(
        t,
        '/arr?tab=activity',
        seerr: seerr,
        radarr: _App(ArrKind.radarr),
        // Tall enough for all four rows.
        size: const Size(1200, 1800),
      );
      await t.tap(find.text('Requests (4)'));
      await _move(t);
      expect(_rows(t), [3, 11, 8, 12]);
    });

    // Every segment is as wide as the widest name, so on a phone the count
    // gives way to a dot: all four on one line, a list's own button beside.
    for (final (name, size) in [
      ('a phone', _phone),
      ('a small phone', Size(360, 760)),
    ]) {
      testWidgets('on $name the count is a dot and all four fit', (t) async {
        final seerr = two()
          ..pending = [
            for (var i = 1; i <= 28; i++) _request(i, tmdbId: 27205),
          ];
        final handle = t.ensureSemantics();
        final radarr = _App(ArrKind.radarr)
          ..queue = [
            {
              'id': 1,
              'movieId': 5,
              'title': 'Inception.2010.1080p',
              'status': 'downloading',
              'size': 1000,
              'sizeleft': 400,
              'downloadId': 'a',
              'movie': {'id': 5, 'title': 'Inception', 'year': 2010},
            },
          ];
        await _open(
          t,
          '/arr?tab=activity',
          seerr: seerr,
          radarr: radarr,
          size: size,
        );
        expect(_switch(t), ['Queue', 'History', 'Blocklist', 'Requests']);
        for (final name in _switch(t)) {
          expect(_whole(t, find.text(name)), isTrue, reason: name);
        }
        expect(_dots(), findsOneWidget);
        expect(
          find.ancestor(
            of: _dots(),
            matching: find.bySemanticsLabel('Requests (28)'),
          ),
          findsWidgets,
        );
        expect(find.bySemanticsLabel('Requests'), findsNothing);
        final bar = t.getRect(_bar);
        expect(bar.left, greaterThanOrEqualTo(16));
        expect(bar.right, lessThanOrEqualTo(size.width - 8));
        expect(bar.height, lessThan(48), reason: 'one line of names');
        expect(t.takeException(), isNull);
        // The queue's Select button, on the switch's own line where the
        // phone is wide enough for both.
        final select = t.getRect(find.byTooltip('Select'));
        if (size.width >= 412) {
          expect(select.left, greaterThanOrEqualTo(bar.right));
          expect(select.center.dy, closeTo(bar.center.dy, 1));
        }
        expect(select.right, lessThanOrEqualTo(size.width));
        // Still the way into the list.
        await t.tap(find.text('Requests'));
        await _move(t);
        expect(_rows(t).take(3), [1, 2, 3]);
        handle.dispose();
      });
    }

    testWidgets('no dot on a phone with none waiting', (t) async {
      await _open(
        t,
        '/arr?tab=activity',
        seerr: _Seerr(),
        radarr: _App(ArrKind.radarr),
        size: _phone,
      );
      expect(_switch(t), ['Queue', 'History', 'Blocklist', 'Requests']);
      expect(_dots(), findsNothing);
      expect(_whole(t, find.text('Requests')), isTrue);
      expect(t.getRect(_bar).height, lessThan(48));
    });

    testWidgets('the count in full where there is room for it', (t) async {
      final seerr = two()
        ..pending = [
          for (var i = 1; i <= 28; i++) _request(i, tmdbId: 27205),
        ];
      await _open(
        t,
        '/arr?tab=activity',
        seerr: seerr,
        radarr: _App(ArrKind.radarr),
        size: const Size(600, 900),
      );
      expect(_switch(t), ['Queue', 'History', 'Blocklist', 'Requests (28)']);
      expect(_whole(t, find.text('Requests (28)')), isTrue);
      expect(_dots(), findsNothing);
    });

    testWidgets('with none waiting, a plain name and a word on why', (t) async {
      await _open(
        t,
        '/arr?tab=activity',
        seerr: _Seerr(),
        radarr: _App(ArrKind.radarr),
      );
      expect(_switch(t).last, 'Requests');
      await t.tap(find.text('Requests'));
      await _move(t);
      expect(find.text('No requests waiting'), findsOneWidget);
      expect(
        find.text('Requests that need a yes or no from you show here'),
        findsOneWidget,
      );
      expect(_rows(t), isEmpty);
    });

    testWidgets('isn\'t there for an account that can\'t answer them', (
      t,
    ) async {
      final seerr = two()..permissions = 0;
      await _open(
        t,
        '/arr?tab=activity',
        seerr: seerr,
        radarr: _App(ArrKind.radarr),
      );
      expect(_switch(t), ['Queue', 'History', 'Blocklist']);
      // And Seerr isn't asked for what wouldn't be shown.
      expect(seerr.pendingAsked, 0);
    });

    testWidgets('an admin answers them too', (t) async {
      await _open(
        t,
        '/arr?tab=activity',
        seerr: two()..permissions = 2,
        radarr: _App(ArrKind.radarr),
      );
      expect(_switch(t).last, 'Requests (2)');
    });

    testWidgets('isn\'t there without Seerr', (t) async {
      final seerr = two();
      await _open(
        t,
        '/arr?tab=activity',
        seerr: seerr,
        connected: false,
        radarr: _App(ArrKind.radarr),
      );
      expect(_switch(t), ['Queue', 'History', 'Blocklist']);
      expect(seerr.pendingAsked, 0);
    });

    testWidgets('a request answered leaves the list and the count', (t) async {
      final seerr = two();
      await _open(
        t,
        '/arr?tab=activity',
        seerr: seerr,
        radarr: _App(ArrKind.radarr),
      );
      await t.tap(find.text('Requests (2)'));
      await _move(t);

      await t.tap(find.text('Approve').first);
      await _move(t);
      expect(seerr.answered, ['approve 4']);
      expect(_switch(t).last, 'Requests (1)');
      expect(_rows(t), [9]);

      await t.tap(find.text('Decline'));
      await _move(t);
      expect(seerr.answered, ['approve 4', 'decline 9']);
      expect(_switch(t).last, 'Requests');
      expect(find.text('No requests waiting'), findsOneWidget);
      // The word on each answer goes away by itself.
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('stays up while the permissions are read again', (t) async {
      final seerr = two();
      await _open(
        t,
        '/arr?tab=activity',
        seerr: seerr,
        radarr: _App(ArrKind.radarr),
      );
      await t.tap(find.text('Requests (2)'));
      await _move(t);

      // Any saved setting has them read again, and that takes a moment.
      seerr.permissionsTake = const Duration(seconds: 2);
      await _scope
          .read(preferencesProvider.notifier)
          .edit((p) => p.copyWith(showArrComingUp: false));
      await t.pump(const Duration(milliseconds: 300));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(ArrRequestsView), findsOneWidget);
      expect(_switch(t).last, 'Requests (2)');
      expect(_rows(t), [4, 9]);
      await t.pump(const Duration(seconds: 2));
      await _move(t);
      expect(find.byType(ArrRequestsView), findsOneWidget);
    });

    testWidgets('gives way to the queue when the account may no longer', (
      t,
    ) async {
      final seerr = two();
      await _open(
        t,
        '/arr?tab=activity',
        seerr: seerr,
        radarr: _App(ArrKind.radarr),
      );
      await t.tap(find.text('Requests (2)'));
      await _move(t);
      expect(find.byType(ArrRequestsView), findsOneWidget);

      seerr.permissions = 0;
      _scope.invalidate(seerrPermissionsProvider);
      await _move(t);
      expect(_switch(t), ['Queue', 'History', 'Blocklist']);
      expect(find.byType(ArrRequestsView), findsNothing);
      expect(find.text('Nothing downloading'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('a request\'s row', () {
    _Seerr movie() => _Seerr(
      pending: [_request(4, tmdbId: 27205)],
      titles: [_movie(27205, 'Inception')],
    );

    testWidgets('opens the movie\'s page in Radarr', (t) async {
      final radarr = _App(ArrKind.radarr, {27205: 5});
      await _open(t, '/requests', seerr: movie(), radarr: radarr);
      expect(radarr.asked, [27205]);
      final manage = find.widgetWithText(FilledButton, 'Manage in Radarr');
      expect(manage, findsOneWidget);
      // With the other things done to a request, above the one that ends it.
      expect(
        t.getTopLeft(manage).dy,
        lessThan(
          t.getTopLeft(find.widgetWithText(FilledButton, 'Delete Request')).dy,
        ),
      );
      expect(
        t.getTopLeft(manage).dy,
        greaterThan(
          t.getTopLeft(find.widgetWithText(FilledButton, 'Decline')).dy,
        ),
      );

      await t.tap(manage);
      await _move(t);
      expect(find.text('page: movie 5'), findsOneWidget);
    });

    testWidgets('its own movie, from a Radarr that answers with them all', (
      t,
    ) async {
      final radarr = _App(ArrKind.radarr, {238: 2, 27205: 5, 157336: 9})
        ..unfiltered = true;
      await _open(t, '/requests', seerr: movie(), radarr: radarr);
      await t.tap(find.widgetWithText(FilledButton, 'Manage in Radarr'));
      await _move(t);
      expect(find.text('page: movie 5'), findsOneWidget);
    });

    testWidgets('and none when the movie isn\'t among them', (t) async {
      final radarr = _App(ArrKind.radarr, {238: 2, 157336: 9})
        ..unfiltered = true;
      await _open(t, '/requests', seerr: movie(), radarr: radarr);
      expect(radarr.asked, [27205]);
      expect(find.textContaining('Manage in'), findsNothing);
    });

    testWidgets('has no such way when Radarr hasn\'t got the movie', (t) async {
      final radarr = _App(ArrKind.radarr, {238: 2});
      await _open(t, '/requests', seerr: movie(), radarr: radarr);
      expect(radarr.asked, [27205]);
      expect(find.textContaining('Manage in'), findsNothing);
      expect(find.text('Delete Request'), findsOneWidget);
    });

    testWidgets('nor when Radarr isn\'t connected, or can\'t be reached', (
      t,
    ) async {
      // Sonarr alone is no help with a movie.
      final sonarr = _App(ArrKind.sonarr, {27205: 5});
      await _open(t, '/requests', seerr: movie(), sonarr: sonarr);
      expect(find.textContaining('Manage in'), findsNothing);
      expect(sonarr.asked, isEmpty);
    });

    testWidgets('nor when Radarr can\'t be reached, and says nothing', (
      t,
    ) async {
      final radarr = _App(ArrKind.radarr, {27205: 5})..down = true;
      await _open(t, '/requests', seerr: movie(), radarr: radarr);
      expect(radarr.asked, [27205]);
      expect(find.textContaining('Manage in'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Inception'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('opens a show\'s page in Sonarr by the request\'s TVDB id', (
      t,
    ) async {
      final sonarr = _App(ArrKind.sonarr, {81189: 7});
      final radarr = _App(ArrKind.radarr, {1396: 99});
      await _open(
        t,
        '/requests',
        seerr: _Seerr(
          pending: [_request(9, type: 'tv', tmdbId: 1396, tvdbId: 81189)],
          // Seerr has nothing more on the title (it can't reach TMDB, say).
        ),
        sonarr: sonarr,
        radarr: radarr,
      );
      expect(sonarr.asked, [81189]);
      // Radarr isn't asked for a show, whatever numbers they share.
      expect(radarr.asked, isEmpty);
      await t.tap(find.widgetWithText(FilledButton, 'Manage in Sonarr'));
      await _move(t);
      expect(find.text('page: series 7'), findsOneWidget);
    });

    testWidgets('its own show, from a Sonarr that answers with them all', (
      t,
    ) async {
      final sonarr = _App(ArrKind.sonarr, {121361: 3, 81189: 7})
        ..unfiltered = true;
      await _open(
        t,
        '/requests',
        seerr: _Seerr(
          pending: [_request(9, type: 'tv', tmdbId: 1396, tvdbId: 81189)],
        ),
        sonarr: sonarr,
      );
      await t.tap(find.widgetWithText(FilledButton, 'Manage in Sonarr'));
      await _move(t);
      expect(find.text('page: series 7'), findsOneWidget);
    });

    testWidgets('and none when the show isn\'t among them', (t) async {
      final sonarr = _App(ArrKind.sonarr, {121361: 3, 73739: 4})
        ..unfiltered = true;
      await _open(
        t,
        '/requests',
        seerr: _Seerr(
          pending: [_request(9, type: 'tv', tmdbId: 1396, tvdbId: 81189)],
        ),
        sonarr: sonarr,
      );
      expect(sonarr.asked, [81189]);
      expect(find.textContaining('Manage in'), findsNothing);
    });

    testWidgets('or by the title\'s own, when the request has none', (t) async {
      final sonarr = _App(ArrKind.sonarr, {81189: 7});
      await _open(
        t,
        '/requests',
        seerr: _Seerr(
          pending: [_request(9, type: 'tv', tmdbId: 1396)],
          titles: [_show(1396, 'Breaking Bad', externalTvdb: 81189)],
        ),
        sonarr: sonarr,
      );
      expect(sonarr.asked, [81189]);
      expect(find.text('Manage in Sonarr'), findsOneWidget);
    });

    testWidgets('a show with no TVDB id anywhere isn\'t asked for', (t) async {
      final sonarr = _App(ArrKind.sonarr, {1396: 7});
      await _open(
        t,
        '/requests',
        seerr: _Seerr(
          pending: [_request(9, type: 'tv', tmdbId: 1396)],
          titles: [_show(1396, 'Breaking Bad')],
        ),
        sonarr: sonarr,
      );
      expect(sonarr.asked, isEmpty);
      expect(find.textContaining('Manage in'), findsNothing);
    });

    testWidgets('on a phone, it\'s in the row\'s menu', (t) async {
      final radarr = _App(ArrKind.radarr, {27205: 5});
      await _open(t, '/requests', seerr: movie(), radarr: radarr, size: _phone);
      expect(find.text('Manage in Radarr'), findsNothing);
      await t.tap(find.byTooltip('More Options'));
      await _move(t);
      expect(find.text('Manage in Radarr'), findsOneWidget);
      expect(
        t.getTopLeft(find.text('Manage in Radarr')).dy,
        lessThan(t.getTopLeft(find.text('Delete Request')).dy),
      );
      await t.tap(find.text('Manage in Radarr'));
      await _move(t);
      expect(find.text('page: movie 5'), findsOneWidget);
    });

    testWidgets('and not in the menu without the movie in Radarr', (t) async {
      await _open(
        t,
        '/requests',
        seerr: movie(),
        radarr: _App(ArrKind.radarr),
        size: _phone,
      );
      await t.tap(find.byTooltip('More Options'));
      await _move(t);
      expect(find.text('Delete Request'), findsOneWidget);
      expect(find.textContaining('Manage in'), findsNothing);
    });
  });

  group('a title\'s page in Discover', () {
    testWidgets('has the way to its page in Radarr among its buttons', (
      t,
    ) async {
      final radarr = _App(ArrKind.radarr, {27205: 5});
      await _open(
        t,
        '/seerr-detail',
        extra: _result('movie', 27205, 'Inception'),
        seerr: _Seerr(titles: [_movie(27205, 'Inception')]),
        radarr: radarr,
      );
      expect(radarr.asked, [27205]);
      expect(_headerButton('Manage in Radarr'), findsOneWidget);
      // One more button, not the main one.
      expect(
        t.widget<HeaderActionButton>(_headerButton('Manage in Radarr')).primary,
        isFalse,
      );
      await t.tap(_headerButton('Manage in Radarr'));
      await _move(t);
      expect(find.text('page: movie 5'), findsOneWidget);
    });

    testWidgets('and none when Radarr hasn\'t got it', (t) async {
      final radarr = _App(ArrKind.radarr);
      await _open(
        t,
        '/seerr-detail',
        extra: _result('movie', 27205, 'Inception'),
        seerr: _Seerr(
          titles: [
            _movie(27205, 'Inception', downloads: [_download('Inception.2010')]),
          ],
        ),
        radarr: radarr,
      );
      expect(radarr.asked, [27205]);
      expect(
        find.byWidgetPredicate(
          (w) => w is HeaderActionButton && w.tooltip.startsWith('Manage in'),
        ),
        findsNothing,
      );
      // The download shows all the same, with nowhere to open.
      expect(find.text('Inception.2010'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
      expect(find.byTooltip('Manage in Radarr'), findsNothing);
    });

    testWidgets('a show\'s goes to Sonarr by its TVDB id', (t) async {
      final sonarr = _App(ArrKind.sonarr, {81189: 7});
      final radarr = _App(ArrKind.radarr, {1396: 99});
      await _open(
        t,
        '/seerr-detail',
        extra: _result('tv', 1396, 'Breaking Bad'),
        seerr: _Seerr(
          titles: [_show(1396, 'Breaking Bad', externalTvdb: 81189)],
        ),
        sonarr: sonarr,
        radarr: radarr,
      );
      expect(sonarr.asked, [81189]);
      expect(radarr.asked, isEmpty);
      await t.tap(_headerButton('Manage in Sonarr'));
      await _move(t);
      expect(find.text('page: series 7'), findsOneWidget);
    });

    testWidgets('on a phone it\'s a named button', (t) async {
      await _open(
        t,
        '/seerr-detail',
        extra: _result('movie', 27205, 'Inception'),
        seerr: _Seerr(titles: [_movie(27205, 'Inception')]),
        radarr: _App(ArrKind.radarr, {27205: 5}),
        size: _phone,
      );
      expect(_headerButton('Manage in Radarr'), findsNothing);
      expect(_pill('Manage in Radarr'), findsOneWidget);
      await t.ensureVisible(_pill('Manage in Radarr'));
      await t.pump();
      await t.tap(_pill('Manage in Radarr'));
      await _move(t);
      expect(find.text('page: movie 5'), findsOneWidget);
    });

    testWidgets('its download opens the page too', (t) async {
      await _open(
        t,
        '/seerr-detail',
        extra: _result('movie', 27205, 'Inception'),
        seerr: _Seerr(
          titles: [
            _movie(27205, 'Inception', downloads: [_download('Inception.2010')]),
          ],
        ),
        radarr: _App(ArrKind.radarr, {27205: 5}),
      );
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      expect(find.byTooltip('Manage in Radarr'), findsOneWidget);
      await t.ensureVisible(find.text('Inception.2010'));
      await t.pump();
      await t.tap(find.text('Inception.2010'));
      await _move(t);
      expect(find.text('page: movie 5'), findsOneWidget);
    });

    testWidgets('Radarr is asked again once the request is approved', (
      t,
    ) async {
      final radarr = _App(ArrKind.radarr);
      final seerr = _Seerr(titles: [_movie(27205, 'Inception')]);
      const key = (mediaType: 'movie', tmdbId: 27205);
      await _open(
        t,
        '/seerr-detail',
        extra: _result('movie', 27205, 'Inception'),
        seerr: seerr,
        radarr: radarr,
      );
      expect(radarr.asked, hasLength(1));
      expect(_headerButton('Manage in Radarr'), findsNothing);

      // Seerr's word read again and unchanged: Radarr is left alone.
      _scope.invalidate(seerrDetailProvider(key));
      await _move(t);
      expect(radarr.asked, hasLength(1));

      // Approved: Seerr hands the movie to Radarr and says so.
      radarr.has[27205] = 5;
      seerr.put(_movie(27205, 'Inception', status: 3));
      _scope.invalidate(seerrDetailProvider(key));
      await _move(t);
      expect(radarr.asked, hasLength(2));
      expect(_headerButton('Manage in Radarr'), findsOneWidget);
    });

    testWidgets('and when its download starts or ends', (t) async {
      final radarr = _App(ArrKind.radarr);
      final seerr = _Seerr(titles: [_movie(27205, 'Inception', status: 3)]);
      const key = (mediaType: 'movie', tmdbId: 27205);
      await _open(
        t,
        '/seerr-detail',
        extra: _result('movie', 27205, 'Inception'),
        seerr: seerr,
        radarr: radarr,
      );
      expect(radarr.asked, hasLength(1));

      radarr.has[27205] = 5;
      seerr.put(
        _movie(
          27205,
          'Inception',
          status: 3,
          downloads: [_download('Inception.2010')],
        ),
      );
      _scope.invalidate(seerrDetailProvider(key));
      await _move(t);
      expect(radarr.asked, hasLength(2));
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);

      // The card reads Seerr every few seconds while it shows; a download
      // that only moves on doesn't send Fathom back to Radarr.
      await t.pump(const Duration(seconds: 8));
      await _move(t);
      expect(radarr.asked, hasLength(2));
    });
  });
}
