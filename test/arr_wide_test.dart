import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fathom/api/arr_client.dart';
import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/screens/arr_calendar_tab.dart';
import 'package:fathom/screens/arr_detail_screens.dart';
import 'package:fathom/screens/arr_screen.dart';
import 'package:fathom/services/tv_mode.dart';
import 'package:fathom/state/arr_providers.dart';
import 'package:fathom/state/preferences.dart';
import 'package:fathom/theme/app_theme.dart';
import 'package:fathom/widgets/app_spinner.dart';
import 'package:fathom/widgets/arr_pane.dart';
import 'package:fathom/widgets/arr_skeletons.dart';
import 'package:fathom/widgets/arr_widgets.dart';
import 'package:fathom/widgets/context_menu.dart';
import 'package:fathom/widgets/media_cards.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

// Manage on a tablet or a computer: a title in a pane beside the lists, the
// Calendar's month, the keyboard, right-click menus, and the lists' shapes
// while they load. And the same section on a phone, where none of that
// applies.

const _wide = Size(1360, 850);
const _tablet = Size(820, 1180);
const _phone = Size(412, 892);

Map<String, dynamic> _movie(int id, String title) => {
  'id': id,
  'title': title,
  'year': 2021,
  'monitored': true,
  'hasFile': false,
  'isAvailable': true,
  'status': 'released',
};

Map<String, dynamic> _page(List<Map<String, dynamic>> records) => {
  'page': 1,
  'pageSize': 50,
  'totalRecords': records.length,
  'records': records,
};

/// A release date as Radarr sends one: midnight UTC of its day.
String _on(DateTime day) =>
    '${DateFormat('yyyy-MM-dd').format(day)}T00:00:00Z';

/// A Radarr whose lists the test can change between reloads.
class _Radarr implements HttpClientAdapter {
  List<Map<String, dynamic>> movies;
  List<Map<String, dynamic>> wanted;
  List<Map<String, dynamic>> calendar;
  List<Map<String, dynamic>> blocklist;
  final Map<String, Duration> slow;

  /// What it answers with an error, for as long as it's in here.
  final Set<String> fail = {};
  final List<String> asked = [];

  /// The last days the calendar was asked for, as sent.
  String? calendarStart;

  _Radarr({
    this.movies = const [],
    this.wanted = const [],
    this.calendar = const [],
    this.blocklist = const [],
    this.slow = const {},
  });

  int count(String path) => asked.where((p) => p == path).length;

  /// As Radarr answers (checked against a real one): the movies with a
  /// release from the start asked for through the end, each compared as a
  /// moment.
  List<Map<String, dynamic>> _between(Uri uri) {
    calendarStart = uri.queryParameters['start'];
    final start = DateTime.parse(uri.queryParameters['start']!);
    final end = DateTime.parse(uri.queryParameters['end']!);
    bool inside(Object? v) {
      if (v is! String) return false;
      final d = DateTime.parse(v);
      return !d.isBefore(start) && !d.isAfter(end);
    }

    return [
      for (final m in calendar)
        if (inside(m['inCinemas']) ||
            inside(m['digitalRelease']) ||
            inside(m['physicalRelease']))
          m,
    ];
  }

