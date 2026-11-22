import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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
import 'package:fathom/services/tv_mode.dart';
import 'package:fathom/state/arr_providers.dart';
import 'package:fathom/state/preferences.dart';
import 'package:fathom/state/seerr_providers.dart';
import 'package:fathom/theme/app_theme.dart';
import 'package:fathom/widgets/arr_widgets.dart';
import 'package:fathom/widgets/cached_image.dart';
import 'package:fathom/widgets/detail_header.dart';
import 'package:fathom/widgets/hover_pill_button.dart';
import 'package:flutter/gestures.dart';
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

  /// How many Seerr says wait in all, when it's asked for fewer than that.
  int? total;
  final Map<String, Map<String, dynamic>> titles = {};
  int pendingAsked = 0;

  /// How the requests were last asked for.
  ({int take, String filter, String sortDirection})? asked;

  /// The answers given, in order: `approve 4`.
  final List<String> answered = [];

  /// How long Seerr takes over an answer.
  Duration answerTakes = Duration.zero;
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
  Future<({List<SeerrRequest> requests, int total})> requestsPage({
    int take = 40,
    String filter = 'all',
    String mediaType = 'all',
    String sort = 'added',
    String sortDirection = 'desc',
  }) async {
    seerr.pendingAsked++;
    seerr.asked = (take: take, filter: filter, sortDirection: sortDirection);
    return (
      requests: [
        for (final r in seerr.pending.take(take)) SeerrRequest.fromJson(r),
      ],
      total: seerr.total ?? seerr.pending.length,
    );
  }

  Future<void> _answer(String how, int id) async {
    if (seerr.answerTakes > Duration.zero) {
      await Future<void>.delayed(seerr.answerTakes);
    }
    seerr.answered.add('$how $id');
    seerr.pending = [
      for (final r in seerr.pending)
        if (r['id'] != id) r,
    ];
    if (seerr.total != null) seerr.total = seerr.total! - 1;
  }

  @override
  Future<void> approveRequest(int id) => _answer('approve', id);

  @override
  Future<void> declineRequest(int id) => _answer('decline', id);
}

