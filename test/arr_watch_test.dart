import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fathom/api/arr_client.dart';
import 'package:fathom/api/jellyfin_client.dart';
import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/models/arr.dart';
import 'package:fathom/models/base_item.dart';
import 'package:fathom/models/session.dart';
import 'package:fathom/screens/arr_detail_screens.dart';
import 'package:fathom/screens/arr_screen.dart';
import 'package:fathom/services/tv_mode.dart';
import 'package:fathom/state/arr_providers.dart';
import 'package:fathom/state/providers.dart';
import 'package:fathom/state/session_controller.dart';
import 'package:fathom/theme/app_theme.dart';
import 'package:fathom/widgets/arr_actions.dart';
import 'package:fathom/widgets/detail_header.dart';
import 'package:fathom/widgets/hover_pill_button.dart';
import 'package:fathom/widgets/media_cards.dart';
import 'package:fathom/widgets/tv_focus.dart';
import 'package:fathom/widgets/tv_keyboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// Watch, on a movie's or a show's page in the Manage section: the Jellyfin
// library is asked for the title by the ids it shares with Radarr and
// Sonarr, and the button opens it there.

/// What the library was asked: where, and with what.
typedef _Ask = ({String path, Map<String, String> query});

/// A Jellyfin server holding [items], answering as a real one does (checked
/// against Jellyfin 12.1): a name search gives the titles whose name has the
/// words, a year search the titles of those years.
class _Library implements HttpClientAdapter {
  final List<Map<String, dynamic>> items;

  /// A server from before `/Items` took a user: only the old address works.
  final bool old;
  bool down = false;