  Object? _reply(String path, Uri uri) {
    final one = RegExp(r'^movie/(\d+)$').firstMatch(path);
    if (one != null) {
      final id = int.parse(one.group(1)!);
      return [
        ...movies,
        ...wanted,
      ].firstWhere((m) => m['id'] == id, orElse: () => _movie(id, 'Movie $id'));
    }
    return switch (path) {
      'movie' => movies,
      'calendar' => _between(uri),
      'wanted/missing' => _page(wanted),
      'blocklist' => _page(blocklist),
      'queue' || 'history' || 'wanted/cutoff' => _page(const []),
      'queue/status' => {'totalCount': 0, 'warnings': false, 'errors': false},
      'system/status' => {'version': '1.0.0'},
      _ => const [],
    };
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    final path = o.uri.path.replaceFirst(RegExp(r'^.*/api/v3/'), '');
    asked.add(path);
    final wait = slow[path];
    if (wait != null) await Future<void>.delayed(wait);
    return ResponseBody.fromString(
      jsonEncode(fail.contains(path) ? {'message': 'down'} : _reply(path, o.uri)),
      fail.contains(path) ? 500 : 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

late GoRouter _router;

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

Future<void> _open(
  WidgetTester t,
  _Radarr radarr,
  Size size, {
  Prefs? prefs,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  _router = GoRouter(
    initialLocation: '/arr',
    routes: [
      GoRoute(path: '/arr', builder: (_, _) => const ArrScreen()),
      GoRoute(
        path: '/arr/movie/:id',
        builder: (_, s) =>
            Scaffold(body: Text('page: movie ${s.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/arr/releases',
        builder: (_, s) => const Scaffold(body: Text('page: releases')),
      ),
    ],
  );
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        sonarrClientProvider.overrideWithValue(null),
        radarrClientProvider.overrideWithValue(
          RadarrClient('http://r', 'k', dio: Dio()..httpClientAdapter = radarr),
        ),
        if (prefs != null)
          preferencesProvider.overrideWith(() => _FakePrefs(prefs)),
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

/// Lets the answers arrive and the page draw them. Never pumpAndSettle: the
/// lists' loading shapes shimmer for as long as they show.
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// Past a page's or a menu's way in or out.
Future<void> _move(WidgetTester t) async {
  await _settle(t);
  await t.pump(const Duration(milliseconds: 400));
  await _settle(t);
}

Future<void> _tab(WidgetTester t, String name) async {
  await t.tap(find.widgetWithText(Tab, name));
  await _move(t);
}

Future<void> _rightClick(WidgetTester t, Finder at) async {
  await t.tap(at, buttons: kSecondaryButton);
  await _move(t);
}

Future<void> _key(
  WidgetTester t,
  LogicalKeyboardKey key, {
  bool ctrl = false,
}) async {
  if (ctrl) await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await t.sendKeyEvent(key);
  if (ctrl) await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await _move(t);
}

/// The poster above [title] in the library's grid: the part that's pressed.
Finder _poster(String title) => find.descendant(
  of: find.byWidgetPredicate(
    (w) =>
        w is Column && w.children.any((c) => c is Text && c.data == title),
  ),
  matching: find.byType(HoverPosterArt),
);

/// The title's own page, when one is open over Manage: 'movie 5'.
String? _pageOpen(WidgetTester t) {
  final f = find.textContaining('page: ');
  return f.evaluate().isEmpty
      ? null
      : t.widget<Text>(f).data!.replaceFirst('page: ', '');
}

/// The titles of the open menu's lines, top to bottom.
List<String> _menu(WidgetTester t) => [
  for (final e in t.widgetList<Text>(
    find.descendant(
      of: find.byWidgetPredicate((w) => w is PopupMenuItem),
      matching: find.byType(Text),
    ),
  ))
    e.data!,
];

/// The library's search: the only field there is (a title's facts are
/// text that can be selected, which is the same widget underneath).
bool _searchFocused(WidgetTester t) => t
    .widget<EditableText>(
      find.descendant(
        of: find.byType(TextField),
        matching: find.byType(EditableText),
      ),
    )
    .focusNode
    .hasFocus;

void main() {
  group('how wide the pane is', () {
    test('none until the lists would keep a phone\'s width and more', () {
      expect(arrPaneWidth(412), isNull);
      expect(arrPaneWidth(820), isNull);
      expect(arrPaneWidth(1039), isNull);
      expect(arrPaneWidth(1040), 416);
      expect(arrPaneWidth(1284), closeTo(513.6, 0.01));
      expect(arrPaneWidth(2400), 520);
      // The Calendar's month never falls back to the agenda as a title
      // opens beside it.
      for (var w = 1040.0; w < 2600; w += 20) {
        expect(w - arrPaneWidth(w)! - 1, greaterThanOrEqualTo(600));
      }
    });
  });

  group('a title beside the lists', () {
    testWidgets('opens in the pane on a wide window, and closes', (t) async {
      final radarr = _Radarr(movies: [_movie(5, 'Dune'), _movie(6, 'Heat')]);
      await _open(t, radarr, _wide);
      expect(find.byType(ArrMovieScreen), findsNothing);

      await t.tap(_poster('Dune'));
      await _move(t);
      // Still Manage: the lists stay where they were, the title beside
      // them.
      expect(_pageOpen(t), isNull);
      expect(find.byType(ArrMovieScreen), findsOneWidget);
      expect(t.widget<ArrMovieScreen>(find.byType(ArrMovieScreen)).id, 5);
      expect(find.widgetWithText(Tab, 'Library'), findsOneWidget);
      expect(find.text('Heat'), findsOneWidget);
      final pane = t.getRect(find.byType(ArrMovieScreen));
      expect(pane.right, _wide.width);
      expect(pane.width, arrPaneWidth(_wide.width));

      // Another title takes its place.
      await t.tap(_poster('Heat'));
      await _move(t);
      expect(t.widget<ArrMovieScreen>(find.byType(ArrMovieScreen)).id, 6);

      await t.tap(find.byTooltip('Close'));
      await _move(t);
      expect(find.byType(ArrMovieScreen), findsNothing);
      expect(_pageOpen(t), isNull);
    });

    testWidgets('another server put in use closes the pane', (t) async {
      final radarr = _Radarr(movies: [_movie(5, 'Dune'), _movie(6, 'Heat')]);
      await _open(t, radarr, _wide, prefs: const Prefs());
      await t.tap(_poster('Dune'));
      await _move(t);
      expect(find.byType(ArrMovieScreen), findsOneWidget);
      // Its number means another movie (or none) on the other server.
      final c = ProviderScope.containerOf(
        t.element(find.byType(ArrScreen)),
      );
      await c
          .read(preferencesProvider.notifier)
          .edit(
            (p) => p.copyWith(
              arrActiveServers: {
                'radarr': {'id': 'x', 'name': '4K'},
              },
            ),
          );
      await _move(t);
      expect(find.byType(ArrMovieScreen), findsNothing);
    });

    testWidgets('the pane\'s title can open as a page too', (t) async {
      await _open(t, _Radarr(movies: [_movie(5, 'Dune')]), _wide);
      await t.tap(_poster('Dune'));
      await _move(t);
      await t.tap(find.byTooltip('Open Full Page'));
      await _move(t);
      expect(_pageOpen(t), 'movie 5');
      expect(find.text('page: movie 5'), findsOneWidget);

      // Back to the lists as they were left: the title still beside them.
      _router.pop();
      await _move(t);
      expect(find.byType(ArrMovieScreen), findsOneWidget);
    });

    testWidgets('says whose it is once its header has scrolled away', (
      t,
    ) async {
      // A short window, so there's more of the title than fits.
      await _open(t, _Radarr(movies: [_movie(5, 'Dune')]), const Size(1360, 420));
      await t.tap(_poster('Dune'));
      await _move(t);
      final inBar = find.descendant(
        of: find.byType(NavigationToolbar),
        matching: find.text('Dune'),
      );
      // The header says it at first, the bar doesn't.
      expect(inBar, findsNothing);

      await t.drag(find.byType(ArrMovieScreen), const Offset(0, -900));
      await _move(t);
      expect(inBar, findsOneWidget);
      final shown = t.widget<Opacity>(
        find.ancestor(of: inBar, matching: find.byType(Opacity)).first,
      );
      expect(shown.opacity, 1);
      // On a bar the page can't be read through.
      final bar = t.widget<Material>(
        find
            .descendant(of: find.byType(AppBar), matching: find.byType(Material))
            .first,
      );
      expect(bar.color!.a, 1);
      // Beside the pane's own buttons, which stay.
      expect(find.byTooltip('Close'), findsOneWidget);
      expect(find.byTooltip('Open Full Page'), findsOneWidget);

      await t.drag(find.byType(ArrMovieScreen), const Offset(0, 900));
      await _move(t);
      expect(inBar, findsNothing);
    });

    testWidgets('goes as the window narrows, and is back as it widens', (
      t,
    ) async {
      await _open(t, _Radarr(movies: [_movie(5, 'Dune')]), _wide);
      await t.tap(_poster('Dune'));
      await _move(t);
      t.view.physicalSize = _tablet;
      await _move(t);
      expect(find.byType(ArrMovieScreen), findsNothing);
      expect(_pageOpen(t), isNull);

      t.view.physicalSize = _wide;
      await _move(t);
      expect(t.widget<ArrMovieScreen>(find.byType(ArrMovieScreen)).id, 5);
    });

    testWidgets('but not with a title that has since given way to another', (
      t,
    ) async {
      final radarr = _Radarr(movies: [_movie(5, 'Dune'), _movie(6, 'Heat')]);
      await _open(t, radarr, _wide);
      await t.tap(_poster('Dune'));
      await _move(t);
      t.view.physicalSize = _tablet;
      await _move(t);
      await t.tap(_poster('Heat'));
      await _move(t);
      expect(_pageOpen(t), 'movie 6');
      _router.pop();
      await _move(t);

      // Dune isn't what was last looked at any more.
      t.view.physicalSize = _wide;
      await _move(t);
      expect(find.byType(ArrMovieScreen), findsNothing);
    });

    testWidgets('Back closes it, and stays in Manage', (t) async {
      await _open(t, _Radarr(movies: [_movie(5, 'Dune')]), _wide);
      await t.tap(_poster('Dune'));
      await _move(t);
      await t.binding.handlePopRoute();
      await _move(t);
      expect(find.byType(ArrMovieScreen), findsNothing);
      expect(find.widgetWithText(Tab, 'Library'), findsOneWidget);
      expect(find.text('Dune'), findsOneWidget);
    });

    testWidgets('Back closes it first, then ends picking', (t) async {
      final radarr = _Radarr(wanted: [_movie(9, 'Tenet'), _movie(8, 'Alien')]);
      await _open(t, radarr, _wide);
      await _tab(t, 'Wanted');
      await t.tap(find.text('Tenet'));
      await _move(t);
      expect(find.byType(ArrMovieScreen), findsOneWidget);
      await _rightClick(t, find.text('Alien'));
      await t.tap(find.text('Select'));
      await _move(t);
      expect(find.byType(Checkbox), findsNWidgets(2));

      await t.binding.handlePopRoute();
      await _move(t);
      expect(find.byType(ArrMovieScreen), findsNothing);
      expect(find.byType(Checkbox), findsNWidgets(2));

      await t.binding.handlePopRoute();
      await _move(t);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.widgetWithText(Tab, 'Wanted'), findsOneWidget);
    });

    for (final size in [_phone, _tablet]) {
      testWidgets('opens as a page at ${size.width.round()} wide', (t) async {
        await _open(t, _Radarr(movies: [_movie(5, 'Dune')]), size);
        await t.tap(_poster('Dune'));
        await _move(t);
        expect(_pageOpen(t), 'movie 5');
        expect(find.byType(ArrMovieScreen), findsNothing);
      });
    }

    testWidgets('closes when its title leaves the library', (t) async {
      final radarr = _Radarr(movies: [_movie(5, 'Dune'), _movie(6, 'Heat')]);
      await _open(t, radarr, _wide);
      await t.tap(_poster('Dune'));
      await _move(t);
      expect(find.byType(ArrMovieScreen), findsOneWidget);

      // A reload with the title still there changes nothing.
      await _key(t, LogicalKeyboardKey.f5);
      expect(find.byType(ArrMovieScreen), findsOneWidget);

      // Deleted somewhere else: there's nothing left to show.
      radarr.movies = [_movie(6, 'Heat')];
      await _key(t, LogicalKeyboardKey.f5);
      expect(find.text('Dune'), findsNothing);
      expect(find.byType(ArrMovieScreen), findsNothing);
    });

    testWidgets('stays for a title newer than the library\'s list', (t) async {
      // Added by something else since the list loaded, and already wanted.
      final radarr = _Radarr(
        movies: [_movie(5, 'Dune')],
        wanted: [_movie(9, 'Tenet')],
      );
      await _open(t, radarr, _wide);
      await _tab(t, 'Wanted');
      await t.tap(find.text('Tenet'));
      await _move(t);
      expect(t.widget<ArrMovieScreen>(find.byType(ArrMovieScreen)).id, 9);

      await _key(t, LogicalKeyboardKey.f5);
      expect(find.byType(ArrMovieScreen), findsOneWidget);
    });

    testWidgets('narrowing the window puts the title away', (t) async {
      await _open(t, _Radarr(movies: [_movie(5, 'Dune')]), _wide);
      await t.tap(_poster('Dune'));
      await _move(t);
      expect(find.byType(ArrMovieScreen), findsOneWidget);

      t.view.physicalSize = _tablet;
      await _move(t);
      expect(t.takeException(), isNull);
      expect(find.text('Dune'), findsOneWidget);
      // A poster now opens a page, as on any narrow window.
      await t.tap(_poster('Dune'));
      await _move(t);
      expect(_pageOpen(t), 'movie 5');
    });
  });

  group('the keyboard', () {
    testWidgets('Ctrl+F finds the library\'s search from any tab', (t) async {
      await _open(t, _Radarr(movies: [_movie(5, 'Dune')]), _wide);
      await _tab(t, 'Calendar');
      expect(find.byType(TextField), findsNothing);

      await _key(t, LogicalKeyboardKey.keyF, ctrl: true);
      expect(find.text('Dune'), findsOneWidget);
      expect(_searchFocused(t), isTrue);

      // Escape hands the keys back, so the next shortcut still works.
      await _key(t, LogicalKeyboardKey.escape);
      expect(_searchFocused(t), isFalse);
      await _key(t, LogicalKeyboardKey.digit3, ctrl: true);
      expect(find.text('Nothing downloading'), findsOneWidget);
    });

    testWidgets('Ctrl+1 to 4 are the tabs', (t) async {
      final radarr = _Radarr(movies: [_movie(5, 'Dune')]);
      await _open(t, radarr, _wide);
      await _key(t, LogicalKeyboardKey.digit4, ctrl: true);
      expect(find.text('Nothing missing'), findsOneWidget);
      await _key(t, LogicalKeyboardKey.digit2, ctrl: true);
      expect(radarr.count('calendar'), 1);
      await _key(t, LogicalKeyboardKey.digit1, ctrl: true);
      expect(find.text('Dune'), findsOneWidget);
    });

    testWidgets('Escape leaves the search first, then closes the pane', (
      t,
    ) async {
      await _open(t, _Radarr(movies: [_movie(5, 'Dune')]), _wide);
      await t.tap(_poster('Dune'));
      await _move(t);
      await _key(t, LogicalKeyboardKey.keyF, ctrl: true);
      expect(_searchFocused(t), isTrue);

      await _key(t, LogicalKeyboardKey.escape);
      expect(_searchFocused(t), isFalse);
      expect(find.byType(ArrMovieScreen), findsOneWidget);
      await _key(t, LogicalKeyboardKey.escape);
      expect(find.byType(ArrMovieScreen), findsNothing);
    });

    testWidgets('F5 reloads the lists', (t) async {
      final radarr = _Radarr(movies: [_movie(5, 'Dune')]);
      await _open(t, radarr, _wide);
      expect(radarr.count('movie'), 1);
      radarr.movies = [_movie(5, 'Dune'), _movie(6, 'Heat')];
      await _key(t, LogicalKeyboardKey.f5);
      expect(radarr.count('movie'), 2);
      expect(find.text('Heat'), findsOneWidget);
    });
  });

  group('the Calendar', () {
    final now = DateTime.now();
    // Mid-month: never among the days a neighboring month's grid borrows.
    final day = DateTime(now.year, now.month, 15);
    Map<String, dynamic> release() => {
      ..._movie(5, 'Dune'),
      'digitalRelease': _on(day),
    };
    // More than a day of the month has room for.
    List<Map<String, dynamic>> busyDay() => [
      for (var i = 1; i <= 6; i++)
        {..._movie(10 + i, 'Movie $i'), 'digitalRelease': _on(day)},
    ];
    final more = find.textContaining(RegExp(r'^\+\d+ More$'));
    Finder inDay(String title) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(title),
    );
    // The dot round today's date.
    Finder todayMark(WidgetTester t) {
      final scheme = Theme.of(t.element(find.byType(ArrScreen))).colorScheme;
      return find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).color == scheme.primary &&
            w.child is Center,
      );
    }

    test('a month\'s grid is whole weeks around it', () {
      // November 2026 starts on a Sunday and has 30 days.
      final nov = DateTime(2026, 11);
      expect(arrMonthGrid(nov, 0), (start: DateTime(2026, 11, 1), weeks: 5));
      expect(arrMonthGrid(nov, 1), (start: DateTime(2026, 10, 26), weeks: 6));
      // February 2026: four weeks exactly, Sunday to Saturday.
      expect(
        arrMonthGrid(DateTime(2026, 2), 0),
        (start: DateTime(2026, 2, 1), weeks: 4),
      );
      expect(
        arrMonthGrid(DateTime(2026, 2, 17), 6),
        (start: DateTime(2026, 1, 31), weeks: 5),
      );
      // Across the day the clocks go back: still midnight, not 23:00.
      final grid = arrMonthGrid(DateTime(2026, 11), 0);
      final last = DateTime(
        grid.start.year,
        grid.start.month,
        grid.start.day + grid.weeks * 7,
      );
      expect((last.hour, last.day, last.month), (0, 6, 12));
    });

    test('the agenda runs from yesterday, four weeks ahead', () {
      final w = arrCalendarWindow(DateTime(2026, 11, 21, 18, 30));
      expect(w, (start: DateTime(2026, 11, 20), end: DateTime(2026, 12, 20)));
    });

    testWidgets('is a month on a wide window, and turns', (t) async {
      final radarr = _Radarr(movies: [_movie(5, 'Dune')], calendar: [release()]);
      await _open(t, radarr, _wide);
      await _tab(t, 'Calendar');
      expect(find.byType(ArrSwitch<ArrCalendarView>), findsOneWidget);
      expect(find.text(DateFormat.yMMMM('en').format(now)), findsOneWidget);
      expect(find.text('Dune'), findsOneWidget);
      expect(find.text('Today'), findsNothing);
      final asked = radarr.count('calendar');

      await t.tap(find.byTooltip('Next Month'));
      await _move(t);
      final next = DateTime(now.year, now.month + 1);
      expect(find.text(DateFormat.yMMMM('en').format(next)), findsOneWidget);
      expect(radarr.count('calendar'), asked + 1);
      expect(find.text('Dune'), findsNothing);

      await t.tap(find.text('Today'));
      await _move(t);
      expect(find.text('Dune'), findsOneWidget);

      // A release opens its title beside the month, which stays a month.
      await t.tap(find.text('Dune'));
      await _move(t);
      expect(find.byType(ArrMovieScreen), findsOneWidget);
      expect(find.byTooltip('Next Month'), findsOneWidget);
    });

    testWidgets('today is a dot round its date, not a bar across the day', (
      t,
    ) async {
      await _open(t, _Radarr(), _wide);
      await _tab(t, 'Calendar');
      final mark = todayMark(t);
      expect(mark, findsOneWidget);
      expect(
        find.descendant(of: mark, matching: find.text('${now.day}')),
        findsOneWidget,
      );
      final size = t.getSize(mark);
      expect(size.height, 24);
      // A day is a seventh of the window here: some 190 wide.
      expect(size.width, inInclusiveRange(24, 40));
    });

    testWidgets('the day turning moves today along', (t) async {
      var clock = DateTime(now.year, now.month, 15, 23, 59, 30);
      arrCalendarNow = () => clock;
      addTearDown(() => arrCalendarNow = DateTime.now);
      await _open(t, _Radarr(), _wide);
      await _tab(t, 'Calendar');
      Finder marked(int day) =>
          find.descendant(of: todayMark(t), matching: find.text('$day'));
      expect(marked(15), findsOneWidget);

      clock = DateTime(now.year, now.month, 16, 0, 0, 5);
      await t.pump(const Duration(seconds: 40));
      await _settle(t);
      expect(marked(15), findsNothing);
      expect(marked(16), findsOneWidget);
    });

    testWidgets('a movie out on the first day shown is there', (t) async {
      // West of UTC the month's first midnight is hours after the moment
      // Radarr keeps for that day's releases.
      final first = arrMonthGrid(DateTime(now.year, now.month), 0).start;
      final radarr = _Radarr(
        calendar: [
          {..._movie(5, 'Dune'), 'digitalRelease': _on(first)},
        ],
      );
      await _open(t, radarr, _wide);
      await _tab(t, 'Calendar');
      expect(radarr.calendarStart, _on(first).replaceFirst('Z', '.000Z'));
      expect(find.text('Dune'), findsOneWidget);
    });

    testWidgets('and on the agenda\'s first day, yesterday', (t) async {
      final yesterday = DateTime(now.year, now.month, now.day - 1);
      final radarr = _Radarr(
        calendar: [
          {..._movie(5, 'Dune'), 'digitalRelease': _on(yesterday)},
        ],
      );
      await _open(t, radarr, _phone);
      await _tab(t, 'Calendar');
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('Dune'), findsOneWidget);
    });

    testWidgets('weeks start on Sunday in the United States', (t) async {
      await _open(t, _Radarr(), _wide);
      await _tab(t, 'Calendar');
      expect(
        t.getTopLeft(find.text('Sun')).dx,
        lessThan(t.getTopLeft(find.text('Mon')).dx),
      );
    });

    testWidgets('and on Monday where the device\'s region starts them there', (
      t,
    ) async {
      // The app's own language is English either way.
      t.platformDispatcher.localeTestValue = const Locale('en', 'GB');
      addTearDown(t.platformDispatcher.clearLocaleTestValue);
      await _open(t, _Radarr(), _wide);
      await _tab(t, 'Calendar');
      expect(
        t.getTopLeft(find.text('Mon')).dx,
        lessThan(t.getTopLeft(find.text('Sun')).dx),
      );
    });

    testWidgets('large text makes a day\'s lines taller, not cut through', (
      t,
    ) async {
      t.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await _open(t, _Radarr(calendar: [release()]), _wide);
      await _tab(t, 'Calendar');
      expect(t.takeException(), isNull);
      // What the words need, against the box they're drawn in.
      double needs(Finder text) {
        final p = t.renderObject<RenderParagraph>(text);
        return p.getMaxIntrinsicHeight(p.size.width);
      }

      final title = find.text('Dune');
      final line = find.ancestor(of: title, matching: find.byType(InkWell));
      expect(needs(title), lessThanOrEqualTo(t.getSize(line.first).height));
      final number = find.descendant(
        of: todayMark(t),
        matching: find.byType(Text),
      );
      expect(needs(number), lessThanOrEqualTo(t.getSize(todayMark(t)).height));
    });

    testWidgets('a day with more than fits opens as a list', (t) async {
      await _open(t, _Radarr(calendar: busyDay()), _wide);
      await _tab(t, 'Calendar');
      expect(more, findsOneWidget);
      await t.tap(more);
      await _move(t);
      for (var i = 1; i <= 6; i++) {
        expect(inDay('Movie $i'), findsOneWidget);
      }

      // A row opens its title beside the month, and the list gets out of
      // the way.
      await t.tap(inDay('Movie 6'));
      await _move(t);
      expect(find.byType(AlertDialog), findsNothing);
      expect(t.widget<ArrMovieScreen>(find.byType(ArrMovieScreen)).id, 16);
    });

    testWidgets('whose rows still work once the month behind it is gone', (
      t,
    ) async {
      await _open(t, _Radarr(calendar: busyDay()), _wide);
      await _tab(t, 'Calendar');
      await t.tap(more);
      await _move(t);
      // Too narrow for a month now: the cell that opened the list is gone.
      t.view.physicalSize = const Size(560, 850);
      await _move(t);
      expect(find.byTooltip('Next Month'), findsNothing);

      await t.tap(inDay('Movie 6'));
      await _move(t);
      expect(t.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
      expect(_pageOpen(t), 'movie 16');
    });

    testWidgets('and a search from one closes the list to say it started', (
      t,
    ) async {
      final radarr = _Radarr(calendar: busyDay());
      await _open(t, radarr, _wide);
      await _tab(t, 'Calendar');
      await t.tap(more);
      await _move(t);
      await _rightClick(t, inDay('Movie 6'));
      await t.tap(find.text('Search Movie'));
      await _move(t);
      expect(radarr.count('command'), 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('Searching. Radarr'), findsOneWidget);
    });

    testWidgets('a reload that fails says so', (t) async {
      final radarr = _Radarr(calendar: [release()]);
      await _open(t, radarr, _wide);
      await _tab(t, 'Calendar');
      expect(find.text('Dune'), findsOneWidget);
      radarr.fail.add('calendar');
      await _key(t, LogicalKeyboardKey.f5);
      expect(
        find.descendant(
          of: find.byType(ArrErrorBanner),
          matching: find.byType(Text),
        ),
        findsWidgets,
      );
    });

    testWidgets('the layout picked is kept across tabs', (t) async {
      final radarr = _Radarr(calendar: [release()]);
      await _open(t, radarr, _wide);
      await _tab(t, 'Calendar');
      await t.tap(find.text('Agenda'));
      await _move(t);
      expect(find.byTooltip('Next Month'), findsNothing);

      await _tab(t, 'Wanted');
      await _tab(t, 'Calendar');
      expect(find.byTooltip('Next Month'), findsNothing);
    });

    testWidgets('is the agenda on a phone, with no switch', (t) async {
      await _open(t, _Radarr(calendar: [release()]), _phone);
      await _tab(t, 'Calendar');
      expect(find.byType(ArrSwitch<ArrCalendarView>), findsNothing);
      expect(find.byTooltip('Next Month'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('a release\'s menu opens it and searches for it', (t) async {
      final radarr = _Radarr(movies: [_movie(5, 'Dune')], calendar: [release()]);
      await _open(t, radarr, _wide);
      await _tab(t, 'Calendar');
      await _rightClick(t, find.text('Dune'));
      expect(_menu(t), ['Open', 'Open Full Page', 'Search Movie']);
      await t.tap(find.text('Open'));
      await _move(t);
      expect(find.byType(ArrMovieScreen), findsOneWidget);
    });
  });

  group('right-click menus', () {
    testWidgets('a poster: open, search, select', (t) async {
      await _open(t, _Radarr(movies: [_movie(5, 'Dune')]), _wide);
      await _rightClick(t, _poster('Dune'));
      expect(_menu(t), [
        'Open',
        'Open Full Page',
        'Search Movie',
        'Interactive Search',
        'Select',
      ]);
      await t.tap(find.text('Open Full Page'));
      await _move(t);
      expect(_pageOpen(t), 'movie 5');
    });

    testWidgets('no Open Full Page where a title opens as a page anyway', (
      t,
    ) async {
      await _open(t, _Radarr(movies: [_movie(5, 'Dune')]), _tablet);
      await _rightClick(t, _poster('Dune'));
      expect(_menu(t), ['Open', 'Search Movie', 'Interactive Search', 'Select']);
    });

    testWidgets('a wanted title: its Select starts picking with it', (t) async {
      final radarr = _Radarr(wanted: [_movie(9, 'Tenet'), _movie(8, 'Alien')]);
      await _open(t, radarr, _wide);
      await _tab(t, 'Wanted');
      await _rightClick(t, find.text('Tenet'));
      expect(_menu(t), [
        'Open',
        'Open Full Page',
        'Search Movie',
        'Interactive Search',
        'Select',
      ]);
      await t.tap(find.text('Select'));
      await _move(t);
      final boxes = t.widgetList<Checkbox>(find.byType(Checkbox)).toList();
      expect([for (final b in boxes) b.value], [true, false]);

      // While picking, a right-click is no menu.
      await _rightClick(t, find.text('Alien'));
      expect(_menu(t), isEmpty);
    });

    testWidgets('a blocked release: open its title, or take it off', (t) async {
      final radarr = _Radarr(
        blocklist: [
          {
            'id': 3,
            'movieId': 5,
            'sourceTitle': 'Dune.2021.CAM',
            'movie': _movie(5, 'Dune'),
          },
        ],
      );
      await _open(t, radarr, _wide);
      await _tab(t, 'Activity');
      await t.tap(find.text('Blocklist'));
      await _move(t);
      await _rightClick(t, find.text('Dune.2021.CAM').first);
      expect(_menu(t), [
        'Open',
        'Open Full Page',
        'Select',
        'Remove from Blocklist',
      ]);
    });
  });

  group('a list\'s buttons on a phone', () {
    testWidgets('Wanted folds them under More', (t) async {
      final radarr = _Radarr(wanted: [_movie(9, 'Tenet')]);
      await _open(t, radarr, _phone);
      await _tab(t, 'Wanted');
      expect(t.takeException(), isNull);
      expect(find.byTooltip('Manual Import'), findsNothing);
      expect(find.text('Search All'), findsNothing);

      await t.tap(find.byTooltip('More'));
      await _move(t);
      expect(_menu(t), ['Search All', 'Manual Import', 'Select']);
      await t.tap(find.text('Select'));
      await _move(t);
      expect(find.byType(Checkbox), findsOneWidget);
    });

    testWidgets('and a wide window shows them all', (t) async {
      final radarr = _Radarr(wanted: [_movie(9, 'Tenet')]);
      await _open(t, radarr, _wide);
      await _tab(t, 'Wanted');
      expect(find.text('Search All'), findsOneWidget);
      expect(find.byTooltip('Manual Import'), findsOneWidget);
      expect(find.byTooltip('Select'), findsOneWidget);
      expect(find.byTooltip('More'), findsNothing);
    });
  });

  group('a list\'s toolbar', () {
    testWidgets('folds below 600 of the list, its own padding counted', (
      t,
    ) async {
      Future<void> at(double width) => t.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: ArrToolbar(
                  lead: const Text('lead'),
                  tools: [ArrTool(Icons.checklist_rounded, 'Select', () {})],
                ),
              ),
            ),
          ),
        ),
      );
      await at(600);
      expect(find.byTooltip('Select'), findsOneWidget);
      expect(find.byTooltip('More'), findsNothing);
      await at(599);
      expect(find.byTooltip('Select'), findsNothing);
      expect(find.byTooltip('More'), findsOneWidget);
    });

    testWidgets('keeps its buttons beside the narrowest pane', (
      t,
    ) async {
      final radarr = _Radarr(wanted: [_movie(9, 'Tenet')]);
      // The narrowest window with a pane: the lists keep 623 of it.
      await _open(t, radarr, const Size(1040, 850));
      await _tab(t, 'Wanted');
      await t.tap(find.text('Tenet'));
      await _move(t);
      expect(find.byType(ArrMovieScreen), findsOneWidget);
      expect(find.text('Search All'), findsOneWidget);
      // The pane's title has a More of its own.
      expect(
        find.descendant(
          of: find.byType(ArrToolbar),
          matching: find.byTooltip('More'),
        ),
        findsNothing,
      );
      expect(t.takeException(), isNull);
    });
  });

  group('on a TV', () {
    setUp(() => isTvDevice = true);
    tearDown(() => isTvDevice = false);

    testWidgets('a title is a page and the Calendar a list, however wide', (
      t,
    ) async {
      final now = DateTime.now();
      final radarr = _Radarr(
        movies: [_movie(5, 'Dune')],
        calendar: [
          {..._movie(5, 'Dune'), 'digitalRelease': _on(now)},
        ],
      );
      await _open(t, radarr, const Size(1920, 1080));
      await t.tap(_poster('Dune'));
      await _move(t);
      expect(_pageOpen(t), 'movie 5');
      _router.pop();
      await _move(t);
      expect(find.byType(ArrMovieScreen), findsNothing);

      await _tab(t, 'Calendar');
      expect(find.byType(ArrSwitch<ArrCalendarView>), findsNothing);
      expect(find.byTooltip('Next Month'), findsNothing);
      expect(find.text('Today'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('a menu there, as under a finger, says what it\'s about', (
      t,
    ) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showContextMenu(
                  context,
                  at: Offset.zero,
                  title: 'Severance',
                  subtitle: 'S02E01 · Hello, Ms. Cobel\n8:00 PM · Unaired',
                  actions: [
                    ContextMenuAction(
                      icon: Icons.info_outline_rounded,
                      label: 'Open',
                      onTap: () {},
                    ),
                  ],
                ),
                child: const Text('press'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('press'));
      await _move(t);
      expect(find.text('Severance'), findsOneWidget);
      expect(find.textContaining('8:00 PM · Unaired'), findsOneWidget);
    });
  });

  group('while a list loads', () {
    testWidgets('the library shows posters to come, not a spinner', (t) async {
      final radarr = _Radarr(
        movies: [_movie(5, 'Dune')],
        slow: const {'movie': Duration(seconds: 2)},
      );
      await _open(t, radarr, _wide);
      expect(find.byType(ArrPosterGridSkeleton), findsOneWidget);
      expect(find.byType(AppSpinner), findsNothing);
      await t.pump(const Duration(seconds: 2));
      await _settle(t);
      expect(find.byType(ArrPosterGridSkeleton), findsNothing);
      expect(find.text('Dune'), findsOneWidget);
    });

    for (final (tab, path) in [
      ('Calendar', 'calendar'),
      ('Wanted', 'wanted/missing'),
      ('Activity', 'queue'),
    ]) {
      testWidgets('$tab shows rows to come', (t) async {
        final radarr = _Radarr(slow: {path: const Duration(seconds: 2)});
        // The Calendar's agenda: its month has the grid itself to show.
        await _open(t, radarr, tab == 'Calendar' ? _phone : _wide);
        await _tab(t, tab);
        expect(find.byType(ArrRowsSkeleton), findsOneWidget);
        expect(find.byType(AppSpinner), findsNothing);
        expect(t.takeException(), isNull);
        // The row above the list is where it will be once the list is in
        // (the Calendar's is the same widget either way).
        final bar = find.byType(ArrToolbar);
        final before = tab == 'Calendar' ? null : t.getRect(bar);
        await t.pump(const Duration(seconds: 2));
        await _settle(t);
        expect(find.byType(ArrRowsSkeleton), findsNothing);
        if (before != null) expect(t.getRect(bar), before);
      });
    }
  });
}