/// A Seerr that answers every question with [body], and keeps what it was
/// asked.
class _Reply implements HttpClientAdapter {
  final Object? body;
  final List<Uri> asked = [];
  _Reply(this.body);

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? data,
    Future<void>? cancel,
  ) async {
    asked.add(o.uri);
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _request(
  int id, {
  String type = 'movie',
  required int tmdbId,
  int? tvdbId,
  String by = 'ana',
  String created = '2026-11-20T10:00:00.000Z',

  /// 1 waits for an answer, 2 was approved, 4 failed on its way.
  int status = 1,
}) => {
  'id': id,
  'status': status,
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

/// The poster on a request's card.
Finder _cardPoster() =>
    find.byWidgetPredicate((w) => '${w.runtimeType}' == '_RequestPoster');

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
      ('the narrowest phone', Size(320, 640)),
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

    testWidgets('an answer that comes once its row is gone still counts', (
      t,
    ) async {
      final seerr = two()..answerTakes = const Duration(seconds: 3);
      await _open(
        t,
        '/arr?tab=activity',
        seerr: seerr,
        radarr: _App(ArrKind.radarr),
      );
      await t.tap(find.text('Requests (2)'));
      await _move(t);
      await t.tap(find.text('Approve').first);
      await t.pump(const Duration(milliseconds: 50));

      // Off the list before Seerr has replied.
      await t.tap(find.text('Queue'));
      await _move(t);
      expect(find.byType(SeerrRequestTile), findsNothing);
      expect(seerr.answered, isEmpty);
      final before = seerr.pendingAsked;

      await t.pump(const Duration(seconds: 3));
      await _move(t);
      expect(seerr.answered, ['approve 4']);
      expect(seerr.pendingAsked, greaterThan(before));
      expect(_switch(t).last, 'Requests (1)');
      expect(t.takeException(), isNull);
    });

    testWidgets('more than a page of them: Seerr\'s count, and Load More', (
      t,
    ) async {
      final seerr = _Seerr(
        pending: [for (var i = 1; i <= 130; i++) _request(i, tmdbId: 27205)],
        titles: [_movie(27205, 'Inception')],
      );
      await _open(
        t,
        '/arr?tab=activity',
        seerr: seerr,
        radarr: _App(ArrKind.radarr),
      );
      // Every one that waits is counted, not only the ones sent.
      expect(seerr.asked!.take, 100);
      expect(_switch(t).last, 'Requests (130)');
      await t.tap(find.text('Requests (130)'));
      await _move(t);
      final list = find
          .descendant(
            of: find.byType(ArrRequestsView),
            matching: find.byType(Scrollable),
          )
          .first;
      await t.scrollUntilVisible(
        find.text('Load More'),
        3000,
        scrollable: list,
        maxScrolls: 40,
      );
      expect(find.byKey(const ValueKey(100)), findsOneWidget);
      expect(find.byKey(const ValueKey(101)), findsNothing);

      await t.tap(find.text('Load More'));
      await _move(t);
      expect(seerr.asked!.take, 200);
      await t.scrollUntilVisible(
        find.byKey(const ValueKey(130)),
        3000,
        scrollable: list,
        maxScrolls: 40,
      );
      await _move(t);
      // All of them listed: nothing more to bring.
      expect(find.text('Load More'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('and it\'s back to one page once the list is left', (t) async {
      final seerr = _Seerr(
        pending: [for (var i = 1; i <= 130; i++) _request(i, tmdbId: 27205)],
        titles: [_movie(27205, 'Inception')],
      );
      await _open(
        t,
        '/arr?tab=activity',
        seerr: seerr,
        radarr: _App(ArrKind.radarr),
      );
      await t.tap(find.text('Requests (130)'));
      await _move(t);
      Finder list() => find
          .descendant(
            of: find.byType(ArrRequestsView),
            matching: find.byType(Scrollable),
          )
          .first;
      await t.scrollUntilVisible(
        find.text('Load More'),
        3000,
        scrollable: list(),
        maxScrolls: 40,
      );
      await t.tap(find.text('Load More'));
      await _move(t);
      expect(seerr.asked!.take, 200);

      // Off to the queue: the count is all that's shown of them now, and
      // every later look asks for one page, not for two.
      await t.scrollUntilVisible(
        find.text('Queue'),
        -3000,
        scrollable: list(),
        maxScrolls: 40,
      );
      await t.tap(find.text('Queue'));
      await _move(t);
      expect(find.byType(ArrRequestsView), findsNothing);
      expect(seerr.asked!.take, 100);
      expect(_switch(t).last, 'Requests (130)');
      await t.sendKeyEvent(LogicalKeyboardKey.f5);
      await _move(t);
      expect(seerr.asked!.take, 100);

      // Back on it: the first hundred, and the way to the rest.
      await t.tap(find.text('Requests (130)'));
      await _move(t);
      await t.scrollUntilVisible(
        find.text('Load More'),
        3000,
        scrollable: list(),
        maxScrolls: 40,
      );
      expect(find.byKey(const ValueKey(100)), findsOneWidget);
      expect(find.byKey(const ValueKey(101)), findsNothing);
      expect(t.takeException(), isNull);
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
    // Approved already, unless a test says otherwise: with no answer to
    // give, the way to the app is the row's own button.
    _Seerr movie({int status = 2}) => _Seerr(
      pending: [_request(4, tmdbId: 27205, status: status)],
      titles: [_movie(27205, 'Inception')],
    );

    testWidgets('opens the movie\'s page in Radarr', (t) async {
      final radarr = _App(ArrKind.radarr, {27205: 5});
      await _open(t, '/requests', seerr: movie(), radarr: radarr);
      expect(radarr.asked, [27205]);
      final manage = find.widgetWithText(FilledButton, 'Manage in Radarr');
      expect(manage, findsOneWidget);
      // The one thing in the open: the rest is under the menu.
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.text('Delete Request'), findsNothing);

      await t.tap(manage);
      await _move(t);
      expect(find.text('page: movie 5'), findsOneWidget);
    });

    testWidgets('one that waits has its answers in the open instead', (
      t,
    ) async {
      final radarr = _App(ArrKind.radarr, {27205: 5});
      await _open(t, '/requests', seerr: movie(status: 1), radarr: radarr);
      expect(find.widgetWithText(FilledButton, 'Approve'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Decline'), findsOneWidget);
      expect(find.byType(FilledButton), findsNWidgets(2));
      expect(find.textContaining('Manage in'), findsNothing);
      expect(find.text('Edit Request'), findsNothing);

      // Everything the row does is under its menu, the way to Radarr above
      // the ones that end the request.
      await t.tap(find.byTooltip('More Options'));
      await _move(t);
      double top(String name) => t.getTopLeft(find.text(name).last).dy;
      final names = [
        'Approve',
        'Decline',
        'Edit Request',
        'Manage in Radarr',
        'Delete Request',
      ];
      for (final (i, name) in names.indexed.skip(1)) {
        expect(top(name), greaterThan(top(names[i - 1])), reason: name);
      }
      await t.tap(find.text('Manage in Radarr'));
      await _move(t);
      expect(find.text('page: movie 5'), findsOneWidget);
    });

    testWidgets('one that failed has Retry in the open', (t) async {
      final seerr = movie(status: 4);
      await _open(
        t,
        '/requests',
        seerr: seerr,
        radarr: _App(ArrKind.radarr, {27205: 5}),
      );
      expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      await t.tap(find.byTooltip('More Options'));
      await _move(t);
      expect(find.text('Manage in Radarr'), findsOneWidget);
      expect(find.text('Approve'), findsNothing);
    });

    testWidgets('a right-click opens the same menu', (t) async {
      await _open(
        t,
        '/requests',
        seerr: movie(status: 1),
        radarr: _App(ArrKind.radarr, {27205: 5}),
      );
      await t.tap(find.text('Inception'), buttons: kSecondaryButton);
      await _move(t);
      expect(find.text('Edit Request'), findsOneWidget);
      expect(find.text('Manage in Radarr'), findsOneWidget);
      expect(find.text('Delete Request'), findsOneWidget);
    });

    testWidgets('someone who only asks has no answers to give', (t) async {
      final seerr = movie(status: 1)..permissions = 0;
      await _open(
        t,
        '/requests',
        seerr: seerr,
        radarr: _App(ArrKind.radarr, {27205: 5}),
      );
      expect(find.widgetWithText(FilledButton, 'Approve'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Decline'), findsNothing);
      // Their own request, still theirs to take back.
      await t.tap(find.byTooltip('More Options'));
      await _move(t);
      expect(find.text('Delete Request'), findsOneWidget);
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Edit Request'), findsNothing);
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
      expect(find.byType(FilledButton), findsNothing);
      await t.tap(find.byTooltip('More Options'));
      await _move(t);
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
          pending: [
            _request(9, type: 'tv', tmdbId: 1396, tvdbId: 81189, status: 2),
          ],
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
          pending: [
            _request(9, type: 'tv', tmdbId: 1396, tvdbId: 81189, status: 2),
          ],
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
          // Approved, so the way to it would be in the open.
          pending: [
            _request(9, type: 'tv', tmdbId: 1396, tvdbId: 81189, status: 2),
          ],
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
          pending: [_request(9, type: 'tv', tmdbId: 1396, status: 2)],
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
          pending: [_request(9, type: 'tv', tmdbId: 1396, status: 2)],
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

    // It changes at 560 and at 860 of the room it's given.
    for (final (width, poster) in [
      (412.0, 56.0),
      (559.0, 56.0),
      (560.0, 64.0),
      (859.0, 64.0),
      (860.0, 72.0),
      (1200.0, 72.0),
    ]) {
      testWidgets('makes use of a window ${width.round()} wide', (t) async {
        await _open(
          t,
          '/requests',
          seerr: movie(status: 1),
          radarr: _App(ArrKind.radarr, {27205: 5}),
          size: Size(width, 900),
        );
        final art = t.getRect(_cardPoster());
        expect(art.size, Size(poster, poster * 1.5));
        final approve = t.getRect(find.widgetWithText(FilledButton, 'Approve'));
        final decline = t.getRect(find.widgetWithText(FilledButton, 'Decline'));
        final title = t.getRect(find.text('Inception'));
        final status = t.getRect(find.text('Status'));
        if (poster == 56) {
          // A phone: the answers under the row, each as wide as the other.
          expect(approve.top, greaterThanOrEqualTo(art.bottom));
          expect(decline.top, approve.top);
          expect(decline.left, greaterThan(approve.right));
          expect(approve.width, closeTo(decline.width, 0.5));
          expect(approve.height, greaterThanOrEqualTo(40));
        } else {
          // Beside the row, one under the other and as wide.
          expect(approve.top, lessThan(art.bottom));
          expect(approve.left, greaterThan(title.left));
          expect(decline.top, greaterThan(approve.bottom));
          expect(decline.left, approve.left);
          expect(decline.width, approve.width);
          expect(approve.width, greaterThanOrEqualTo(132));
        }
        if (poster == 72) {
          // The details in a column of their own.
          expect(status.left, greaterThan(title.left + 100));
          expect(status.right, lessThan(approve.left));
          expect(status.top, lessThan(title.bottom));
        } else {
          expect(status.left, title.left);
          expect(status.top, greaterThan(title.bottom));
        }
        expect(t.takeException(), isNull);
      });
    }

    for (final width in [412.0, 1200.0]) {
      testWidgets('has the title\'s wide picture behind it, kept at the size '
          'it\'s drawn at ${width.round()}', (t) async {
        final seerr = _Seerr(
          pending: [_request(4, tmdbId: 27205, status: 1)],
          titles: [
            {..._movie(27205, 'Inception'), 'backdropPath': '/wide.jpg'},
          ],
        );
        await _open(
          t,
          '/requests',
          seerr: seerr,
          radarr: _App(ArrKind.radarr, {27205: 5}),
          size: Size(width, 900),
        );
        final picture = find.descendant(
          of: find.byType(ArrCardWash),
          matching: find.byWidgetPredicate(
            (w) => w is CachedImage && w.url.endsWith('/wide.jpg'),
          ),
        );
        expect(picture, findsOneWidget);
        final drawn = t.getSize(picture);
        final needs = math.max(drawn.width, drawn.height * 16 / 9);
        final decoded = t.widget<CachedImage>(picture).cacheWidth;
        // Never smaller than it's drawn, and less than a step more: far
        // from the 1280 it comes in at.
        expect(decoded, isNotNull);
        expect(decoded!, greaterThanOrEqualTo(needs));
        expect(decoded, lessThan(needs + 160));
        expect(decoded, lessThan(1000));
        expect(t.takeException(), isNull);
      });
    }

    for (final scale in [1.0, 1.5]) {
      testWidgets('keeps its status whole and inside the card on the '
          'narrowest phone, with text at $scale', (t) async {
        // The longest status there is, at the default size and at the size
        // someone who needs bigger text has it.
        t.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        final request = _request(4, tmdbId: 27205, status: 2);
        (request['media'] as Map)['status'] = 4;
        await _open(
          t,
          '/requests',
          seerr:
              _Seerr(pending: [request], titles: [_movie(27205, 'Inception')]),
          radarr: _App(ArrKind.radarr, {27205: 5}),
          size: const Size(320, 640),
        );
        final card = t.getRect(find.byType(ArrCardWash));
        // Every word of it, never cut short.
        final status = find.text('Partially Available');
        expect(status, findsOneWidget);
        expect(t.getRect(status).right, lessThanOrEqualTo(card.right - 8));
        expect(t.getRect(status).left, greaterThan(card.left));
        // On its one line, not broken over two.
        final words = t.renderObject<RenderParagraph>(status);
        expect(
          words.getMaxIntrinsicWidth(double.infinity),
          lessThanOrEqualTo(words.size.width + 0.5),
        );
        // What each line is stays on one line, as tall as the shortest word
        // of them.
        expect(
          t.getSize(find.text('Requested')).height,
          t.getSize(find.text('Status')).height,
        );
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('and is the card alone for a title without one', (t) async {
      await _open(
        t,
        '/requests',
        seerr: movie(status: 1),
        radarr: _App(ArrKind.radarr, {27205: 5}),
      );
      expect(_cardPoster(), findsOneWidget);
      expect(t.widget<ArrCardWash>(find.byType(ArrCardWash)).picture, isNull);
      // The poster's own picture at most, never a wide one.
      expect(
        find.descendant(
          of: find.byType(ArrCardWash),
          matching: find.byWidgetPredicate(
            (w) => w is CachedImage && w.url.contains('/w1280/'),
          ),
        ),
        findsNothing,
      );
    });

    group('on a TV', () {
      setUp(() => isTvDevice = true);
      tearDown(() => isTvDevice = false);

      testWidgets('keeps every action a button to move to', (t) async {
        final radarr = _App(ArrKind.radarr, {27205: 5});
        await _open(t, '/requests', seerr: movie(status: 1), radarr: radarr);
        for (final name in ['Edit', 'Approve', 'Decline', 'Delete Request']) {
          expect(find.text(name), findsOneWidget, reason: name);
        }
        // No menu to open, and none of the card that has one.
        expect(find.byTooltip('More Options'), findsNothing);
        expect(_cardPoster(), findsNothing);
        // The way to Radarr isn't on a TV yet: it isn't asked.
        expect(radarr.asked, isEmpty);
        expect(find.textContaining('Manage in'), findsNothing);
        expect(t.takeException(), isNull);
      });
    });
  });

  group('how many requests Seerr says there are', () {
    final two = [_request(4, tmdbId: 27205), _request(9, tmdbId: 603)];

    Future<({List<SeerrRequest> requests, int total})> page(_Reply seerr) =>
        SeerrClient(
          'http://seerr',
          'k',
          dio: Dio()..httpClientAdapter = seerr,
        ).requestsPage(take: 2, filter: 'pending', sortDirection: 'asc');

    test('its count of them all, when it sent fewer', () async {
      final seerr = _Reply({
        'pageInfo': {'pages': 65, 'pageSize': 2, 'results': 130, 'page': 1},
        'results': two,
      });
      final got = await page(seerr);
      expect([for (final r in got.requests) r.id], [4, 9]);
      expect(got.total, 130);
      final asked = seerr.asked.single;
      expect(asked.path, '/api/v1/request');
      expect(asked.queryParameters, {
        'take': '2',
        'skip': '0',
        'filter': 'pending',
        'mediaType': 'all',
        'sort': 'added',
        'sortDirection': 'asc',
      });
    });

    test('never fewer than it sent', () async {
      final got = await page(
        _Reply({
          'pageInfo': {'results': 1},
          'results': two,
        }),
      );
      expect(got.total, 2);
    });

    test('the ones it sent, when it doesn\'t count them', () async {
      expect((await page(_Reply({'results': two}))).total, 2);
      expect(
        (await page(
          _Reply({
            'pageInfo': {'results': 'many'},
            'results': two,
          }),
        )).total,
        2,
      );
      expect((await page(_Reply({'pageInfo': {}, 'results': []}))).total, 0);
    });

    test('the plain list is the same page\'s', () async {
      final seerr = _Reply({
        'pageInfo': {'results': 130},
        'results': two,
      });
      final got = await SeerrClient(
        'http://seerr',
        'k',
        dio: Dio()..httpClientAdapter = seerr,
      ).requests(take: 2, filter: 'pending');
      expect([for (final r in got) r.id], [4, 9]);
      expect(seerr.asked.single.queryParameters['take'], '2');
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