  /// How long it takes over each answer.
  Duration takes = Duration.zero;
  final List<_Ask> asked = [];
  _Library(this.items, {this.old = false});

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    final q = o.uri.queryParameters;
    asked.add((path: o.uri.path, query: q));
    if (takes > Duration.zero) await Future<void>.delayed(takes);
    ResponseBody reply(Object? data, [int code = 200]) =>
        ResponseBody.fromString(
          jsonEncode(data),
          code,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
    if (down) return reply({'message': 'down'}, 500);
    if (old && o.uri.path == '/Items') return reply(null, 404);
    final term = q['SearchTerm']?.toLowerCase();
    final years = q['Years']?.split(',').map(int.parse).toSet();
    return reply({
      'Items': [
        for (final i in items)
          if (i['Type'] == q['IncludeItemTypes'] &&
              (term == null ||
                  (i['Name'] as String).toLowerCase().contains(term)) &&
              (years == null || years.contains(i['ProductionYear'])))
            i,
      ],
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _item(
  String id,
  String name,
  int year,
  Map<String, String> ids, {
  String type = 'Movie',
}) => {
  'Id': id,
  'Name': name,
  'Type': type,
  'ProductionYear': year,
  'ProviderIds': ids,
};

/// The rig's library: a movie under its own name, one under a German name,
/// two of the same name, and a show.
List<Map<String, dynamic>> _titles() => [
  _item('jf-inception', 'Inception', 2010, {
    'Tmdb': '27205',
    'Imdb': 'tt1375666',
  }),
  _item('jf-pate', 'Der Pate', 1972, {'Tmdb': '238', 'Imdb': 'tt0068646'}),
  _item('jf-dune-84', 'Dune', 1984, {'Tmdb': '841'}),
  _item('jf-dune-21', 'Dune', 2021, {'Imdb': 'tt1160419'}),
  _item('jf-bb', 'Breaking Bad', 2008, {'Tvdb': '81189'}, type: 'Series'),
];

JellyfinClient _client(_Library lib) =>
    JellyfinClient(deviceId: 'd', httpClient: Dio()..httpClientAdapter = lib);

Future<String?> _find(
  _Library lib, {
  String type = 'Movie',
  required String title,
  required Map<String, String> ids,
  int? year,
  bool byYear = false,
}) => _client(lib).findItemIdByProviderIds(
  baseUrl: 'http://jf',
  userId: 'u1',
  token: 't',
  itemType: type,
  title: title,
  providerIds: ids,
  year: year,
  byYear: byYear,
);

const _session = Session(
  baseUrl: 'http://jf',
  accessToken: 't',
  userId: 'u1',
  userName: 'rig',
);

class _Signed extends SessionController {
  _Signed(this.session);
  final Session? session;

  @override
  Future<Session?> build() async => session;
}

/// What Radarr and Sonarr were asked since the page was opened: `movie/5`.
final List<String> _appAsked = [];

int _askedFor(String what) => _appAsked.where((p) => p == what).length;

/// An app that has one movie and one show, as their pages ask for them.
class _App implements HttpClientAdapter {
  final Map<String, dynamic> title;

  /// What else it has, by what's asked for: `episode`.
  final Map<String, Object> more;
  _App(this.title, {this.more = const {}});

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    final path = o.uri.path.replaceFirst(RegExp(r'^.*/api/v3/'), '');
    _appAsked.add(path);
    final Object reply = more[path] ?? switch (path) {
      'movie/5' || 'series/7' => title,
      // The library's list, for the section itself.
      'movie' || 'series' => [title],
      'queue' ||
      'history' ||
      'blocklist' ||
      'wanted/missing' ||
      'wanted/cutoff' => {
        'page': 1,
        'pageSize': 50,
        'totalRecords': 0,
        'records': [],
      },
      'queue/status' => {'totalCount': 0, 'warnings': false, 'errors': false},
      'system/status' => {'version': '1.0.0'},
      _ => const [],
    };
    return ResponseBody.fromString(
      jsonEncode(reply),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _movie({
  String title = 'Inception',
  int year = 2010,
  int tmdbId = 27205,
  String? imdbId = 'tt1375666',
  bool hasFile = true,
}) => {
  'id': 5,
  'title': title,
  'year': year,
  'tmdbId': tmdbId,
  'imdbId': ?imdbId,
  'monitored': true,
  'hasFile': hasFile,
  'isAvailable': true,
  'status': 'released',
};

Map<String, dynamic> _series({int files = 62}) => {
  'id': 7,
  'title': 'Breaking Bad',
  'year': 2008,
  'tvdbId': 81189,
  'monitored': true,
  'status': 'ended',
  'seasons': const [],
  'statistics': {
    'episodeFileCount': files,
    'episodeCount': 62,
    'totalEpisodeCount': 62,
  },
};

const _wide = Size(1360, 850);
const _phone = Size(412, 892);

late GoRouter _router;

Future<void> _open(
  WidgetTester t,
  String page, {
  required _Library library,
  Map<String, dynamic>? movie,
  Map<String, dynamic>? series,
  Map<String, Object> more = const {},
  Session? session = _session,
  Size size = _wide,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  _appAsked.clear();
  _router = GoRouter(
    initialLocation: page,
    routes: [
      GoRoute(path: '/arr', builder: (_, _) => const ArrScreen()),
      GoRoute(
        path: '/arr/movie/:id',
        builder: (_, s) =>
            ArrMovieScreen(id: int.parse(s.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/arr/series/:id',
        builder: (_, s) =>
            ArrSeriesScreen(id: int.parse(s.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/item',
        builder: (_, s) {
          final item = s.extra! as BaseItemDto;
          return Scaffold(body: Text('library: ${item.id} ${item.name}'));
        },
      ),
    ],
  );
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        sessionControllerProvider.overrideWith(() => _Signed(session)),
        jellyfinClientProvider.overrideWithValue(_client(library)),
        sonarrClientProvider.overrideWithValue(
          series == null
              ? null
              : SonarrClient(
                  'http://s',
                  'k',
                  dio: Dio()..httpClientAdapter = _App(series, more: more),
                ),
        ),
        radarrClientProvider.overrideWithValue(
          movie == null
              ? null
              : RadarrClient(
                  'http://r',
                  'k',
                  dio: Dio()..httpClientAdapter = _App(movie, more: more),
                ),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.dark(const Color(0xFF8AB4F8)),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: _router,
      ),
    ),
  );
  await _move(t);
}

/// Lets the answers arrive and a page or a menu come in. Never
/// pumpAndSettle: a page that's loading never goes quiet.
Future<void> _move(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  await t.pump(const Duration(milliseconds: 400));
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// The header's round buttons, left to right: (name, the main one).
List<(String, bool)> _header(WidgetTester t) => [
  for (final b in t.widgetList<HeaderActionButton>(
    find.byType(HeaderActionButton),
  ))
    (b.tooltip, b.primary),
];

/// The names of what the remote's focus passes through on its way to [f]:
/// 'tvReadStop', 'tvRowActions'.
Set<String?> _focusLabels(WidgetTester t, Finder f) => {
  for (final w in t.widgetList<Focus>(
    find.ancestor(of: f, matching: find.byType(Focus)),
  ))
    w.focusNode?.debugLabel ?? w.debugLabel,
};

/// Every focus node of that name.
List<FocusNode> _focusNodes(String label) => [
  for (final n in FocusManager.instance.rootScope.descendants)
    if (n.debugLabel == label) n,
];

/// One of the header's round buttons, by its name.
Finder _headerButton(String name) => find.byWidgetPredicate(
  (w) => w is HeaderActionButton && w.tooltip == name,
);

/// How many times the library has been looked through. A title that's on
/// disk and isn't found by name is asked for twice a look: by name, then by
/// year.
int _looks(_Library lib) =>
    lib.asked.where((a) => a.query.containsKey('SearchTerm')).length;

/// Pulls the page down to refresh it, as far as what that does.
Future<void> _pullToRefresh(WidgetTester t) async {
  // Not waited for: its answers come with the frames below.
  final done = t
      .widget<RefreshIndicator>(find.byType(RefreshIndicator))
      .onRefresh();
  await _move(t);
  await done;
}

/// Waits, a second at a time, until [done] or [most] seconds have gone.
Future<void> _until(
  WidgetTester t,
  bool Function() done, {
  int most = 60,
}) async {
  for (var i = 0; i < most && !done(); i++) {
    await t.pump(const Duration(seconds: 1));
  }
  await _move(t);
}

/// Lets a slow library's last answer come, so the test ends with nothing
/// still on its way.
Future<void> _lastAnswer(WidgetTester t, _Library lib) async {
  final most = lib.takes;
  lib.takes = Duration.zero;
  await t.pump(most + const Duration(seconds: 1));
  await _move(t);
}

/// A narrow page's buttons, left to right: (name, the main one).
List<(String, bool)> _pills(WidgetTester t) => [
  for (final b in t.widgetList<HoverPillButton>(find.byType(HoverPillButton)))
    (b.label, b.primary),
];

void main() {
  group('finding a title in the library', () {
    test('by the id it shares, among the titles of its name', () async {
      final lib = _Library(_titles());
      expect(
        await _find(lib, title: 'Inception', ids: {'Tmdb': '27205'}),
        'jf-inception',
      );
      // One small question, for movies only, with their ids and little else.
      expect(lib.asked, hasLength(1));
      final ask = lib.asked.single;
      expect(ask.path, '/Items');
      expect(ask.query['SearchTerm'], 'Inception');
      expect(ask.query['IncludeItemTypes'], 'Movie');
      expect(ask.query['Recursive'], 'true');
      expect(ask.query['Fields'], 'ProviderIds');
      expect(ask.query['Limit'], '50');
      expect(ask.query['userId'], 'u1');
    });

    test('the right one of two with the same name', () async {
      final lib = _Library(_titles());
      expect(await _find(lib, title: 'Dune', ids: {'Tmdb': '841'}), 'jf-dune-84');
      // The newer one has no TMDB id in the library: its IMDb id finds it.
      expect(
        await _find(
          lib,
          title: 'Dune',
          ids: {'Tmdb': '438631', 'Imdb': 'tt1160419'},
        ),
        'jf-dune-21',
      );
      // Same name, neither id: not in the library.
      expect(await _find(lib, title: 'Dune', ids: {'Tmdb': '9'}), isNull);
    });

    test('an id is the same however it\'s written', () async {
      final lib = _Library([
        _item('a', 'Heat', 1995, {'tmdb': '949', 'IMDB': 'TT0113277'}),
      ]);
      expect(await _find(lib, title: 'Heat', ids: {'Tmdb': '949'}), 'a');
      expect(await _find(lib, title: 'Heat', ids: {'Imdb': 'tt0113277'}), 'a');
      // The same number under another name is another title.
      expect(await _find(lib, title: 'Heat', ids: {'Tvdb': '949'}), isNull);
    });

    test('a show among shows, not a movie of the same id', () async {
      final lib = _Library([
        _item('movie', 'Breaking Bad', 2008, {'Tvdb': '81189'}),
        ..._titles(),
      ]);
      expect(
        await _find(
          lib,
          type: 'Series',
          title: 'Breaking Bad',
          ids: {'Tvdb': '81189'},
        ),
        'jf-bb',
      );
      expect(lib.asked.single.query['IncludeItemTypes'], 'Series');
    });

    test('under another name, by its year, then those beside it', () async {
      final lib = _Library(_titles());
      // Radarr calls it The Godfather; the library has it in German.
      Future<String?> find({required bool byYear, int? year = 1972}) => _find(
        lib,
        title: 'The Godfather',
        ids: {'Tmdb': '238'},
        year: year,
        byYear: byYear,
      );
      List<String?> years() => [for (final a in lib.asked) a.query['Years']];
      expect(await find(byYear: true), 'jf-pate');
      // Its own year has it: the years beside it aren't asked for.
      expect(years(), [null, '1972']);
      expect(lib.asked.last.query['SearchTerm'], isNull);
      expect(lib.asked.last.query['Limit'], '2000');

      // A year out, as the apps and the library sometimes disagree: the
      // years beside its own are asked next, without its own again.
      lib.asked.clear();
      expect(await find(byYear: true, year: 1973), 'jf-pate');
      expect(years(), [null, '1973', '1972,1974']);
      expect(lib.asked.last.query['SearchTerm'], isNull);
      expect(lib.asked.last.query['Limit'], '2000');
      lib.asked.clear();
      expect(await find(byYear: true, year: 1975), isNull);
      expect(years(), [null, '1975', '1974,1976']);

      // Not asked for unless it's worth it: the title isn't on disk.
      lib.asked.clear();
      expect(await find(byYear: false), isNull);
      expect(lib.asked, hasLength(1));
      // And not without a year to go by.
      lib.asked.clear();
      expect(await find(byYear: true, year: null), isNull);
      expect(lib.asked, hasLength(1));
    });

    test('found by name, the years aren\'t asked for', () async {
      final lib = _Library(_titles());
      expect(
        await _find(
          lib,
          title: 'Inception',
          ids: {'Tmdb': '27205'},
          year: 2010,
          byYear: true,
        ),
        'jf-inception',
      );
      expect(lib.asked, hasLength(1));
    });

    test('with no id to go by, the library isn\'t asked', () async {
      final lib = _Library(_titles());
      expect(await _find(lib, title: 'Inception', ids: {}), isNull);
      expect(await _find(lib, title: 'Inception', ids: {'Tmdb': ''}), isNull);
      expect(lib.asked, isEmpty);
    });

    test('an older server is asked at its own address', () async {
      final lib = _Library(_titles(), old: true);
      expect(
        await _find(lib, title: 'Inception', ids: {'Tmdb': '27205'}),
        'jf-inception',
      );
      expect([for (final a in lib.asked) a.path], [
        '/Items',
        '/Users/u1/Items',
      ]);
      expect(lib.asked.last.query['SearchTerm'], 'Inception');
    });

    test('a server that fails says so', () async {
      final lib = _Library(_titles())..down = true;
      expect(
        () => _find(lib, title: 'Inception', ids: {'Tmdb': '27205'}),
        throwsA(isA<JellyfinException>()),
      );
    });
  });

  group('what the library is asked for a title', () {
    ProviderContainer scope(_Library lib, {Session? session = _session}) {
      final c = ProviderContainer(
        overrides: [
          sessionControllerProvider.overrideWith(() => _Signed(session)),
          jellyfinClientProvider.overrideWithValue(_client(lib)),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    Future<String?> item(ProviderContainer c, ArrLibraryKey k) async {
      await c.read(sessionControllerProvider.future);
      final sub = c.listen(arrLibraryItemProvider(k), (_, _) {});
      addTearDown(sub.close);
      return c.read(arrLibraryItemProvider(k).future);
    }

    test('a movie by its TMDB and IMDb ids', () async {
      final lib = _Library(_titles());
      final m = ArrMovie.fromJson(_movie());
      expect(await item(scope(lib), arrLibraryKeyOfMovie(m)), 'jf-inception');
      expect(lib.asked.single.query['IncludeItemTypes'], 'Movie');
      expect(lib.asked.single.query['SearchTerm'], 'Inception');
    });

    test('a show by its TVDB id', () async {
      final lib = _Library(_titles());
      final s = ArrSeries.fromJson(_series());
      expect(await item(scope(lib), arrLibraryKeyOfSeries(s)), 'jf-bb');
      expect(lib.asked.single.query['IncludeItemTypes'], 'Series');
    });

    test('the longer look only for a title that\'s on disk', () async {
      final onDisk = ArrMovie.fromJson(
        _movie(title: 'The Godfather', year: 1972, tmdbId: 238, imdbId: null),
      );
      final missing = ArrMovie.fromJson(
        _movie(
          title: 'The Godfather',
          year: 1972,
          tmdbId: 238,
          imdbId: null,
          hasFile: false,
        ),
      );
      final a = _Library(_titles());
      expect(await item(scope(a), arrLibraryKeyOfMovie(onDisk)), 'jf-pate');
      expect(a.asked, hasLength(2));
      final b = _Library(_titles());
      expect(await item(scope(b), arrLibraryKeyOfMovie(missing)), isNull);
      expect(b.asked, hasLength(1));

      // A show's files are its episodes'.
      expect(arrLibraryKeyOfSeries(ArrSeries.fromJson(_series())).onDisk, isTrue);
      expect(
        arrLibraryKeyOfSeries(ArrSeries.fromJson(_series(files: 0))).onDisk,
        isFalse,
      );
    });

    test('nothing when signed out, or when the server can\'t say', () async {
      final m = arrLibraryKeyOfMovie(ArrMovie.fromJson(_movie()));
      final out = _Library(_titles());
      expect(await item(scope(out, session: null), m), isNull);
      expect(out.asked, isEmpty);

      final down = _Library(_titles())..down = true;
      expect(await item(scope(down), m), isNull);
      expect(down.asked, isNotEmpty);
    });
  });

  group('Watch on a movie\'s page', () {
    testWidgets('is the main button when the library has it', (t) async {
      await _open(t, '/arr/movie/5', library: _Library(_titles()), movie: _movie());
      final buttons = _header(t);
      expect(buttons.first, ('Watch', true));
      // Searching for a release is still there, no longer the main thing.
      expect(buttons[1], ('Search Movie', false));
      expect(buttons.where((b) => b.$2), hasLength(1));
    });

    testWidgets('opens the movie in the library', (t) async {
      await _open(t, '/arr/movie/5', library: _Library(_titles()), movie: _movie());
      await t.tap(_headerButton('Watch'));
      await _move(t);
      expect(find.text('library: jf-inception Inception'), findsOneWidget);
      // And back to where it was opened from.
      _router.pop();
      await _move(t);
      expect(find.byType(ArrMovieScreen), findsOneWidget);
    });

    testWidgets('isn\'t there when the library hasn\'t got it', (t) async {
      await _open(
        t,
        '/arr/movie/5',
        library: _Library(_titles()),
        movie: _movie(title: 'Tenet', year: 2020, tmdbId: 577922, imdbId: null),
      );
      final buttons = _header(t);
      expect(buttons.first, ('Search Movie', true));
      expect(buttons.map((b) => b.$1), isNot(contains('Watch')));
    });

    testWidgets('nor with the server down, and says nothing', (t) async {
      final down = _Library(_titles())..down = true;
      await _open(t, '/arr/movie/5', library: down, movie: _movie());
      expect(down.asked, isNotEmpty);
      expect(_header(t).first, ('Search Movie', true));
      expect(_header(t).map((b) => b.$1), isNot(contains('Watch')));
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Inception'), findsWidgets);
      expect(t.takeException(), isNull);
    });

    testWidgets('nor signed out', (t) async {
      final lib = _Library(_titles());
      await _open(
        t,
        '/arr/movie/5',
        library: lib,
        movie: _movie(),
        session: null,
      );
      expect(_header(t).first, ('Search Movie', true));
      expect(lib.asked, isEmpty);
    });

    testWidgets('shows once the library has scanned a new download in', (
      t,
    ) async {
      // Radarr has the file; Jellyfin hasn't seen it yet.
      final lib = _Library([]);
      await _open(t, '/arr/movie/5', library: lib, movie: _movie());
      expect(_header(t).first, ('Search Movie', true));
      expect(_looks(lib), 1);

      lib.items.addAll(_titles());
      // Not before the next look, 20 seconds after the first.
      await t.pump(const Duration(seconds: 15));
      await _move(t);
      expect(_looks(lib), 1);
      expect(_header(t).first, ('Search Movie', true));
      await t.pump(const Duration(seconds: 5));
      await _move(t);
      expect(_looks(lib), 2);
      expect(_header(t).first, ('Watch', true));
      expect(_header(t)[1], ('Search Movie', false));

      // Found: that's the end of looking.
      await t.pump(const Duration(minutes: 10));
      await _move(t);
      expect(_looks(lib), 2);
    });

    testWidgets('is looked for a few times, further and further apart', (
      t,
    ) async {
      final lib = _Library([]);
      await _open(t, '/arr/movie/5', library: lib, movie: _movie());
      expect(arrLibraryLookAgain, const [
        Duration(seconds: 20),
        Duration(seconds: 60),
        Duration(seconds: 120),
      ]);
      var looks = 1;
      for (final wait in arrLibraryLookAgain) {
        // Not a moment early.
        await t.pump(wait - const Duration(seconds: 3));
        expect(_looks(lib), looks);
        await t.pump(const Duration(seconds: 3));
        await _move(t);
        expect(_looks(lib), ++looks);
      }
      // Then it's left to a refresh of the page.
      lib.items.addAll(_titles());
      await t.pump(const Duration(minutes: 30));
      await _move(t);
      expect(_looks(lib), 4);
      expect(_header(t).first, ('Search Movie', true));

      await _pullToRefresh(t);
      expect(_looks(lib), 5);
      expect(_header(t).first, ('Watch', true));
    });

    testWidgets('isn\'t looked for again while there\'s no file of it', (
      t,
    ) async {
      final lib = _Library([]);
      await _open(
        t,
        '/arr/movie/5',
        library: lib,
        movie: _movie(hasFile: false),
      );
      expect(_looks(lib), 1);
      lib.items.addAll(_titles());
      await t.pump(const Duration(minutes: 10));
      await _move(t);
      expect(_looks(lib), 1);
      expect(_header(t).first, ('Search Movie', true));
    });

    testWidgets('a server that\'s down is asked again as well', (t) async {
      final lib = _Library(_titles())..down = true;
      await _open(t, '/arr/movie/5', library: lib, movie: _movie());
      expect(_header(t).first, ('Search Movie', true));
      // At the same pace as for a title it hasn't got: not over and over.
      final first = lib.asked.length;
      await t.pump(const Duration(seconds: 15));
      await _move(t);
      expect(lib.asked, hasLength(first));
      lib.down = false;
      await t.pump(const Duration(seconds: 5));
      await _move(t);
      expect(_header(t).first, ('Watch', true));
    });

    testWidgets('a page that\'s closed stops looking', (t) async {
      final lib = _Library([]);
      await _open(t, '/arr/movie/5', library: lib, movie: _movie());
      final asked = lib.asked.length;
      _router.go('/item', extra: const BaseItemDto(id: 'x', name: 'Other'));
      await _move(t);
      expect(find.byType(ArrMovieScreen), findsNothing);
      await t.pump(const Duration(minutes: 10));
      await _move(t);
      expect(lib.asked, hasLength(asked));
    });

    testWidgets('pulling to refresh asks the library again', (t) async {
      final lib = _Library(_titles());
      await _open(t, '/arr/movie/5', library: lib, movie: _movie());
      expect(_header(t).first, ('Watch', true));

      // Taken out of the library since.
      lib.items.clear();
      await _pullToRefresh(t);
      expect(_header(t).first, ('Search Movie', true));
      expect(_header(t).map((b) => b.$1), isNot(contains('Watch')));

      // And put back.
      lib.items.addAll(_titles());
      await _pullToRefresh(t);
      expect(_header(t).first, ('Watch', true));
    });

    testWidgets('and so does F5 with the movie open beside the library', (
      t,
    ) async {
      final lib = _Library([]);
      await _open(t, '/arr', library: lib, movie: _movie(hasFile: false));
      await t.tap(
        find.descendant(
          of: find.byWidgetPredicate(
            (w) =>
                w is Column &&
                w.children.any((c) => c is Text && c.data == 'Inception'),
          ),
          matching: find.byType(HoverPosterArt),
        ),
      );
      await _move(t);
      expect(find.byType(ArrMovieScreen), findsOneWidget);
      expect(find.byTooltip('Watch'), findsNothing);
      expect(find.text('Watch'), findsNothing);
      expect(_looks(lib), 1);
      final lists = _askedFor('movie');
      final pages = _askedFor('movie/5');

      lib.items.addAll(_titles());
      await t.sendKeyEvent(LogicalKeyboardKey.f5);
      await _move(t);
      expect(_looks(lib), 2);
      // The section's own keys: its lists are asked again with the movie,
      // and the movie once, not twice.
      expect(_askedFor('movie'), lists + 1);
      expect(_askedFor('movie/5'), pages + 1);
      expect(
        find.byTooltip('Watch').evaluate().length +
            find.text('Watch').evaluate().length,
        greaterThan(0),
      );

      // The same with the keyboard on one of the movie's own buttons.
      var inPane = false;
      for (var i = 0; i < 80 && !inPane; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pump();
        inPane =
            FocusManager.instance.primaryFocus?.context
                ?.findAncestorWidgetOfExactType<ArrMovieScreen>() !=
            null;
      }
      expect(inPane, isTrue);
      await t.sendKeyEvent(LogicalKeyboardKey.f5);
      await _move(t);
      expect(_looks(lib), 3);
      expect(_askedFor('movie'), lists + 2);
      expect(_askedFor('movie/5'), pages + 2);
    });

    // Tab goes round the page's own controls. The keys listen from a node
    // as wide as the page, which must never be a stop on the way: nothing
    // would show where the keyboard is.
    Future<void> tabsRound(WidgetTester t) async {
      final page = t.view.physicalSize / t.view.devicePixelRatio;
      final stops = <FocusNode>[];
      for (var i = 0; i < 300; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pump();
        final at = FocusManager.instance.primaryFocus!;
        expect(
          at.size.width >= page.width * 0.9 &&
              at.size.height >= page.height * 0.9,
          isFalse,
          reason: 'Tab ${i + 1} stopped on $at',
        );
        // All the way round.
        if (stops.isNotEmpty && at == stops.first) break;
        stops.add(at);
      }
      expect(stops.length, inInclusiveRange(3, 299));
    }

    testWidgets('Tab never stops on the movie\'s whole page', (t) async {
      final lib = _Library(_titles());
      await _open(t, '/arr/movie/5', library: lib, movie: _movie());
      await tabsRound(t);
      // And the keys still work from wherever it stopped.
      final asked = _askedFor('movie/5');
      await t.sendKeyEvent(LogicalKeyboardKey.f5);
      await _move(t);
      expect(_askedFor('movie/5'), asked + 1);
      expect(t.takeException(), isNull);
    });

    testWidgets('nor on the whole section', (t) async {
      final lib = _Library(_titles());
      await _open(t, '/arr', library: lib, movie: _movie());
      await tabsRound(t);
      final asked = _askedFor('movie');
      await t.sendKeyEvent(LogicalKeyboardKey.f5);
      await _move(t);
      expect(_askedFor('movie'), asked + 1);
      expect(t.takeException(), isNull);
    });

    testWidgets('F5 and Ctrl+R on the movie\'s own page ask again', (t) async {
      final lib = _Library([]);
      await _open(
        t,
        '/arr/movie/5',
        library: lib,
        movie: _movie(hasFile: false),
      );
      expect(_header(t).first, ('Search Movie', true));
      expect(_looks(lib), 1);
      final first = _askedFor('movie/5');

      lib.items.addAll(_titles());
      await t.sendKeyEvent(LogicalKeyboardKey.f5);
      await _move(t);
      expect(_askedFor('movie/5'), first + 1);
      expect(_looks(lib), 2);
      expect(_header(t).first, ('Watch', true));

      lib.items.clear();
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyR);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await _move(t);
      expect(_askedFor('movie/5'), first + 2);
      expect(_looks(lib), 3);
      expect(_header(t).first, ('Search Movie', true));
      expect(t.takeException(), isNull);
    });

    testWidgets('holds its place while the library is first asked', (t) async {
      final lib = _Library(_titles())..takes = const Duration(seconds: 5);
      await _open(t, '/arr/movie/5', library: lib, movie: _movie());
      // Asked, and no answer yet.
      expect(_looks(lib), 1);
      expect(_header(t).first, ('Watch', true));
      expect(_header(t)[1], ('Search Movie', false));
      expect(_header(t).where((b) => b.$2), hasLength(1));
      expect(
        t.widget<HeaderActionButton>(_headerButton('Watch')).onTap,
        isNull,
      );
      final watch = t.getRect(_headerButton('Watch'));
      final search = t.getRect(_headerButton('Search Movie'));
      // Nothing to open yet.
      await t.tap(_headerButton('Watch'), warnIfMissed: false);
      await _move(t);
      expect(find.byType(ArrMovieScreen), findsOneWidget);
      expect(find.textContaining('library:'), findsNothing);

      await t.pump(const Duration(seconds: 5));
      await _move(t);
      // The answer moves nothing.
      expect(_header(t).first, ('Watch', true));
      expect(t.getRect(_headerButton('Watch')), watch);
      expect(t.getRect(_headerButton('Search Movie')), search);
      await t.tap(_headerButton('Watch'));
      await _move(t);
      expect(find.text('library: jf-inception Inception'), findsOneWidget);
    });

    testWidgets('gives the place up when the library hasn\'t got it, for good', (
      t,
    ) async {
      final lib = _Library([])..takes = const Duration(seconds: 5);
      await _open(t, '/arr/movie/5', library: lib, movie: _movie());
      expect(_header(t).first, ('Watch', true));
      expect(_header(t)[1], ('Search Movie', false));

      bool held() => _header(t).any((b) => b.$1 == 'Watch');
      await _until(t, () => !held());
      expect(held(), isFalse);
      expect(_header(t).first, ('Search Movie', true));

      // The later looks are quiet: no button comes and goes with each.
      final asked = lib.asked.length;
      await _until(t, () => lib.asked.length > asked);
      expect(lib.asked.length, greaterThan(asked));
      expect(held(), isFalse);
      expect(_header(t).first, ('Search Movie', true));
      await t.pump(const Duration(seconds: 2));
      expect(held(), isFalse);
      await _lastAnswer(t, lib);
      expect(held(), isFalse);

      // Nor does asking again by hand bring it back while the answer's
      // on its way.
      lib.takes = const Duration(seconds: 5);
      final looks = _looks(lib);
      await t.sendKeyEvent(LogicalKeyboardKey.f5);
      await t.pump(const Duration(seconds: 1));
      expect(_looks(lib), looks + 1);
      expect(held(), isFalse);
      expect(_header(t).first, ('Search Movie', true));
      await _lastAnswer(t, lib);
    });

    testWidgets('holds none for a movie with no file', (t) async {
      final lib = _Library(_titles())..takes = const Duration(seconds: 5);
      await _open(
        t,
        '/arr/movie/5',
        library: lib,
        movie: _movie(hasFile: false),
      );
      expect(_looks(lib), 1);
      expect(_header(t).first, ('Search Movie', true));
      expect(_header(t).map((b) => b.$1), isNot(contains('Watch')));
      // The library has it all the same: Watch comes with the answer.
      await t.pump(const Duration(seconds: 5));
      await _move(t);
      expect(_header(t).first, ('Watch', true));
    });

    testWidgets('holds none signed out', (t) async {
      final out = _Library(_titles())..takes = const Duration(seconds: 5);
      await _open(
        t,
        '/arr/movie/5',
        library: out,
        movie: _movie(),
        session: null,
      );
      expect(_header(t).first, ('Search Movie', true));
      expect(_header(t).map((b) => b.$1), isNot(contains('Watch')));
      expect(out.asked, isEmpty);
    });

    testWidgets('on a phone the held button is dimmed, and not under More', (
      t,
    ) async {
      final lib = _Library(_titles())..takes = const Duration(seconds: 5);
      await _open(
        t,
        '/arr/movie/5',
        library: lib,
        movie: _movie(),
        size: _phone,
      );
      expect(_pills(t).first, ('Watch', true));
      final pill = find.widgetWithText(HoverPillButton, 'Watch');
      expect(t.widget<HoverPillButton>(pill).onTap, isNull);
      expect(
        t
            .widget<Opacity>(
              find.descendant(of: pill, matching: find.byType(Opacity)).first,
            )
            .opacity,
        lessThan(1),
      );
      await t.tap(find.byTooltip('More'));
      await _move(t);
      expect(find.text('Search Movie'), findsOneWidget);
      expect(find.text('Watch'), findsOneWidget);
      await t.tapAt(const Offset(5, 5));
      await _move(t);

      await t.pump(const Duration(seconds: 5));
      await _move(t);
      expect(t.widget<HoverPillButton>(pill).onTap, isNotNull);
      await t.tap(find.text('Watch'));
      await _move(t);
      expect(find.text('library: jf-inception Inception'), findsOneWidget);
    });

    testWidgets('an action that can\'t be taken yet is never under More', (
      t,
    ) async {
      t.view.physicalSize = _phone;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final taken = <String>[];
      ArrAction action(String name, {bool can = true, bool primary = false}) =>
          ArrAction(
            icon: Icons.circle,
            label: name,
            primary: primary,
            onTap: can ? () => taken.add(name) : null,
          );
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(const Color(0xFF8AB4F8)),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ArrActionBar(
              header: false,
              title: 'Inception',
              main: [
                action('Go', primary: true),
                action('Later', can: false),
                action('Search'),
              ],
              more: [action('Not Yet', can: false), action('Rename')],
            ),
          ),
        ),
      );
      await t.tap(find.byTooltip('More'));
      await _move(t);
      expect(find.text('Search'), findsOneWidget);
      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Later'), findsNothing);
      expect(find.text('Not Yet'), findsNothing);
      await t.tap(find.text('Rename'));
      await _move(t);
      expect(taken, ['Rename']);
    });

    testWidgets('on a phone it\'s the button that\'s named', (t) async {
      await _open(
        t,
        '/arr/movie/5',
        library: _Library(_titles()),
        movie: _movie(),
        size: _phone,
      );
      final pills = _pills(t);
      expect(pills.first, ('Watch', true));
      expect(find.text('Watch'), findsOneWidget);
      // Search moved under More with the rest.
      expect(pills.map((p) => p.$1), isNot(contains('Search Movie')));
      await t.tap(find.byTooltip('More'));
      await _move(t);
      expect(find.text('Search Movie'), findsOneWidget);
      await t.tapAt(const Offset(5, 5));
      await _move(t);

      await t.tap(find.text('Watch'));
      await _move(t);
      expect(find.text('library: jf-inception Inception'), findsOneWidget);
    });

    testWidgets('without it, Search is the one named there', (t) async {
      await _open(
        t,
        '/arr/movie/5',
        library: _Library(const []),
        movie: _movie(),
        size: _phone,
      );
      expect(_pills(t).first, ('Search Movie', true));
      expect(find.text('Search Movie'), findsOneWidget);
      expect(find.text('Watch'), findsNothing);
    });
  });

  group('Watch on a show\'s page', () {
    testWidgets('is the main button when the library has it', (t) async {
      await _open(
        t,
        '/arr/series/7',
        library: _Library(_titles()),
        series: _series(),
      );
      final buttons = _header(t);
      expect(buttons.first, ('Watch', true));
      expect(buttons[1], ('Search Monitored', false));

      await t.tap(_headerButton('Watch'));
      await _move(t);
      expect(find.text('library: jf-bb Breaking Bad'), findsOneWidget);
    });

    testWidgets('isn\'t there when the library hasn\'t got it', (t) async {
      await _open(
        t,
        '/arr/series/7',
        library: _Library(const []),
        series: _series(),
      );
      expect(_header(t).first, ('Search Monitored', true));
    });

    testWidgets('shows once its episodes are scanned in, or on a refresh', (
      t,
    ) async {
      final lib = _Library([]);
      await _open(t, '/arr/series/7', library: lib, series: _series());
      expect(_header(t).first, ('Search Monitored', true));

      lib.items.addAll(_titles());
      await t.pump(const Duration(seconds: 20));
      await _move(t);
      expect(_header(t).first, ('Watch', true));

      lib.items.clear();
      await _pullToRefresh(t);
      expect(_header(t).first, ('Search Monitored', true));
    });

    testWidgets('holds its place while the library is first asked', (t) async {
      final lib = _Library(_titles())..takes = const Duration(seconds: 5);
      await _open(t, '/arr/series/7', library: lib, series: _series());
      expect(_header(t).first, ('Watch', true));
      expect(_header(t)[1], ('Search Monitored', false));
      expect(
        t.widget<HeaderActionButton>(_headerButton('Watch')).onTap,
        isNull,
      );
      await t.pump(const Duration(seconds: 5));
      await _move(t);
      expect(
        t.widget<HeaderActionButton>(_headerButton('Watch')).onTap,
        isNotNull,
      );

    });

    testWidgets('holds none for a show with no episodes on disk', (t) async {
      final none = _Library(_titles())..takes = const Duration(seconds: 5);
      await _open(t, '/arr/series/7', library: none, series: _series(files: 0));
      expect(_header(t).first, ('Search Monitored', true));
      expect(_header(t).map((b) => b.$1), isNot(contains('Watch')));
      await _lastAnswer(t, none);
      expect(_header(t).first, ('Watch', true));
    });

    testWidgets('F5 on the show\'s own page asks again', (t) async {
      final lib = _Library([]);
      await _open(
        t,
        '/arr/series/7',
        library: lib,
        series: _series(files: 0),
      );
      expect(_header(t).first, ('Search Monitored', true));
      expect(_looks(lib), 1);
      final first = _askedFor('series/7');

      lib.items.addAll(_titles());
      await t.sendKeyEvent(LogicalKeyboardKey.f5);
      await _move(t);
      expect(_askedFor('series/7'), first + 1);
      expect(_looks(lib), 2);
      expect(_header(t).first, ('Watch', true));
      expect(t.takeException(), isNull);
    });
  });

  // What a title's page offers on a TV: searching, monitoring, editing and
  // deleting the title. Its files (importing, renaming, editing and deleting
  // them) and the way out to the app's own site stay on a phone and a
  // computer. Each is checked both ways on the same screen, so it's the TV
  // and not the size that decides.
  group('a title\'s page on a TV', () {
    const tv = Size(960, 540);
    tearDown(() => isTvDevice = false);

    Map<String, dynamic> movieOnDisk() => {
      ..._movie(),
      'titleSlug': 'inception-27205',
      'path': '/movies/Inception (2010)',
      'movieFile': {
        'id': 9,
        'relativePath': 'Inception.2010.1080p.mkv',
        'size': 8000000000,
        'quality': {
          'quality': {'id': 7, 'name': 'Bluray-1080p'},
        },
      },
    };

    Map<String, dynamic> showOnDisk() => {
      ..._series(),
      'titleSlug': 'breaking-bad',
      'path': '/tv/Breaking Bad',
    };

    Map<String, dynamic> showWithSeason() => {
      ...showOnDisk(),
      'seasons': [
        {
          'seasonNumber': 1,
          'monitored': true,
          'statistics': {
            'episodeFileCount': 2,
            'episodeCount': 7,
            'totalEpisodeCount': 7,
          },
        },
      ],
    };

    /// The season's episodes, two of them on disk.
    Map<String, Object> episodes() => {
      for (final (ask, file) in [
        ('episode', 'sonarr_episodes'),
        ('episodefile', 'sonarr_episodefiles'),
      ])
        ask:
            jsonDecode(File('test/fixtures/arr/$file.json').readAsStringSync())
                as Object,
    };

    /// Down the page to where its seasons are: under the header and what's
    /// said about the show, and built only once they're near.
    Future<void> toSeasons(WidgetTester t) async {
      await t.drag(find.byType(CustomScrollView), const Offset(0, -260));
      await _move(t);
    }

    /// Everything the open page's header offers, under More as well.
    Future<Set<String>> offered(WidgetTester t) async {
      final names = {for (final (name, _) in _header(t)) name};
      if (names.remove('More')) {
        await t.tap(_headerButton('More'));
        await _move(t);
        for (final text in t.widgetList<Text>(find.byType(Text))) {
          if (text.data != null) names.add(text.data!);
        }
      }
      return names;
    }

    for (final onTv in [false, true]) {
      final where = onTv ? 'on a TV' : 'off a TV, on the same screen';

      testWidgets('a movie\'s files and the way out, $where', (t) async {
        isTvDevice = onTv;
        await _open(
          t,
          '/arr/movie/5',
          library: _Library(_titles()),
          movie: movieOnDisk(),
          size: tv,
        );
        expect(find.byType(ArrFileCard), findsOneWidget);
        expect(find.text('Edit File'), onTv ? findsNothing : findsOneWidget);
        expect(find.text('Delete File'), onTv ? findsNothing : findsOneWidget);
        // The file can be read with the remote: it's a stop of its own.
        final stops = [
          for (final n in FocusManager.instance.rootScope.descendants)
            if (n.debugLabel == 'tvReadStop') n,
        ];
        expect(stops, onTv ? isNotEmpty : isEmpty);

        final names = await offered(t);
        for (final gone in ['Manual Import', 'Rename Files', 'Open in Radarr']) {
          expect(names.contains(gone), !onTv, reason: gone);
        }
        // What a remote is for stays either way.
        for (final kept in [
          'Search Movie',
          'Interactive Search',
          'Edit',
          'Refresh & Scan',
          'Delete',
        ]) {
          expect(names, contains(kept), reason: kept);
        }
        await t.pump(const Duration(seconds: 4));
      });

      testWidgets('Edit, $where', (t) async {
        isTvDevice = onTv;
        await _open(
          t,
          '/arr/movie/5',
          library: _Library(_titles()),
          movie: movieOnDisk(),
          size: tv,
        );
        await t.tap(_headerButton('Edit'));
        await _move(t);
        final frame = find.byType(ArrDialogFrame);
        expect(frame, findsOneWidget);
        Finder inFrame(Finder f) => find.descendant(of: frame, matching: f);
        expect(inFrame(find.text('Minimum Availability')), findsOneWidget);
        // Where the files are kept is typed, and moves them: not on a TV.
        expect(
          inFrame(find.text('Path')),
          onTv ? findsNothing : findsOneWidget,
        );
        expect(inFrame(find.byType(TextField)), onTv ? findsNothing : findsOne);

        // On a TV the dialog opens with the remote on its first choice, not
        // on Cancel or Save.
        final lit = FocusManager.instance.primaryFocus?.context;
        if (onTv) {
          expect(lit, isNotNull);
          expect(
            lit!.findAncestorWidgetOfExactType<ArrDialogFrame>(),
            isNotNull,
          );
          expect(lit.findAncestorWidgetOfExactType<TvChrome>(), isNull);
        }
        expect(
          inFrame(find.byType(TvPageLanding)),
          onTv ? findsOneWidget : findsNothing,
        );
        expect(inFrame(find.byType(TvChrome)), onTv ? findsOne : findsNothing);

        // A new tag's name: on a TV, a field the remote can open and leave,
        // no taller than a line.
        await t.ensureVisible(find.text('New Tag'));
        await _move(t);
        await t.tap(find.text('New Tag'));
        await _move(t);
        final field = find.byType(TvTextField);
        expect(field, onTv ? findsOneWidget : findsNothing);
        if (onTv) {
          expect(t.getSize(field).height, lessThan(90));
          expect(
            find.descendant(of: field, matching: find.byType(EditableText)),
            findsNothing,
          );
        } else {
          expect(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextField),
            ),
            findsOneWidget,
          );
        }
        expect(t.takeException(), isNull);
        await t.pump(const Duration(seconds: 4));
      });

      testWidgets('a show\'s files and the way out, $where', (t) async {
        isTvDevice = onTv;
        await _open(
          t,
          '/arr/series/7',
          library: _Library(_titles()),
          series: showOnDisk(),
          size: tv,
        );
        final names = await offered(t);
        for (final gone in [
          'Manage Files',
          'Manual Import',
          'Rename Files',
          'Open in Sonarr',
        ]) {
          expect(names.contains(gone), !onTv, reason: gone);
        }
        for (final kept in [
          'Search Monitored',
          'Edit',
          'Refresh & Scan',
          'Delete',
        ]) {
          expect(names, contains(kept), reason: kept);
        }
        await t.pump(const Duration(seconds: 4));
      });

      // What the page is made of for a remote: each part it can stop on, and
      // what holds the header's buttons back once the page has moved on.
      testWidgets('a movie\'s page, part by part, $where', (t) async {
        isTvDevice = onTv;
        await _open(
          t,
          '/arr/movie/5',
          library: _Library(_titles()),
          movie: {...movieOnDisk(), 'overview': 'A thief who steals secrets.'},
          more: {
            'history/movie': [
              {
                'id': 1,
                'movieId': 5,
                'sourceTitle': 'Inception.2010.1080p.BluRay-GRP',
                'eventType': 'grabbed',
                'date': '2026-11-06T05:36:14Z',
              },
            ],
          },
          size: tv,
        );
        Matcher has(String label) =>
            onTv ? contains(label) : isNot(contains(label));
        expect(_focusNodes('tvPageEnds'), onTv ? hasLength(1) : isEmpty);
        expect(_focusLabels(t, find.text('Quality Profile')), has('tvReadStop'));
        expect(
          _focusLabels(t, find.text('A thief who steals secrets.')),
          has('tvReadStop'),
        );
        expect(_focusLabels(t, find.byType(ArrFileCard)), has('tvReadStop'));
        final grab = find.textContaining('Inception.2010.1080p.BluRay-GRP');
        expect(grab, findsOneWidget);
        expect(_focusLabels(t, grab), has('tvReadStop'));

        // A long name wraps to three lines on a TV and no further, and what's
        // under it gets a second line.
        final header = find.byType(DetailHeaderOverlay);
        final name = t.widget<Text>(
          find.descendant(of: header, matching: find.text('Inception')),
        );
        expect(name.maxLines, onTv ? 3 : null);
        expect(name.overflow, onTv ? TextOverflow.ellipsis : null);
        expect(
          t.widget<DetailHeaderOverlay>(header).metaMaxLines,
          onTv ? 2 : 1,
        );
        final meta = t
            .widgetList<Text>(find.descendant(of: header, matching: find.byType(Text)))
            .where((w) => w.style?.fontSize == 13.5);
        expect(meta, isNotEmpty);
        expect(meta.first.maxLines, onTv ? 2 : 1);

        // The header's buttons are stops while the header is open, and on a
        // TV no longer once the page has scrolled under it.
        bool shut() => t
            .widgetList<ExcludeFocus>(
              find.ancestor(
                of: _headerButton('Edit'),
                matching: find.byType(ExcludeFocus),
              ),
            )
            .any((e) => e.excluding);
        expect(_headerButton('Edit'), findsOneWidget);
        expect(shut(), isFalse);
        await t.drag(find.byType(CustomScrollView), const Offset(0, -200));
        await _move(t);
        expect(_headerButton('Edit'), findsOneWidget);
        expect(shut(), onTv);
        await t.pump(const Duration(seconds: 4));
      });

      testWidgets('a season\'s own buttons, $where', (t) async {
        isTvDevice = onTv;
        await _open(
          t,
          '/arr/series/7',
          library: _Library(_titles()),
          series: showWithSeason(),
          more: episodes(),
          size: tv,
        );
        // The show's page is made like a movie's for a remote.
        expect(_focusNodes('tvPageEnds'), onTv ? hasLength(1) : isEmpty);
        expect(
          _focusLabels(t, find.text('Quality Profile')),
          onTv ? contains('tvReadStop') : isNot(contains('tvReadStop')),
        );
        await toSeasons(t);
        final season = find.byType(ExpansionTile);
        expect(season, findsOneWidget);
        // On a TV the season is one stop, and its buttons are a step to the
        // right of it.
        for (final name in ['Unmonitor', 'Search Season', 'Season Actions']) {
          final button = find.descendant(
            of: season,
            matching: find.byTooltip(name),
          );
          expect(button, findsOneWidget, reason: name);
          expect(
            _focusLabels(t, button),
            onTv ? contains('tvRowActions') : isNot(contains('tvRowActions')),
            reason: name,
          );
        }
        // Its menu keeps the search and drops the deleting.
        await t.ensureVisible(find.byTooltip('Season Actions'));
        await _move(t);
        await t.tap(find.byTooltip('Season Actions'));
        await _move(t);
        expect(find.text('Interactive Search'), findsOneWidget);
        expect(
          find.text('Delete Season Files'),
          onTv ? findsNothing : findsOneWidget,
        );
        await t.pump(const Duration(seconds: 4));
      });

      testWidgets('an episode, $where', (t) async {
        isTvDevice = onTv;
        await _open(
          t,
          '/arr/series/7',
          library: _Library(_titles()),
          series: showWithSeason(),
          more: episodes(),
          size: tv,
        );
        await toSeasons(t);
        await t.ensureVisible(find.text('Pilot'));
        await _move(t);
        await t.tap(find.text('Pilot'));
        await _move(t);
        final sheet = find.byType(BottomSheet);
        expect(sheet, findsOneWidget);
        Finder inSheet(Finder f) => find.descendant(of: sheet, matching: f);
        // Nothing to drag with a remote: the sheet opens tall instead.
        expect(
          inSheet(find.bySemanticsLabel('Dismiss')),
          onTv ? findsNothing : findsOneWidget,
        );
        expect(t.widget<BottomSheet>(sheet).showDragHandle, !onTv);
        final space = t.getSize(find.byType(MaterialApp)).height;
        final tall = t.getSize(inSheet(find.byType(ListView))).height;
        if (onTv) {
          expect(tall, greaterThan(space * 0.85));
        } else {
          expect(tall, lessThan(space * 0.7));
        }
        expect(
          (t.widget<ListView>(inSheet(find.byType(ListView))).padding!
                  as EdgeInsets)
              .top,
          onTv ? 24 : 0,
        );
        // The remote starts on the sheet's first button.
        final lit = FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<HoverPillButton>();
        expect(lit?.label, onTv ? 'Search Episode' : isNot('Search Episode'));
        // The file can be read, and deleting it is for a phone or a desktop.
        // (The sheet is pulled up to it first.)
        for (var i = 0; i < 2; i++) {
          await t.drag(inSheet(find.byType(ListView)), const Offset(0, -250));
          await _move(t);
        }
        final file = inSheet(find.byType(ArrFileCard));
        expect(file, findsOneWidget);
        expect(
          _focusLabels(t, file),
          onTv ? contains('tvReadStop') : isNot(contains('tvReadStop')),
        );
        expect(
          inSheet(find.text('Delete File', skipOffstage: false)),
          onTv ? findsNothing : findsOneWidget,
        );
        expect(t.takeException(), isNull);
        await t.pump(const Duration(seconds: 4));
      });
    }
  });
}
