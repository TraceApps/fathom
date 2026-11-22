import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fathom/api/arr_client.dart';
import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/models/arr.dart';
import 'package:fathom/models/base_item.dart';
import 'package:fathom/models/session.dart';
import 'package:fathom/routing/app_router.dart';
import 'package:fathom/screens/arr_screen.dart';
import 'package:fathom/screens/home_layout_screen.dart';
import 'package:fathom/screens/home_screen.dart';
import 'package:fathom/services/tv_mode.dart';
import 'package:fathom/state/arr_providers.dart';
import 'package:fathom/state/library_providers.dart';
import 'package:fathom/state/preferences.dart';
import 'package:fathom/state/session_controller.dart';
import 'package:fathom/theme/app_theme.dart';
import 'package:fathom/widgets/arr_home_rows.dart';
import 'package:fathom/widgets/arr_widgets.dart';
import 'package:fathom/widgets/media_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// Home's two rows from Sonarr and Radarr (Downloading Now, Coming This
// Week), where they sit among Home's rows, and their switches in Home
// Layout.

/// The clock the rows read: a Saturday morning.
final _now = DateTime(2026, 11, 21, 10);

/// A moment as the apps send one.
String _at(DateTime local) => local.toUtc().toIso8601String();

/// A release day as Radarr sends one: midnight UTC of that day.
String _day(int y, int m, int d) => DateTime.utc(y, m, d).toIso8601String();

Map<String, dynamic> _page(List<Map<String, dynamic>> records) => {
  'page': 1,
  'pageSize': 500,
  'totalRecords': records.length,
  'records': records,
};

/// An app whose queue and calendar the test can change between reloads.
class _App implements HttpClientAdapter {
  List<Map<String, dynamic>> queue;
  List<Map<String, dynamic>> calendar;
  bool down = false;
  final List<String> asked = [];

  /// What each path was last asked with.
  final Map<String, Map<String, String>> query = {};
  _App({this.queue = const [], this.calendar = const []});

  int count(String path) => asked.where((p) => p == path).length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    final path = o.uri.path.replaceFirst(RegExp(r'^.*/api/v3/'), '');
    asked.add(path);
    query[path] = o.uri.queryParameters;
    if (down) throw const SocketException('down');
    final Object reply = switch (path) {
      'queue' => _page(queue),
      'calendar' => calendar,
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

/// An episode in Sonarr's queue.
Map<String, dynamic> _episodeDownload(
  int id, {
  int seriesId = 7,
  String show = 'Severance',
  int episode = 5,
  String status = 'downloading',
  String? state,
  String? tracked,
  String? downloadId,
  double size = 1000,
  double left = 250,
  DateTime? done,
}) => {
  'id': id,
  'title': '$show.S02E0$episode.1080p',
  'seriesId': seriesId,
  'series': {'id': seriesId, 'title': show},
  'episode': {'seasonNumber': 2, 'episodeNumber': episode, 'title': 'Ep'},
  'size': size,
  'sizeleft': left,
  'status': status,
  'trackedDownloadState': ?state,
  'trackedDownloadStatus': ?tracked,
  'downloadId': downloadId ?? 'dl-$id',
  if (done != null) 'estimatedCompletionTime': _at(done),
};

/// A movie in Radarr's queue.
Map<String, dynamic> _movieDownload(
  int id, {
  int movieId = 3,
  String movie = 'Dune',
  String status = 'downloading',
  String? state,
  String? tracked,
  double size = 1000,
  double left = 500,
  DateTime? done,
}) => {
  'id': id,
  'title': '$movie.2021.2160p',
  'movieId': movieId,
  'movie': {'id': movieId, 'title': movie},
  'size': size,
  'sizeleft': left,
  'status': status,
  'trackedDownloadState': ?state,
  'trackedDownloadStatus': ?tracked,
  'downloadId': 'm-$id',
  if (done != null) 'estimatedCompletionTime': _at(done),
};

/// An episode on Sonarr's calendar.
Map<String, dynamic> _airing(
  int id,
  DateTime when, {
  int seriesId = 7,
  String show = 'Severance',
  int episode = 5,
  String title = 'Trojan\'s Horse',
  bool monitored = true,
  bool hasFile = false,
}) => {
  'id': id,
  'seriesId': seriesId,
  'seasonNumber': 2,
  'episodeNumber': episode,
  'title': title,
  'airDateUtc': _at(when),
  'monitored': monitored,
  'hasFile': hasFile,
  'series': {'id': seriesId, 'title': show},
};

/// A movie on Radarr's calendar.
Map<String, dynamic> _release(
  int id,
  String title, {
  String? inCinemas,
  String? digital,
  bool monitored = true,
  bool hasFile = false,
}) => {
  'id': id,
  'title': title,
  'year': 2026,
  'monitored': monitored,
  'hasFile': hasFile,
  'inCinemas': ?inCinemas,
  'digitalRelease': ?digital,
};

ArrQueueItem _q(ArrKind kind, Map<String, dynamic> j) =>
    ArrQueueItem.fromJson(kind, j);

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

late GoRouter _router;

/// The two rows on a page of their own, as Home stacks them.
Future<void> _rows(WidgetTester t, {_App? sonarr, _App? radarr}) async {
  t.view.physicalSize = const Size(1360, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  arrHomeNow = () => _now;
  addTearDown(() => arrHomeNow = DateTime.now);
  _router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, _) => Scaffold(
          body: ListView(
            children: const [
              Text('top of home'),
              ArrDownloadingRow(height: 238),
              ArrComingUpRow(height: 324),
              Text('rest of home'),
            ],
          ),
        ),
      ),
      GoRoute(
        path: '/arr',
        builder: (_, s) => Scaffold(
          body: Text('manage: ${s.uri.queryParameters['tab']}'),
        ),
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
        sonarrClientProvider.overrideWithValue(
          sonarr == null
              ? null
              : SonarrClient(
                  'http://s',
                  'k',
                  dio: Dio()..httpClientAdapter = sonarr,
                ),
        ),
        radarrClientProvider.overrideWithValue(
          radarr == null
              ? null
              : RadarrClient(
                  'http://r',
                  'k',
                  dio: Dio()..httpClientAdapter = radarr,
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
  await _settle(t);
}

/// Lets the answers arrive and the cards fade in. Never pumpAndSettle: the
/// queue's reload never goes quiet.
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// The picture above [title]: the part of a card that's pressed.
Finder _card(String title) => find.descendant(
  of: find.byWidgetPredicate(
    (w) => w is Column && w.children.any((c) => c is Text && c.data == title),
  ),
  matching: find.byType(HoverPosterArt),
);

/// The row's See All, by the row's name.
Finder _seeAll(String row) => find.descendant(
  of: find.ancestor(of: find.text(row), matching: find.byType(Row)).first,
  matching: find.text('See All'),
);

void main() {
  group('where the rows sit among Home\'s', () {
    const before = ['continueWatching', 'nextUp', 'recentlyAdded', 'myMedia'];

    test('a new install has them between the rows they belong with', () {
      expect(homeRowsInOrder(kHomeRows), [
        'continueWatching',
        'nextUp',
        'arrDownloading',
        'recentlyAdded',
        'arrComingUp',
        'myMedia',
      ]);
      expect(const Prefs().homeRowOrder, kHomeRows);
      // Nothing saved, or nothing the app knows of: the same.
      expect(homeRowsInOrder(const []), kHomeRows);
      expect(homeRowsInOrder(const ['gone']), kHomeRows);
    });

    test('an order saved before them gets them in the same places', () {
      expect(homeRowsInOrder(before), kHomeRows);
      // Rearranged: each still follows the row it follows by default.
      expect(
        homeRowsInOrder(const [
          'myMedia',
          'recentlyAdded',
          'continueWatching',
          'nextUp',
        ]),
        [
          'myMedia',
          'recentlyAdded',
          'arrComingUp',
          'continueWatching',
          'nextUp',
          'arrDownloading',
        ],
      );
    });

    test('an order that names them is kept as it is', () {
      const saved = [
        'arrComingUp',
        'myMedia',
        'arrDownloading',
        'nextUp',
        'continueWatching',
        'recentlyAdded',
      ];
      expect(homeRowsInOrder(saved), saved);
    });

    test('unknown and repeated names are dropped, missing rows put in', () {
      expect(
        homeRowsInOrder(const ['nextUp', 'gone', 'nextUp', 'myMedia']),
        [
          'nextUp',
          'arrDownloading',
          'arrComingUp',
          'myMedia',
          'continueWatching',
          'recentlyAdded',
        ],
      );
      // Nothing usable saved: the order of a new install.
      expect(homeRowsInOrder(const []), kHomeRows);
      expect(homeRowsInOrder(const ['gone']), kHomeRows);
    });

    test('moving the rows listed keeps a row that isn\'t where it was', () {
      // Home Layout without the apps lists four rows. My Media goes first.
      expect(
        homeRowsMoved(kHomeRows, shown: const [
          'myMedia',
          'continueWatching',
          'nextUp',
          'recentlyAdded',
        ]),
        [
          'myMedia',
          'continueWatching',
          'nextUp',
          'arrDownloading',
          'recentlyAdded',
          'arrComingUp',
        ],
      );
      // One that led the order still leads it.
      expect(
        homeRowsMoved(
          const ['arrDownloading', 'continueWatching', 'nextUp'],
          shown: const ['nextUp', 'continueWatching'],
        ),
        ['arrDownloading', 'nextUp', 'continueWatching'],
      );
      // With every row listed the new order is simply the one saved.
      final all = [...kHomeRows.reversed];
      expect(homeRowsMoved(kHomeRows, shown: all), all);
    });

    test('the switches are on until turned off, and survive a restart', () {
      expect(const Prefs().showArrDownloading, isTrue);
      expect(const Prefs().showArrComingUp, isTrue);
      final back = Prefs.fromJson(
        jsonDecode(
          jsonEncode(
            const Prefs(
              showArrDownloading: false,
              showArrComingUp: false,
            ).toJson(),
          ),
        ),
      );
      expect(back.showArrDownloading, isFalse);
      expect(back.showArrComingUp, isFalse);
      // Settings saved before the rows existed.
      final old = Prefs.fromJson({'homeRowOrder': before});
      expect(old.showArrDownloading, isTrue);
      expect(old.showArrComingUp, isTrue);
      expect(homeRowsInOrder(old.homeRowOrder), kHomeRows);
    });
  });

  group('what Downloading Now makes of the queue', () {
    test('one card for a show, however many episodes are downloading', () {
      final titles = arrHomeDownloads([
        _q(ArrKind.sonarr, _episodeDownload(1, episode: 5)),
        _q(ArrKind.radarr, _movieDownload(1)),
        _q(ArrKind.sonarr, _episodeDownload(2, episode: 6)),
        _q(ArrKind.sonarr, _episodeDownload(3, seriesId: 8, show: 'Andor')),
      ]);
      expect(
        [for (final t in titles) (t.kind, t.titleId, t.title, t.items.length)],
        [
          (ArrKind.sonarr, 7, 'Severance', 2),
          (ArrKind.radarr, 3, 'Dune', 1),
          (ArrKind.sonarr, 8, 'Andor', 1),
        ],
      );
      // The first entry of the queue's own order speaks for the title.
      expect(titles.first.lead.episodeCode, 'S02E05');
    });

    test('a movie and a show with the same id are two titles', () {
      final titles = arrHomeDownloads([
        _q(ArrKind.sonarr, _episodeDownload(1, seriesId: 3)),
        _q(ArrKind.radarr, _movieDownload(1, movieId: 3)),
      ]);
      expect(titles, hasLength(2));
    });

    test('a download the app couldn\'t match is left to Activity', () {
      final titles = arrHomeDownloads([
        _q(ArrKind.radarr, {
          'id': 9,
          'title': 'Unknown.Release',
          'status': 'completed',
          'size': 10,
          'sizeleft': 0,
        }),
        // Matched to a title the app no longer sends.
        _q(ArrKind.radarr, {'id': 10, 'title': 'X', 'movieId': 4}),
        // A title, with nothing to say which of the app's it is.
        _q(ArrKind.radarr, {
          'id': 11,
          'title': 'Y',
          'movie': {'title': 'Y'},
        }),
      ]);
      expect(titles, isEmpty);
    });

    test('a season pack counts once, not once for each episode', () {
      // One 3000-byte download listed for three episodes, a third done.
      final pack = arrHomeDownloads([
        for (var e = 1; e <= 3; e++)
          _q(
            ArrKind.sonarr,
            _episodeDownload(
              e,
              episode: e,
              downloadId: 'pack',
              size: 3000,
              left: 2000,
            ),
          ),
      ]).single;
      expect(pack.items, hasLength(3));
      expect(pack.downloads, hasLength(1));
      expect(pack.progress, closeTo(1 / 3, 0.001));
    });

    test('progress is of everything coming, by size', () {
      final t = arrHomeDownloads([
        _q(ArrKind.sonarr, _episodeDownload(1, size: 1000, left: 0)),
        _q(ArrKind.sonarr, _episodeDownload(2, size: 3000, left: 2000)),
      ]).single;
      expect(t.progress, 0.5);
      // A download whose size isn't known yet.
      final unknown = arrHomeDownloads([
        _q(ArrKind.radarr, _movieDownload(1, size: 0, left: 0)),
      ]).single;
      expect(unknown.progress, 0);
    });

    test('it finishes when the last of what\'s downloading does', () {
      final soon = _now.add(const Duration(minutes: 5));
      final later = _now.add(const Duration(minutes: 40));
      final t = arrHomeDownloads([
        _q(ArrKind.sonarr, _episodeDownload(1, done: soon)),
        _q(ArrKind.sonarr, _episodeDownload(2, done: later)),
        // Not downloading: its time says nothing.
        _q(
          ArrKind.sonarr,
          _episodeDownload(
            3,
            status: 'paused',
            done: _now.add(const Duration(hours: 9)),
          ),
        ),
      ]).single;
      expect(t.finishes, later);
      final none = arrHomeDownloads([
        _q(ArrKind.radarr, _movieDownload(1)),
      ]).single;
      expect(none.finishes, isNull);
    });
  });

  group('what Coming This Week makes of the calendar', () {
    final week = arrHomeWeek(_now);
    ArrCalendarEntry ep(
      DateTime date, {
      int seriesId = 7,
      String code = 'S02E05',
      bool monitored = true,
      bool hasFile = false,
    }) => ArrCalendarEntry(
      kind: ArrKind.sonarr,
      date: date,
      title: 'Show $seriesId',
      episodeCode: code,
      seriesId: seriesId,
      monitored: monitored,
      hasFile: hasFile,
    );
    ArrCalendarEntry movie(
      DateTime date, {
      int movieId = 3,
      ArrRelease release = ArrRelease.digital,
    }) => ArrCalendarEntry(
      kind: ArrKind.radarr,
      date: date,
      title: 'Movie $movieId',
      release: release,
      movieId: movieId,
    );

    test('the week is today and the six days after, by the calendar', () {
      expect(week.start, DateTime(2026, 11, 21));
      expect(week.end, DateTime(2026, 11, 28));
      // Across a month's end.
      final w = arrHomeWeek(DateTime(2026, 12, 29, 23, 59));
      expect(w.start, DateTime(2026, 12, 29));
      expect(w.end, DateTime(2027, 1, 5));
      // Across the night the clocks go forward in the US: still midnight,
      // not an hour past it. (Only tells where the clocks change that week.)
      expect(arrHomeWeek(DateTime(2027, 3, 10)).end, DateTime(2027, 3, 17));
    });

    test('only what\'s due in the week, monitored and not here yet', () {
      final due = arrHomeComingUp([
        ep(DateTime(2026, 11, 20, 23, 59), seriesId: 1), // yesterday
        ep(DateTime(2026, 11, 21, 0, 0), seriesId: 2), // today, already aired
        ep(DateTime(2026, 11, 27, 23, 59), seriesId: 3), // the last day
        ep(DateTime(2026, 11, 28, 0, 0), seriesId: 4), // a week from today
        ep(DateTime(2026, 11, 22), seriesId: 5, monitored: false),
        ep(DateTime(2026, 11, 22), seriesId: 6, hasFile: true),
      ], week);
      expect([for (final r in due) r.first.seriesId], [2, 3]);
    });

    test('one card for a show, at its first episode, counting the rest', () {
      final due = arrHomeComingUp([
        ep(DateTime(2026, 11, 25, 20), code: 'S02E07'),
        ep(DateTime(2026, 11, 23, 20), code: 'S02E05'),
        ep(DateTime(2026, 11, 24, 20), code: 'S02E06'),
        ep(DateTime(2026, 11, 22, 20), seriesId: 8, code: 'S01E01'),
      ], week);
      expect(
        [for (final r in due) (r.first.seriesId, r.first.episodeCode, r.more)],
        [(8, 'S01E01', 0), (7, 'S02E05', 2)],
      );
    });

    test('a movie out twice in the week is one card, with no count', () {
      final due = arrHomeComingUp([
        movie(DateTime(2026, 11, 26), release: ArrRelease.digital),
        movie(DateTime(2026, 11, 22), release: ArrRelease.cinemas),
      ], week);
      expect(due, hasLength(1));
      expect(due.single.first.release, ArrRelease.cinemas);
      expect(due.single.more, 0);
    });

    test('a download leaving the queue is what asks for the week again', () {
      final a = _q(ArrKind.sonarr, _episodeDownload(1));
      final b = _q(ArrKind.radarr, _movieDownload(1));
      final b2 = _q(ArrKind.radarr, _movieDownload(1, left: 10));
      expect(arrQueueItemLeft([a, b], [a]), isTrue);
      expect(arrQueueItemLeft([a, b], const []), isTrue);
      // The same id in the other app's queue is another download.
      expect(arrQueueItemLeft([a], [b]), isTrue);
      // Progress, and a download starting, change nothing that's due.
      expect(arrQueueItemLeft([a, b], [b2, a]), isFalse);
      expect(arrQueueItemLeft([a], [a, b]), isFalse);
      expect(arrQueueItemLeft(const [], [a]), isFalse);
    });

    test('but not one whose app gave no queue this time', () {
      final a = _q(ArrKind.sonarr, _episodeDownload(1));
      final b = _q(ArrKind.radarr, _movieDownload(1));
      // Sonarr didn't answer: its download is missing, not known to be done.
      expect(
        arrQueueItemLeft([a, b], [b], unanswered: {ArrKind.sonarr}),
        isFalse,
      );
      expect(
        arrQueueItemLeft([a, b], const [], unanswered: ArrKind.values.toSet()),
        isFalse,
      );
      // Radarr did, and its download is gone.
      expect(
        arrQueueItemLeft([a, b], const [], unanswered: {ArrKind.sonarr}),
        isTrue,
      );
    });
  });

  group('what a row keeps for an app that didn\'t answer', () {
    const s = ArrKind.sonarr;
    const r = ArrKind.radarr;
    ArrLastKnown<(ArrKind, int)> known({
      int patience = 2,
      bool ordered = true,
    }) => ArrLastKnown(
      kindOf: (i) => i.$1,
      patience: patience,
      order: ordered ? (a, b) => a.$2.compareTo(b.$2) : null,
    );
    ArrMerged<(ArrKind, int)> answer(
      List<(ArrKind, int)> items, {
      Set<ArrKind> silent = const {},
    }) => ArrMerged(items, {for (final k in silent) k: 'down'});

    test('its last answer, back in the row\'s order', () {
      final k = known();
      expect(k.shown, isEmpty);
      expect(k.of(answer([(s, 1), (r, 2), (s, 3)])), [(s, 1), (r, 2), (s, 3)]);
      // Sonarr silent: Radarr's news, with Sonarr's last among it.
      final mixed = [(r, 0), (s, 1), (r, 2), (s, 3)];
      expect(k.of(answer([(r, 0), (r, 2)], silent: {s})), mixed);
      // Which stands while the next answer is on its way.
      expect(k.shown, mixed);
    });

    test('after what did arrive, for a row with no order of its own', () {
      final k = known(ordered: false);
      k.of(answer([(s, 9), (r, 2)]));
      expect(k.of(answer([(r, 5)], silent: {s})), [(r, 5), (s, 9)]);
    });

    test('for so many answers in a row, and no longer', () {
      final k = known(patience: 2);
      k.of(answer([(s, 1), (r, 2)]));
      expect(k.of(answer([(r, 2)], silent: {s})), [(s, 1), (r, 2)]);
      expect(k.of(answer([(r, 2)], silent: {s})), [(s, 1), (r, 2)]);
      expect(k.of(answer([(r, 2)], silent: {s})), [(r, 2)]);
      // Gone for good, until the app says otherwise.
      expect(k.of(answer([(r, 2)], silent: {s})), [(r, 2)]);
      expect(k.of(answer([(s, 4), (r, 2)])), [(s, 4), (r, 2)]);
    });

    test('an answer in between starts the count again', () {
      final k = known(patience: 2);
      k.of(answer([(s, 1)]));
      k.of(answer(const [], silent: {s}));
      k.of(answer(const [], silent: {s}));
      expect(k.of(answer([(s, 1)])), [(s, 1)]);
      expect(k.of(answer(const [], silent: {s})), [(s, 1)]);
      expect(k.of(answer(const [], silent: {s})), [(s, 1)]);
      expect(k.of(answer(const [], silent: {s})), isEmpty);
    });

    test('the same answer seen again counts once', () {
      final k = known(patience: 1);
      k.of(answer([(s, 1)]));
      // A row is built many times over with the answer it has.
      final missed = answer(const [], silent: {s});
      for (var i = 0; i < 5; i++) {
        expect(k.of(missed), [(s, 1)]);
      }
      expect(k.of(answer(const [], silent: {s})), isEmpty);
    });

    test('nothing for an app that answered with nothing', () {
      final k = known();
      k.of(answer([(s, 1), (r, 2)]));
      // Sonarr's queue is empty now, and that's its last word.
      expect(k.of(answer([(r, 2)])), [(r, 2)]);
      expect(k.of(answer([(r, 2)], silent: {s})), [(r, 2)]);
    });

    test('both apps\' when neither answers', () {
      final k = known();
      k.of(answer([(s, 1), (r, 2)]));
      expect(k.of(answer(const [], silent: {s, r})), [(s, 1), (r, 2)]);
    });
  });

  group('Downloading Now', () {
    testWidgets('a card for each title, with how far along it is', (t) async {
      final sonarr = _App(
        queue: [
          _episodeDownload(
            1,
            left: 250,
            done: _now.add(const Duration(minutes: 12)),
          ),
          _episodeDownload(2, seriesId: 8, show: 'Andor', episode: 1),
          _episodeDownload(3, seriesId: 8, show: 'Andor', episode: 2),
        ],
      );
      final radarr = _App(
        queue: [_movieDownload(1, status: 'queued', left: 1000)],
      );
      await _rows(t, sonarr: sonarr, radarr: radarr);

      expect(find.text('Downloading Now'), findsOneWidget);
      // One episode: which, how far, how long.
      expect(find.text('S02E05 · 75% · 12m left'), findsOneWidget);
      // Two of a show: how many, no single time to give.
      expect(find.text('Andor'), findsOneWidget);
      expect(find.text('2 episodes · 75%'), findsOneWidget);
      // Not downloading yet: the word, not a percentage.
      expect(find.text('Dune'), findsOneWidget);
      expect(find.text('Queued'), findsOneWidget);
      expect(find.byType(ArrPosterBar), findsNWidgets(3));
      // Nothing wrong with any of them: each line in a card's usual color.
      final quiet = Theme.of(
        t.element(find.text('Dune')),
      ).colorScheme.onSurfaceVariant;
      for (final line in ['S02E05 · 75% · 12m left', '2 episodes · 75%', 'Queued']) {
        expect(t.widget<Text>(find.text(line)).style!.color, quiet);
      }
    });

    testWidgets('a download that needs help says so, in its color', (t) async {
      final radarr = _App(
        queue: [
          _movieDownload(
            1,
            status: 'completed',
            left: 0,
            state: 'importBlocked',
            tracked: 'warning',
          ),
        ],
      );
      await _rows(t, radarr: radarr);
      final line = t.widget<Text>(find.text('Import Blocked'));
      expect(line.style!.color, arrWarningColor);
      // The title's own line stays as any card's.
      expect(t.widget<Text>(find.text('Dune')).style!.color, isNot(arrWarningColor));
    });

    testWidgets('a time already past isn\'t given', (t) async {
      final radarr = _App(
        queue: [
          _movieDownload(1, done: _now.subtract(const Duration(minutes: 3))),
        ],
      );
      await _rows(t, radarr: radarr);
      expect(find.text('50%'), findsOneWidget);
    });

    testWidgets('isn\'t there with nothing downloading', (t) async {
      await _rows(t, sonarr: _App(), radarr: _App());
      expect(find.text('Downloading Now'), findsNothing);
      expect(find.text('top of home'), findsOneWidget);
      // Nothing in its place: Home's own rows close up.
      expect(
        t.getTopLeft(find.text('rest of home')).dy,
        t.getBottomLeft(find.text('top of home')).dy,
      );
    });

    testWidgets('isn\'t there, and says nothing, when the apps are down', (
      t,
    ) async {
      final sonarr = _App()..down = true;
      await _rows(t, sonarr: sonarr);
      expect(find.text('Downloading Now'), findsNothing);
      expect(find.text('Coming This Week'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('a card opens its title, See All the queue', (t) async {
      final sonarr = _App(queue: [_episodeDownload(1)]);
      final radarr = _App(queue: [_movieDownload(1)]);
      await _rows(t, sonarr: sonarr, radarr: radarr);

      await t.tap(_card('Severance'));
      await _settle(t);
      expect(find.text('page: series 7'), findsOneWidget);
      _router.pop();
      await _settle(t);

      await t.tap(_card('Dune'));
      await _settle(t);
      expect(find.text('page: movie 3'), findsOneWidget);
      _router.pop();
      await _settle(t);

      await t.tap(_seeAll('Downloading Now'));
      await _settle(t);
      expect(find.text('manage: activity'), findsOneWidget);
      // Over Home, not in its place: Back comes back to it.
      _router.pop();
      await _settle(t);
      expect(find.text('top of home'), findsOneWidget);
      expect(find.text('manage: activity'), findsNothing);
    });

    testWidgets('an app that misses an answer or two keeps its card', (
      t,
    ) async {
      final sonarr = _App(queue: [_episodeDownload(1)]);
      final radarr = _App(queue: [_movieDownload(1)]);
      await _rows(t, sonarr: sonarr, radarr: radarr);
      double at(String title) => t.getTopLeft(find.text(title)).dx;
      // The closest to finishing first.
      expect(at('Severance'), lessThan(at('Dune')));

      Future<void> poll() async {
        await t.pump(const Duration(seconds: 15));
        await _settle(t);
      }

      sonarr.down = true;
      radarr.queue = [_movieDownload(1, left: 100)];
      await poll();
      // Radarr's news is shown, and Sonarr's card is as it was, in its
      // place among them.
      expect(find.text('90%'), findsOneWidget);
      expect(find.text('S02E05 · 75%'), findsOneWidget);
      expect(at('Dune'), lessThan(at('Severance')));
      // Ahead of a movie that's further from done, too.
      radarr.queue = [_movieDownload(1, left: 500)];
      await poll();
      expect(find.text('50%'), findsOneWidget);
      expect(at('Severance'), lessThan(at('Dune')));
      // Silent a third time: its numbers are too old to show.
      await poll();
      expect(find.text('Severance'), findsNothing);
      expect(find.text('Dune'), findsOneWidget);
      // And back as soon as it answers.
      sonarr.down = false;
      await poll();
      expect(find.text('Severance'), findsOneWidget);
    });

    testWidgets('and the row stays up when neither app answers once', (
      t,
    ) async {
      final sonarr = _App(queue: [_episodeDownload(1)]);
      final radarr = _App(queue: [_movieDownload(1)]);
      await _rows(t, sonarr: sonarr, radarr: radarr);
      sonarr.down = radarr.down = true;
      await t.pump(const Duration(seconds: 15));
      await _settle(t);
      expect(sonarr.count('queue'), 2);
      expect(find.text('Downloading Now'), findsOneWidget);
      expect(find.text('Severance'), findsOneWidget);
      expect(find.text('Dune'), findsOneWidget);
      // Still looking as often as with downloads showing.
      await t.pump(const Duration(seconds: 15));
      await _settle(t);
      expect(sonarr.count('queue'), 3);
    });

    testWidgets('keeps itself current, sooner with something downloading', (
      t,
    ) async {
      final radarr = _App();
      await _rows(t, radarr: radarr);
      final first = radarr.count('queue');
      expect(first, 1);

      // Empty: a look once a minute.
      await t.pump(const Duration(seconds: 50));
      await _settle(t);
      expect(radarr.count('queue'), first);
      radarr.queue = [_movieDownload(1)];
      await t.pump(const Duration(seconds: 10));
      await _settle(t);
      expect(radarr.count('queue'), first + 1);
      expect(find.text('Dune'), findsOneWidget);

      // With a download showing: every 15 seconds.
      final shown = radarr.count('queue');
      radarr.queue = [_movieDownload(1, left: 100)];
      await t.pump(const Duration(seconds: 15));
      await _settle(t);
      expect(radarr.count('queue'), shown + 1);
      expect(find.text('90%'), findsOneWidget);

      // Done: the row goes with it.
      radarr.queue = [];
      await t.pump(const Duration(seconds: 15));
      await _settle(t);
      expect(find.text('Downloading Now'), findsNothing);
    });
  });

  group('Coming This Week', () {
    testWidgets('a poster for each title due, soonest first', (t) async {
      final sonarr = _App(
        calendar: [
          _airing(1, DateTime(2026, 11, 22, 20)),
          _airing(2, DateTime(2026, 11, 24, 20), episode: 6),
          _airing(
            3,
            DateTime(2026, 11, 21, 21),
            seriesId: 8,
            show: 'Andor',
            episode: 1,
            title: 'Kassa',
          ),
          // Already here.
          _airing(4, DateTime(2026, 11, 23, 20), seriesId: 9, show: 'Lost',
              hasFile: true),
        ],
      );
      final radarr = _App(
        calendar: [
          _release(3, 'Dune', digital: _day(2026, 11, 25)),
          _release(4, 'Heat', inCinemas: _day(2026, 11, 27)),
        ],
      );
      await _rows(t, sonarr: sonarr, radarr: radarr);

      expect(find.text('Coming This Week'), findsOneWidget);
      // An episode alone: its number and name.
      expect(find.text('S02E01 · Kassa'), findsOneWidget);
      // Two of a show in the week.
      expect(find.text('S02E05 +1 More'), findsOneWidget);
      expect(find.text('Digital Release'), findsOneWidget);
      expect(find.text('In Cinemas'), findsOneWidget);
      expect(find.text('Lost'), findsNothing);
      // Each says its day: today, tomorrow, then the weekday.
      final days = [
        for (final c in t.widgetList<ArrChip>(find.byType(ArrChip))) c.label,
      ];
      expect(days, ['Today', 'Tomorrow', 'Wednesday', 'Friday']);
      final order = [
        for (final title in ['Andor', 'Severance', 'Dune', 'Heat'])
          t.getTopLeft(find.text(title)).dx,
      ];
      expect(order, [...order]..sort());
    });

    testWidgets('asks for the week from today, monitored titles only', (
      t,
    ) async {
      final sonarr = _App();
      final radarr = _App();
      await _rows(t, sonarr: sonarr, radarr: radarr);
      expect(sonarr.count('calendar'), 1);
      expect(radarr.count('calendar'), 1);
      // Sonarr by the moment, from this midnight to the one a week on.
      final shows = sonarr.query['calendar']!;
      expect(shows['start'], DateTime(2026, 11, 21).toUtc().toIso8601String());
      expect(shows['end'], DateTime(2026, 11, 28).toUtc().toIso8601String());
      expect(shows['unmonitored'], 'false');
      // Radarr by the day, which it keeps as UTC's.
      final movies = radarr.query['calendar']!;
      expect(movies['start'], DateTime.utc(2026, 11, 21).toIso8601String());
      expect(movies['end'], DateTime.utc(2026, 11, 28).toIso8601String());
      expect(movies['unmonitored'], 'false');
      expect(find.text('Coming This Week'), findsNothing);
    });

    testWidgets('a poster opens its title, See All the Calendar', (t) async {
      final sonarr = _App(calendar: [_airing(1, DateTime(2026, 11, 22, 20))]);
      final radarr = _App(
        calendar: [_release(3, 'Dune', digital: _day(2026, 11, 25))],
      );
      await _rows(t, sonarr: sonarr, radarr: radarr);

      await t.tap(_card('Severance'));
      await _settle(t);
      expect(find.text('page: series 7'), findsOneWidget);
      _router.pop();
      await _settle(t);

      await t.tap(_card('Dune'));
      await _settle(t);
      expect(find.text('page: movie 3'), findsOneWidget);
      _router.pop();
      await _settle(t);

      await t.tap(_seeAll('Coming This Week'));
      await _settle(t);
      expect(find.text('manage: calendar'), findsOneWidget);
      // Over Home, not in its place: Back comes back to it.
      _router.pop();
      await _settle(t);
      expect(find.text('top of home'), findsOneWidget);
      expect(find.text('manage: calendar'), findsNothing);
    });

    /// Lets [time] pass, then the answers arrive.
    Future<void> after(WidgetTester t, Duration time) async {
      await t.pump(time);
      await _settle(t);
    }

    List<String> days(WidgetTester t) => [
      for (final c in t.widgetList<ArrChip>(find.byType(ArrChip))) c.label,
    ];

    testWidgets('looks again every quarter of an hour', (t) async {
      final radarr = _App(
        calendar: [_release(3, 'Dune', digital: _day(2026, 11, 25))],
      );
      await _rows(t, radarr: radarr);
      expect(radarr.count('calendar'), 1);
      await after(t, const Duration(minutes: 14));
      expect(radarr.count('calendar'), 1);

      // Something added to the week since.
      radarr.calendar = [
        ...radarr.calendar,
        _release(4, 'Heat', inCinemas: _day(2026, 11, 27)),
      ];
      await after(t, const Duration(minutes: 1));
      expect(radarr.count('calendar'), 2);
      expect(find.text('Heat'), findsOneWidget);
      expect(find.text('Dune'), findsOneWidget);
    });

    testWidgets('an app that didn\'t answer is asked again a minute on', (
      t,
    ) async {
      final sonarr = _App(calendar: [_airing(1, DateTime(2026, 11, 22, 20))])
        ..down = true;
      await _rows(t, sonarr: sonarr);
      expect(find.text('Coming This Week'), findsNothing);
      expect(sonarr.count('calendar'), 1);

      sonarr.down = false;
      await after(t, const Duration(minutes: 1));
      expect(sonarr.count('calendar'), 2);
      expect(find.text('Severance'), findsOneWidget);
      // It answered: no hurry any more.
      await after(t, const Duration(minutes: 5));
      expect(sonarr.count('calendar'), 2);
    });

    testWidgets('and keeps its posters for a few tries', (t) async {
      final sonarr = _App(calendar: [_airing(1, DateTime(2026, 11, 22, 20))]);
      final radarr = _App(
        calendar: [_release(3, 'Dune', digital: _day(2026, 11, 25))],
      );
      await _rows(t, sonarr: sonarr, radarr: radarr);
      expect(days(t), ['Tomorrow', 'Wednesday']);

      sonarr.down = true;
      await after(t, const Duration(minutes: 15));
      expect(sonarr.count('calendar'), 2);
      expect(days(t), ['Tomorrow', 'Wednesday']);
      // Asked every minute now. Five tries in all, its poster there
      // throughout.
      for (var i = 0; i < 4; i++) {
        await after(t, const Duration(minutes: 1));
        expect(find.text('Severance'), findsOneWidget);
      }
      expect(sonarr.count('calendar'), 6);
      // The other app isn't asked any less for it.
      expect(radarr.count('calendar'), 6);
      // A sixth: what it said last is too old to stand.
      await after(t, const Duration(minutes: 1));
      expect(find.text('Severance'), findsNothing);
      expect(find.text('Dune'), findsOneWidget);

      sonarr.down = false;
      await after(t, const Duration(minutes: 1));
      expect(days(t), ['Tomorrow', 'Wednesday']);
    });

    testWidgets('a queue that couldn\'t be read doesn\'t ask for the week', (
      t,
    ) async {
      final radarr = _App(
        queue: [_movieDownload(1)],
        calendar: [_release(3, 'Dune', digital: _day(2026, 11, 21))],
      );
      await _rows(t, radarr: radarr);
      expect(radarr.count('calendar'), 1);

      radarr.down = true;
      await after(t, const Duration(seconds: 15));
      expect(radarr.count('queue'), 2);
      // The download isn't known to have come in: the week stands, and so
      // do both rows.
      expect(radarr.count('calendar'), 1);
      expect(find.text('Digital Release'), findsOneWidget);
      expect(find.text('Downloading Now'), findsOneWidget);
    });

    testWidgets('finds out that it\'s tomorrow', (t) async {
      final sonarr = _App(
        calendar: [
          _airing(1, DateTime(2026, 11, 22, 20)),
          _airing(2, DateTime(2026, 11, 21, 21), seriesId: 8, show: 'Andor'),
        ],
      );
      await _rows(t, sonarr: sonarr);
      expect(days(t), ['Today', 'Tomorrow']);

      // Past midnight.
      arrHomeNow = () => DateTime(2026, 11, 22, 0, 10);
      await t.pump(const Duration(minutes: 15));
      // At once, from what it has: yesterday's is off the row, and
      // tomorrow's is today's. The row never left.
      expect(find.text('Coming This Week'), findsOneWidget);
      expect(days(t), ['Today']);
      expect(find.text('Andor'), findsNothing);
      expect(find.text('Severance'), findsOneWidget);

      // And the new week is what's asked for.
      await _settle(t);
      final asked = sonarr.query['calendar']!;
      expect(asked['start'], DateTime(2026, 11, 22).toUtc().toIso8601String());
      expect(asked['end'], DateTime(2026, 11, 29).toUtc().toIso8601String());
      expect(days(t), ['Today']);
    });

    testWidgets('a title leaves once its download has come in', (t) async {
      final radarr = _App(
        queue: [_movieDownload(1)],
        calendar: [_release(3, 'Dune', digital: _day(2026, 11, 21))],
      );
      await _rows(t, radarr: radarr);
      expect(find.text('Digital Release'), findsOneWidget);
      expect(radarr.count('calendar'), 1);

      // Still downloading: the week isn't asked for again.
      radarr.queue = [_movieDownload(1, left: 100)];
      await t.pump(const Duration(seconds: 15));
      await _settle(t);
      expect(radarr.count('calendar'), 1);

      // Imported: out of the queue, and on disk.
      radarr.queue = [];
      radarr.calendar = [
        _release(3, 'Dune', digital: _day(2026, 11, 21), hasFile: true),
      ];
      await t.pump(const Duration(seconds: 15));
      await _settle(t);
      expect(radarr.count('calendar'), 2);
      expect(find.text('Coming This Week'), findsNothing);
      expect(find.text('Downloading Now'), findsNothing);
    });
  });

  group('Manage opens on the tab asked for', () {
    Future<void> open(WidgetTester t, String? tab) async {
      t.view.physicalSize = const Size(1200, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            sonarrClientProvider.overrideWithValue(null),
            radarrClientProvider.overrideWithValue(
              RadarrClient(
                'http://r',
                'k',
                dio: Dio()..httpClientAdapter = _App(),
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(const Color(0xFF8AB4F8)),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ArrScreen(tab: tab),
          ),
        ),
      );
      await _settle(t);
    }

    int shown(WidgetTester t) =>
        DefaultTabController.of(t.element(find.byType(TabBar))).index;

    testWidgets('Activity from Downloading Now', (t) async {
      await open(t, 'activity');
      expect(shown(t), 2);
    });

    testWidgets('the Calendar from Coming This Week', (t) async {
      await open(t, 'calendar');
      expect(shown(t), 1);
    });

    testWidgets('the Library otherwise', (t) async {
      await open(t, null);
      expect(shown(t), 0);
      await open(t, 'nonsense');
      expect(shown(t), 0);
    });

    testWidgets('and the app\'s own address for Manage passes it on', (
      t,
    ) async {
      final scope = ProviderContainer(
        overrides: [
          sessionControllerProvider.overrideWith(_SignedOut.new),
          splashReadyProvider.overrideWith((ref) async {}),
        ],
      );
      addTearDown(scope.dispose);
      final router = scope.read(routerProvider);
      GoRoute? under(List<RouteBase> routes) {
        for (final r in routes) {
          if (r is GoRoute && r.path == '/arr') return r;
          final below = under(r.routes);
          if (below != null) return below;
        }
        return null;
      }

      await t.pumpWidget(const SizedBox());
      ArrScreen at(String address) {
        final page = under(router.configuration.routes)!.pageBuilder!(
          t.element(find.byType(SizedBox)),
          GoRouterState(
            router.configuration,
            uri: Uri.parse(address),
            matchedLocation: '/arr',
            fullPath: '/arr',
            pathParameters: const {},
            pageKey: const ValueKey('arr'),
          ),
        );
        return (page as CustomTransitionPage).child as ArrScreen;
      }

      expect(at('/arr?tab=activity').tab, 'activity');
      expect(at('/arr?tab=calendar').tab, 'calendar');
      expect(at('/arr').tab, isNull);
    });
  });

  group('Home', () {
    Future<void> open(
      WidgetTester t, {
      bool connected = true,
      Prefs prefs = const Prefs(),
    }) async {
      t.view.physicalSize = const Size(1360, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      Future<List<BaseItemDto>> none(Ref ref) async => const [];
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            preferencesProvider.overrideWith(
              () => _FakePrefs(prefs.copyWith(homeBanner: 'hide')),
            ),
            continueWatchingProvider.overrideWith(none),
            nextUpItemsProvider.overrideWith(none),
            latestItemsProvider.overrideWith(none),
            heroItemsProvider.overrideWith(none),
            userViewsProvider.overrideWith(none),
            genresProvider.overrideWith(none),
            sonarrClientProvider.overrideWithValue(null),
            radarrClientProvider.overrideWithValue(
              connected
                  ? RadarrClient(
                      'http://r',
                      'k',
                      dio: Dio()..httpClientAdapter = _App(),
                    )
                  : null,
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(const Color(0xFF8AB4F8)),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const HomeScreen(),
          ),
        ),
      );
      await _settle(t);
    }

    // In the page or not, whether or not there's anything for them to show:
    // a row with nothing in it takes no room, which a finder passes over.
    final downloading = find.byType(ArrDownloadingRow, skipOffstage: false);
    final comingUp = find.byType(ArrComingUpRow, skipOffstage: false);

    testWidgets('has both rows with an app connected', (t) async {
      await open(t);
      expect(downloading, findsOneWidget);
      expect(comingUp, findsOneWidget);
    });

    testWidgets('and on a TV as well', (t) async {
      isTvDevice = true;
      addTearDown(() => isTvDevice = false);
      await open(t);
      expect(downloading, findsOneWidget);
      expect(comingUp, findsOneWidget);
    });

    testWidgets('leaves out the one that\'s switched off', (t) async {
      await open(t, prefs: const Prefs(showArrDownloading: false));
      expect(downloading, findsNothing);
      expect(comingUp, findsOneWidget);

      await t.pumpWidget(const SizedBox());
      await open(t, prefs: const Prefs(showArrComingUp: false));
      expect(downloading, findsOneWidget);
      expect(comingUp, findsNothing);
    });

    testWidgets('has neither with no app connected', (t) async {
      await open(t, connected: false);
      expect(downloading, findsNothing);
      expect(comingUp, findsNothing);
    });
  });

  group('Home Layout', () {
    Future<ProviderContainer> open(
      WidgetTester t, {
      required bool connected,
      Prefs prefs = const Prefs(),
    }) async {
      t.view.physicalSize = const Size(412, 892);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      late ProviderContainer container;
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            preferencesProvider.overrideWith(() => _FakePrefs(prefs)),
            sonarrClientProvider.overrideWithValue(null),
            radarrClientProvider.overrideWithValue(
              connected
                  ? RadarrClient(
                      'http://r',
                      'k',
                      dio: Dio()..httpClientAdapter = _App(),
                    )
                  : null,
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(const Color(0xFF8AB4F8)),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                return const HomeLayoutScreen();
              },
            ),
          ),
        ),
      );
      await t.pump();
      await t.pump();
      return container;
    }

    /// The rows listed, top to bottom: the tiles that can be dragged.
    List<String> listed(WidgetTester t) => [
      for (final tile in t.widgetList<ListTile>(
        find.descendant(
          of: find.byType(ReorderableListView),
          matching: find.byType(ListTile),
        ),
      ))
        (tile.title! as Text).data!,
    ];

    Prefs saved(ProviderContainer c) =>
        c.read(preferencesProvider).requireValue;

    testWidgets('lists the two rows with an app connected', (t) async {
      await open(t, connected: true);
      expect(listed(t), [
        'Continue Watching',
        'Next Up',
        'Downloading Now',
        'Recently Added',
        'Coming This Week',
        'My Media',
      ]);
    });

    testWidgets('and on a TV as well', (t) async {
      isTvDevice = true;
      addTearDown(() => isTvDevice = false);
      await open(t, connected: true);
      expect(listed(t), containsAll(['Downloading Now', 'Coming This Week']));
    });

    testWidgets('leaves them out with neither app connected', (t) async {
      await open(t, connected: false);
      expect(listed(t), [
        'Continue Watching',
        'Next Up',
        'Recently Added',
        'My Media',
      ]);
    });

    testWidgets('each has its own switch', (t) async {
      final c = await open(t, connected: true);
      Finder toggle(String row) => find.descendant(
        of: find.widgetWithText(ListTile, row),
        matching: find.byType(Switch),
      );
      expect(t.widget<Switch>(toggle('Downloading Now')).value, isTrue);

      await t.tap(toggle('Downloading Now'));
      await t.pump();
      expect(saved(c).showArrDownloading, isFalse);
      expect(saved(c).showArrComingUp, isTrue);
      expect(t.widget<Switch>(toggle('Downloading Now')).value, isFalse);

      await t.tap(toggle('Coming This Week'));
      await t.pump();
      expect(saved(c).showArrComingUp, isFalse);
      // Home's own rows weren't touched.
      expect(saved(c).showContinueWatching, isTrue);
      expect(saved(c).showRecentlyAdded, isTrue);
    });

    testWidgets('moving a row without the apps keeps theirs in place', (
      t,
    ) async {
      final c = await open(t, connected: false);
      // My Media, the last of four, dragged to the top.
      final list = t.widget<ReorderableListView>(
        find.byType(ReorderableListView),
      );
      // ignore: deprecated_member_use
      list.onReorder!(3, 0);
      await t.pump();
      expect(saved(c).homeRowOrder, [
        'myMedia',
        'continueWatching',
        'nextUp',
        'arrDownloading',
        'recentlyAdded',
        'arrComingUp',
      ]);
      expect(listed(t), [
        'My Media',
        'Continue Watching',
        'Next Up',
        'Recently Added',
      ]);
    });

    testWidgets('an order from before the rows lists them in their places', (
      t,
    ) async {
      await open(
        t,
        connected: true,
        prefs: const Prefs(
          homeRowOrder: [
            'recentlyAdded',
            'continueWatching',
            'nextUp',
            'myMedia',
          ],
        ),
      );
      expect(listed(t), [
        'Recently Added',
        'Coming This Week',
        'Continue Watching',
        'Next Up',
        'Downloading Now',
        'My Media',
      ]);
    });
  });
}
