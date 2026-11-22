import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fathom/api/arr_client.dart';
import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/models/arr.dart';
import 'package:fathom/routing/nav_destinations.dart';
import 'package:fathom/screens/arr_add_screen.dart';
import 'package:fathom/screens/arr_collections_screen.dart';
import 'package:fathom/screens/arr_releases_screen.dart';
import 'package:fathom/screens/arr_screen.dart';
import 'package:fathom/services/tv_mode.dart';
import 'package:fathom/state/arr_providers.dart';
import 'package:fathom/theme/app_theme.dart';
import 'package:fathom/widgets/arr_actions.dart';
import 'package:fathom/widgets/arr_pane.dart';
import 'package:fathom/widgets/arr_widgets.dart';
import 'package:fathom/widgets/detail_header.dart';
import 'package:fathom/widgets/hover_pill_button.dart';
import 'package:fathom/widgets/search_field.dart';
import 'package:fathom/widgets/seerr_icon.dart';
import 'package:fathom/widgets/tv_focus.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// The Manage section: its four tabs, the switches inside Library and
// Activity, the queue count on the Activity tab, and a title's actions on a
// narrow window.

/// Answers every request from [reply] and keeps what was asked for.
class _Server implements HttpClientAdapter {
  final Object? Function(String path) reply;
  final List<String> asked = [];

  /// How long each answer to a path takes; none by default.
  final Map<String, Duration> slow;
  _Server(this.reply, {this.slow = const {}});

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
      jsonEncode(reply(path)),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}

  int count(String path) => asked.where((p) => p == path).length;
}

Map<String, dynamic> _page(List<Map<String, dynamic>> records) => {
  'page': 1,
  'pageSize': 50,
  'totalRecords': records.length,
  'records': records,
};

const _downloading = {'id': 1, 'title': 'Show.S01E01', 'status': 'downloading'};
const _blocked = {
  'id': 2,
  'title': 'Movie.2020',
  'status': 'completed',
  'trackedDownloadStatus': 'warning',
  'trackedDownloadState': 'importBlocked',
};

/// A server with [queue] downloading and nothing else in it.
_Server _server([
  List<Map<String, dynamic>> queue = const [],
  Map<String, Duration> slow = const {},
]) => _Server(
  slow: slow,
  (path) => switch (path) {
    'queue' => _page(queue),
    'queue/status' => {
      'totalCount': queue.length,
      'warnings': queue.any((q) => q['trackedDownloadStatus'] == 'warning'),
      'errors': false,
    },
    'history' || 'blocklist' => _page(const []),
    'wanted/missing' || 'wanted/cutoff' => _page(const []),
    'system/status' => {'version': '1.0.0'},
    _ => const [],
  },
);

class _Rig {
  final _Server? sonarr;
  final _Server? radarr;
  late final GoRouter router;

  /// One page of the section by itself, in place of the section.
  final Widget? alone;
  _Rig({this.sonarr, this.radarr, this.alone});

  Widget app() {
    router = GoRouter(
      initialLocation: '/arr',
      routes: [
        GoRoute(
          path: '/arr',
          builder: (_, _) => alone ?? const ArrScreen(),
        ),
        GoRoute(
          path: '/arr/add',
          builder: (_, _) => const Scaffold(body: Text('add: both')),
        ),
        GoRoute(
          path: '/arr/add/:kind',
          builder: (_, s) =>
              Scaffold(body: Text('add: ${s.pathParameters['kind']}')),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        sonarrClientProvider.overrideWithValue(
          sonarr == null
              ? null
              : SonarrClient(
                  'http://s',
                  'k',
                  dio: Dio()..httpClientAdapter = sonarr!,
                ),
        ),
        radarrClientProvider.overrideWithValue(
          radarr == null
              ? null
              : RadarrClient(
                  'http://r',
                  'k',
                  dio: Dio()..httpClientAdapter = radarr!,
                ),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.dark(const Color(0xFF8AB4F8)),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
  }
}

Future<_Rig> _open(
  WidgetTester t, {
  _Server? sonarr,
  _Server? radarr,
  Size size = const Size(1200, 900),
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final rig = _Rig(sonarr: sonarr, radarr: radarr);
  await t.pumpWidget(rig.app());
  await _settle(t);
  return rig;
}

/// One page of the section by itself, as its own address opens it.
Future<void> _alone(
  WidgetTester t,
  Widget page, {
  _Server? sonarr,
  _Server? radarr,
  Size size = const Size(1200, 900),
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(_Rig(sonarr: sonarr, radarr: radarr, alone: page).app());
  await _settle(t);
}

/// Lets the answers arrive and the page draw them. Never pumpAndSettle: the
/// spinners and the queue's reload never go quiet.
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _tab(WidgetTester t, String name) async {
  await t.tap(find.widgetWithText(Tab, name));
  await _settle(t);
  // The swipe between tabs runs for 300 ms.
  await t.pump(const Duration(milliseconds: 400));
  await _settle(t);
}

List<String> _tabLabels(WidgetTester t) => [
  for (final e in t.widgetList<Text>(
    find.descendant(of: find.byType(TabBar), matching: find.byType(Text)),
  ))
    e.data!,
];

/// The Activity tab's count pill, or null when there's none.
Container? _countPill(WidgetTester t) {
  final f = find.descendant(
    of: find.byType(TabBar),
    matching: find.byWidgetPredicate(
      (w) => w is Container && w.decoration is BoxDecoration,
    ),
  );
  return f.evaluate().isEmpty ? null : t.widget<Container>(f.first);
}

/// A server that can't be reached.
_Server _down() => _Server((path) => throw const SocketException('down'));

/// How much the Activity tab's name was shrunk to fit: 1 when not at all.
double _activityScale(WidgetTester t) {
  final label = find.descendant(
    of: find.byType(TabBar),
    matching: find.text('Activity'),
  );
  return t.getRect(label).width / t.getSize(label).width;
}

/// True when the Activity tab's name and count sit inside their tab.
bool _activityFits(WidgetTester t) {
  final tab = t.getRect(find.widgetWithText(Tab, 'Activity'));
  final label = t.getRect(
    find.descendant(of: find.byType(TabBar), matching: find.text('Activity')),
  );
  final pill = t.getRect(find.byWidget(_countPill(t)!));
  return label.left >= tab.left - 0.5 && pill.right <= tab.right + 0.5;
}

/// True when the text drew whole: not cut short and not wrapped.
bool _whole(WidgetTester t, Finder text) {
  final p = t.renderObject<RenderParagraph>(text);
  return p.getMaxIntrinsicWidth(double.infinity) <= p.size.width + 0.5;
}

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

void main() {
  group('tabs', () {
    testWidgets('are Library, Calendar, Activity, Wanted', (t) async {
      await _open(t, sonarr: _server(), radarr: _server());
      expect(_tabLabels(t), ['Library', 'Calendar', 'Activity', 'Wanted']);
      expect(find.widgetWithText(AppBar, 'Manage'), findsOneWidget);
    });

    testWidgets('Activity counts the queue of both apps', (t) async {
      await _open(
        t,
        sonarr: _server([_downloading]),
        radarr: _server([
          {..._downloading, 'id': 7},
        ]),
      );
      expect(_tabLabels(t), ['Library', 'Calendar', 'Activity', '2', 'Wanted']);
      final box = _countPill(t)!.decoration as BoxDecoration;
      expect(box.color, isNot(arrWarningColor));
    });

    testWidgets('the count is orange when a download needs help', (t) async {
      await _open(
        t,
        sonarr: _server([_downloading]),
        radarr: _server([_blocked]),
      );
      final box = _countPill(t)!.decoration as BoxDecoration;
      expect(box.color, arrWarningColor);
    });

    testWidgets('an empty queue shows no count', (t) async {
      await _open(t, sonarr: _server(), radarr: _server());
      expect(_countPill(t), isNull);
    });

    testWidgets('fit a small phone without cutting a label', (t) async {
      await _loadInter();
      await _open(
        t,
        sonarr: _server([_downloading]),
        radarr: _server([_blocked]),
        size: const Size(360, 780),
      );
      expect(_activityScale(t), closeTo(1, 0.001));
      expect(_activityFits(t), isTrue);
      for (final label in ['Library', 'Calendar', 'Wanted']) {
        expect(
          _whole(
            t,
            find.descendant(
              of: find.byType(TabBar),
              matching: find.text(label),
            ),
          ),
          isTrue,
          reason: label,
        );
      }
      // The Movies and Shows switch keeps each name on one line.
      for (final label in ['Movies', 'Shows']) {
        expect(
          _whole(
            t,
            find.descendant(
              of: find.byType(SegmentedButton<ArrKind>),
              matching: find.text(label),
            ),
          ),
          isTrue,
          reason: label,
        );
      }
      expect(t.takeException(), isNull);
    });

    testWidgets('a long count shrinks the Activity tab, never cuts it', (
      t,
    ) async {
      await _loadInter();
      for (final n in [12, 120]) {
        await t.pumpWidget(const SizedBox());
        await _open(
          t,
          sonarr: _server([
            for (var i = 0; i < n; i++) {..._downloading, 'id': i},
          ]),
          radarr: _server(),
          size: const Size(360, 780),
        );
        expect(_tabLabels(t), contains('$n'));
        expect(_activityFits(t), isTrue, reason: '$n');
        expect(_activityScale(t), greaterThan(0.8), reason: '$n');
        expect(t.takeException(), isNull);
      }
    });

    testWidgets('the count comes from the small status answer', (t) async {
      final sonarr = _server([_downloading]);
      await _open(t, sonarr: sonarr, radarr: _server());
      expect(sonarr.count('queue/status'), 1);
      // The whole queue is only downloaded for the queue's own list.
      expect(sonarr.count('queue'), 0);
    });

    testWidgets('an app that can\'t be reached turns the count orange', (
      t,
    ) async {
      await _open(t, sonarr: _down(), radarr: _server([_downloading]));
      expect(_tabLabels(t), contains('1'));
      expect((_countPill(t)!.decoration as BoxDecoration).color,
          arrWarningColor);

      // Nothing to count at all: a "!" says the queue couldn't be read.
      await t.pumpWidget(const SizedBox());
      await _open(t, sonarr: _down(), radarr: _server());
      expect(_tabLabels(t), contains('!'));
      expect((_countPill(t)!.decoration as BoxDecoration).color,
          arrWarningColor);
    });
  });

  group('Library', () {
    testWidgets('switches between movies and shows, keeping the search', (
      t,
    ) async {
      await _open(t, sonarr: _server(), radarr: _server());
      expect(find.byType(SegmentedButton<ArrKind>), findsOneWidget);
      expect(find.text('Search your movies'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'dune');
      await _settle(t);

      await t.tap(find.text('Shows'));
      await _settle(t);
      expect(find.text('Search your movies'), findsNothing);
      expect(t.widget<TextField>(find.byType(TextField)).controller!.text,
          'dune');
    });

    testWidgets('has no switch with one app connected', (t) async {
      await _open(t, radarr: _server());
      expect(find.byType(SegmentedButton<ArrKind>), findsNothing);
      expect(find.text('Search your movies'), findsOneWidget);

      await t.pumpWidget(const SizedBox());
      await _open(t, sonarr: _server());
      expect(find.byType(SegmentedButton<ArrKind>), findsNothing);
      expect(find.text('Search your shows'), findsOneWidget);
    });

    testWidgets('Add looks for the kind showing', (t) async {
      final rig = await _open(t, sonarr: _server(), radarr: _server());
      await t.tap(find.text('Add'));
      await _settle(t);
      expect(find.text('add: movie'), findsOneWidget);
      rig.router.pop();
      await _settle(t);

      await t.tap(find.text('Shows'));
      await _settle(t);
      await t.tap(find.text('Add'));
      await _settle(t);
      expect(find.text('add: series'), findsOneWidget);
    });

    testWidgets('Add looks for shows with only Sonarr connected', (t) async {
      await _open(t, sonarr: _server());
      await t.tap(find.text('Add'));
      await _settle(t);
      expect(find.text('add: series'), findsOneWidget);
    });

    testWidgets('a phone keeps the tools and Select under More', (t) async {
      final movies = jsonDecode(
        File('test/fixtures/arr/radarr_movies.json').readAsStringSync(),
      );
      await _open(
        t,
        sonarr: _server(),
        radarr: _Server((path) => path == 'movie' ? movies : const []),
        size: const Size(360, 780),
      );
      expect(find.byTooltip('Select'), findsNothing);
      await t.tap(find.byTooltip('More'));
      await _settle(t);
      for (final label in ['Collections', 'Import Library', 'Select']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('Add searches both apps from the other tabs', (t) async {
      await _open(t, sonarr: _server(), radarr: _server());
      await _tab(t, 'Calendar');
      await t.tap(find.text('Add'));
      await _settle(t);
      expect(find.text('add: both'), findsOneWidget);
    });
  });

  group('Activity', () {
    testWidgets('holds the queue, the history and the blocklist', (t) async {
      final sonarr = _server();
      await _open(t, sonarr: sonarr, radarr: _server());
      expect(sonarr.count('history'), 0);
      expect(sonarr.count('blocklist'), 0);

      await _tab(t, 'Activity');
      expect(find.byType(SegmentedButton<ArrActivityView>), findsOneWidget);
      expect(find.text('Nothing downloading'), findsOneWidget);

      await t.tap(find.text('History'));
      await _settle(t);
      expect(sonarr.count('history'), 1);

      await t.tap(find.text('Blocklist'));
      await _settle(t);
      expect(sonarr.count('blocklist'), 1);
      expect(find.text('Nothing on the blocklist'), findsOneWidget);
      expect(find.text('Nothing downloading'), findsNothing);
      // Still in Manage, on the same tab: the lists are not pages of their
      // own.
      expect(find.widgetWithText(AppBar, 'Manage'), findsOneWidget);
      expect(find.byType(SegmentedButton<ArrActivityView>), findsOneWidget);
    });

    testWidgets('opens on the queue again after leaving the tab', (t) async {
      await _open(t, sonarr: _server(), radarr: _server());
      await _tab(t, 'Activity');
      await t.tap(find.text('Blocklist'));
      await _settle(t);
      expect(find.text('Nothing on the blocklist'), findsOneWidget);

      await _tab(t, 'Library');
      await _tab(t, 'Activity');
      expect(find.text('Nothing downloading'), findsOneWidget);
    });
  });

  group('queue reload', () {
    testWidgets('the count every 30 seconds, the queue\'s list every 5', (
      t,
    ) async {
      final sonarr = _server([_downloading]);
      await _open(t, sonarr: sonarr, radarr: _server());
      expect(sonarr.count('queue/status'), 1);

      await t.pump(const Duration(seconds: 29));
      await _settle(t);
      expect(sonarr.count('queue/status'), 1);
      await t.pump(const Duration(seconds: 2));
      await _settle(t);
      expect(sonarr.count('queue/status'), 2);
      expect(sonarr.count('queue'), 0);

      await _tab(t, 'Activity');
      final list = sonarr.count('queue');
      final status = sonarr.count('queue/status');
      expect(list, greaterThan(0));
      await t.pump(const Duration(seconds: 6));
      await _settle(t);
      expect(sonarr.count('queue'), greaterThan(list));
      // The count follows each reload of the list.
      expect(sonarr.count('queue/status'), greaterThan(status));

      // On another list the queue is left alone again.
      await t.tap(find.text('History'));
      await _settle(t);
      final left = sonarr.count('queue');
      await t.pump(const Duration(seconds: 12));
      await _settle(t);
      expect(sonarr.count('queue'), left);
    });

    testWidgets('stops while another page covers Manage', (t) async {
      final sonarr = _server([_downloading]);
      final rig = await _open(t, sonarr: sonarr, radarr: _server());
      rig.router.push('/arr/add');
      await _settle(t);
      await t.pump(const Duration(milliseconds: 400));
      final before = sonarr.count('queue/status');

      await t.pump(const Duration(seconds: 65));
      await _settle(t);
      expect(sonarr.count('queue/status'), before);

      // Back on Manage, the reload that waited runs at once.
      rig.router.pop();
      await _settle(t);
      await t.pump(const Duration(milliseconds: 400));
      await _settle(t);
      expect(sonarr.count('queue/status'), before + 1);
    });

    testWidgets('stops out of sight and catches up on the way back', (
      t,
    ) async {
      final sonarr = _server([_downloading]);
      await _open(t, sonarr: sonarr, radarr: _server());
      addTearDown(
        () => t.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      for (final s in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        t.binding.handleAppLifecycleStateChanged(s);
      }
      final before = sonarr.count('queue/status');
      await t.pump(const Duration(seconds: 65));
      await _settle(t);
      expect(sonarr.count('queue/status'), before);

      for (final s in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        t.binding.handleAppLifecycleStateChanged(s);
      }
      await _settle(t);
      expect(sonarr.count('queue/status'), before + 1);
      await t.pump(const Duration(seconds: 31));
      await _settle(t);
      expect(sonarr.count('queue/status'), before + 2);
    });

    testWidgets('keeps going in a window that only lost the focus', (t) async {
      final sonarr = _server([_downloading]);
      await _open(t, sonarr: sonarr, radarr: _server());
      addTearDown(
        () => t.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      final before = sonarr.count('queue/status');
      await t.pump(const Duration(seconds: 31));
      await _settle(t);
      expect(sonarr.count('queue/status'), before + 1);

      // Getting the focus back isn't a reason to ask again.
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle(t);
      expect(sonarr.count('queue/status'), before + 1);
    });

    testWidgets('a server slower than the reload still gets to answer', (
      t,
    ) async {
      final sonarr = _server(
        [_downloading],
        const {'queue': Duration(seconds: 12)},
      );
      await _open(t, sonarr: sonarr, radarr: _server());
      await _tab(t, 'Activity');
      expect(find.text('Show.S01E01'), findsNothing);
      // Two reloads come due while the first answer is on its way.
      await t.pump(const Duration(seconds: 13));
      await _settle(t);
      expect(find.text('Show.S01E01'), findsOneWidget);
      expect(sonarr.count('queue'), 1);
    });

    testWidgets('the count stays up while the next one is asked for', (
      t,
    ) async {
      final sonarr = _server(
        [_downloading],
        const {'queue/status': Duration(seconds: 3)},
      );
      await _open(t, sonarr: sonarr, radarr: _server());
      await t.pump(const Duration(seconds: 4));
      await _settle(t);
      expect(_tabLabels(t), contains('1'));
      await t.pump(const Duration(seconds: 28));
      expect(sonarr.count('queue/status'), 2);
      expect(_tabLabels(t), contains('1'));
      await t.pump(const Duration(seconds: 4));
    });
  });

  group('a title\'s actions', () {
    final tapped = <String>[];
    ArrAction a(String label, {bool primary = false, bool pinned = false}) =>
        ArrAction(
          icon: Icons.circle,
          label: label,
          primary: primary,
          pinned: pinned,
          onTap: () => tapped.add(label),
        );
    Widget bar({required bool header}) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ArrActionBar(
          header: header,
          title: 'Dune',
          main: [
            a('Search Movie', primary: true),
            a('Interactive Search'),
            a('Unmonitor', pinned: true),
            a('Edit'),
          ],
          more: [a('Refresh & Scan'), a('Delete')],
        ),
      ),
    );

    testWidgets('narrow: the main one named, the switch, and More', (t) async {
      tapped.clear();
      await t.pumpWidget(bar(header: false));
      final pills = t
          .widgetList<HoverPillButton>(find.byType(HoverPillButton))
          .toList();
      expect([for (final p in pills) p.label], [
        'Search Movie',
        'Unmonitor',
        'More',
      ]);
      // Only the main action shows its name at rest.
      expect(find.text('Search Movie'), findsOneWidget);
      expect(find.text('Unmonitor'), findsNothing);
      expect(find.text('More'), findsNothing);

      await t.tap(find.byTooltip('More'));
      await t.pumpAndSettle();
      // What left the row leads the menu, in its own order.
      final rows = [
        'Interactive Search',
        'Edit',
        'Refresh & Scan',
        'Delete',
      ];
      final tops = [for (final r in rows) t.getTopLeft(find.text(r)).dy];
      expect(tops, [...tops]..sort());
      await t.tap(find.text('Edit'));
      await t.pumpAndSettle();
      expect(tapped, ['Edit']);
    });

    testWidgets('wide: every main action is a header button', (t) async {
      await t.pumpWidget(bar(header: true));
      final buttons = t
          .widgetList<HeaderActionButton>(find.byType(HeaderActionButton))
          .toList();
      expect([for (final b in buttons) b.tooltip], [
        'Search Movie',
        'Interactive Search',
        'Unmonitor',
        'Edit',
        'More',
      ]);
    });
  });

  // On a TV the section keeps what a remote does well and leaves out what
  // takes a keyboard and a pointer: picking many at once, bringing a library
  // in and saying what a download is. Each is checked both ways on the same
  // screen, so it's the TV and not the size that decides.
  group('on a TV', () {
    const tv = Size(960, 540);
    tearDown(() => isTvDevice = false);

    Object fixture(String name) =>
        jsonDecode(File('test/fixtures/arr/$name.json').readAsStringSync())
            as Object;

    /// A Sonarr with the rig's three shows.
    _Server sonarr() => _Server(
      (path) => switch (path) {
        'series' => fixture('sonarr_series'),
        'queue' ||
        'history' ||
        'blocklist' ||
        'wanted/missing' ||
        'wanted/cutoff' => _page(const []),
        'queue/status' => {'totalCount': 0, 'warnings': false, 'errors': false},
        'system/status' => {'version': '1.0.0'},
        _ => const [],
      },
    );

    /// A Radarr with the rig's movies; [held] adds a download that a delay
    /// profile is holding back.
    _Server radarr({bool held = false}) {
      final movies = fixture('radarr_movies');
      // The second is one the app couldn't match: done downloading, and
      // waiting to be told which movie it is.
      final queue = [
        _downloading,
        {..._blocked, 'downloadId': 'abc'},
        if (held) {'id': 3, 'title': 'Held.2021', 'status': 'delay'},
      ];
      return _Server(
        (path) => switch (path) {
          'movie' => movies,
          'collection' => fixture('radarr_collections'),
          'release' => fixture('radarr_releases'),
          'queue' => _page(queue),
          'queue/status' => {
            'totalCount': queue.length,
            'warnings': true,
            'errors': false,
          },
          'wanted/missing' => _page([
            {
              'id': 5,
              'title': 'Dune',
              'year': 2021,
              'monitored': true,
              'hasFile': false,
            },
          ]),
          'history' || 'blocklist' || 'wanted/cutoff' => _page(const []),
          'system/status' => {'version': '1.0.0'},
          _ => const [],
        },
      );
    }

    /// The names of the tools on show, as their tooltips give them.
    Set<String> tools(WidgetTester t) => {
      for (final w in t.widgetList<Tooltip>(find.byType(Tooltip)))
        ?w.message,
    };

    /// The names of what the remote's focus passes through on its way to
    /// [f]: 'tvChrome', 'tvRow', 'tvRowActions'.
    Set<String?> labels(WidgetTester t, Finder f) => {
      for (final w in t.widgetList<Focus>(
        find.ancestor(of: f, matching: find.byType(Focus)),
      ))
        w.focusNode?.debugLabel ?? w.debugLabel,
    };

    /// Every focus node of that name.
    List<FocusNode> nodes(String label) => [
      for (final n in FocusManager.instance.rootScope.descendants)
        if (n.debugLabel == label) n,
    ];

    /// The stops a row's own buttons make for a remote.
    int rowButtonGroups() => FocusManager.instance.rootScope.descendants
        .where((n) => n.debugLabel == 'tvRowActions')
        .length;

    for (final onTv in [false, true]) {
      final where = onTv ? 'on a TV' : 'off a TV, on the same screen';

      testWidgets('the library\'s tools, $where', (t) async {
        isTvDevice = onTv;
        await _open(t, radarr: radarr(), size: tv);
        final names = tools(t);
        // Nothing is tucked away at this width, either way.
        expect(names, isNot(contains('More')));
        expect(names, containsAll(['Filter', 'Sort', 'Collections']));
        expect(names.contains('Select'), !onTv);
        expect(names.contains('Import Library'), !onTv);
        await t.pump(const Duration(seconds: 4));
      });

      testWidgets('the queue, $where', (t) async {
        isTvDevice = onTv;
        await _open(t, radarr: radarr(), size: tv);
        await _tab(t, 'Activity');
        expect(find.text('Movie.2020'), findsOneWidget);
        final names = tools(t);
        expect(names.contains('Select'), !onTv);
        expect(find.text('Manual Import'), onTv ? findsNothing : findsOneWidget);
        // Taking a download off the queue is one press either way, and on a
        // TV each row's button is a stop of the row's own.
        expect(find.byTooltip('Remove from Queue'), findsNWidgets(2));
        expect(rowButtonGroups(), onTv ? 2 : 0);
        await t.pump(const Duration(seconds: 4));
      });

      testWidgets('what\'s wanted, $where', (t) async {
        isTvDevice = onTv;
        await _open(t, radarr: radarr(), size: tv);
        await _tab(t, 'Wanted');
        expect(find.text('Dune'), findsOneWidget);
        final names = tools(t);
        expect(names, contains('Search Movie'));
        expect(names.contains('Select'), !onTv);
        expect(names.contains('Manual Import'), !onTv);
        expect(rowButtonGroups(), onTv ? 1 : 0);
        await t.pump(const Duration(seconds: 4));
      });

      testWidgets('the shows\' tools, $where', (t) async {
        isTvDevice = onTv;
        await _open(t, sonarr: sonarr(), size: tv);
        expect(find.text('Breaking Bad'), findsWidgets);
        final names = tools(t);
        expect(names, containsAll(['Filter', 'Sort']));
        expect(names.contains('Select'), !onTv);
        expect(names.contains('Import Library'), !onTv);
        await t.pump(const Duration(seconds: 4));
      });

      // A page opens on what's under its toolbar, with the toolbar one UP
      // away: each toolbar says so itself. And the section keeps the remote
      // on something when a list is asked for again.
      testWidgets('each tab\'s toolbar, $where', (t) async {
        isTvDevice = onTv;
        await _open(t, radarr: radarr(held: true), size: tv);
        Matcher has(String label) =>
            onTv ? contains(label) : isNot(contains(label));
        expect(nodes('tvKeeper'), onTv ? hasLength(1) : isEmpty);
        expect(labels(t, find.byTooltip('Filter')), has('tvChrome'));
        // The tabs too, and the one the remote is on shows from a couch.
        final library = find.widgetWithText(Tab, 'Library');
        expect(labels(t, library), has('tvChrome'));
        final tint = Theme.of(t.element(library)).tabBarTheme.overlayColor
            ?.resolve({WidgetState.focused});
        expect(tint?.a, onTv ? closeTo(0.34, 0.01) : isNull);
        // So do a switch's segments, the selected one too.
        final switchTint = Theme.of(t.element(library))
            .segmentedButtonTheme
            .style
            ?.overlayColor
            ?.resolve({WidgetState.focused, WidgetState.selected});
        expect(switchTint?.a, onTv ? closeTo(0.34, 0.01) : isNull);
        await _tab(t, 'Calendar');
        expect(labels(t, find.byType(FilterChip)), has('tvChrome'));
        // A month's grid is for a pointer: a TV has the list of days.
        expect(find.text('Month'), onTv ? findsNothing : findsOneWidget);
        await _tab(t, 'Activity');
        expect(labels(t, find.text('Blocklist')), has('tvChrome'));
        // A download held back has a button to send it now: a step to the
        // right of its row, like the one that takes it off the queue.
        expect(find.byTooltip('Grab Now'), findsOneWidget);
        expect(labels(t, find.byTooltip('Grab Now')), has('tvRowActions'));
        await _tab(t, 'Wanted');
        expect(labels(t, find.text('Cutoff Unmet')), has('tvChrome'));
        await t.pump(const Duration(seconds: 4));
      });

      // A pointer plugged into a TV still opens a row's menu: it has what a
      // remote has, and no picking of several.
      testWidgets('a download\'s menu, $where', (t) async {
        isTvDevice = onTv;
        await _open(t, radarr: radarr(), size: tv);
        await _tab(t, 'Activity');
        await t.tap(find.text('Show.S01E01'), buttons: kSecondaryButton);
        await _settle(t);
        await t.pump(const Duration(milliseconds: 400));
        expect(find.text('Remove from Queue'), findsOneWidget);
        expect(find.text('Select'), onTv ? findsNothing : findsOneWidget);
        await t.pump(const Duration(seconds: 4));
      });

      // One the app couldn't match, still downloading: on a TV its menu,
      // since there's no page to open; elsewhere nothing, with the menu a
      // right-click away.
      testWidgets('a download with no title of its own, $where', (t) async {
        isTvDevice = onTv;
        await _open(t, radarr: radarr(), size: tv);
        await _tab(t, 'Activity');
        await t.tap(find.text('Show.S01E01'));
        await _settle(t);
        await t.pump(const Duration(milliseconds: 400));
        expect(
          find.text('Remove from Queue'),
          onTv ? findsOneWidget : findsNothing,
        );
        await t.pump(const Duration(seconds: 4));
      });

      // A title opens in a pane beside the list on a wide window, and on its
      // own page on a TV however wide.
      testWidgets('a wide screen, $where', (t) async {
        isTvDevice = onTv;
        await _open(t, radarr: radarr(), size: const Size(1600, 900));
        final scope = t.widget<ArrPaneScope>(find.byType(ArrPaneScope).first);
        expect(scope.open == null, onTv);
        await t.pump(const Duration(seconds: 4));
      });

      testWidgets('a wanted title\'s menu, $where', (t) async {
        isTvDevice = onTv;
        await _open(t, radarr: radarr(), size: tv);
        await _tab(t, 'Wanted');
        await t.tap(find.text('Dune'), buttons: kSecondaryButton);
        await _settle(t);
        await t.pump(const Duration(milliseconds: 400));
        expect(find.text('Interactive Search'), findsOneWidget);
        expect(find.text('Select'), onTv ? findsNothing : findsOneWidget);
        await t.pump(const Duration(seconds: 4));
      });

      testWidgets('the collections, $where', (t) async {
        isTvDevice = onTv;
        await _alone(
          t,
          const ArrCollectionsScreen(),
          radarr: radarr(),
          size: tv,
        );
        Matcher has(String label) =>
            onTv ? contains(label) : isNot(contains(label));
        // A collection's own buttons are a row of their own, passed by when
        // the page opens; its movies are a row under them.
        final monitor = find.byWidgetPredicate(
          (w) =>
              w is IconButton &&
              (w.tooltip == 'Monitor' || w.tooltip == 'Unmonitor'),
        );
        expect(monitor, findsWidgets);
        expect(labels(t, monitor.first), has('tvChrome'));
        expect(labels(t, monitor.first), has('tvRow'));
        // Each movie is outlined while the remote is on it.
        final movies = find.byType(TvFocusRing);
        expect(movies, findsWidgets);
        expect(labels(t, movies.first), has('tvRow'));
        expect(labels(t, movies.first), isNot(contains('tvChrome')));
        // Both rows of a card are piled ones: UP and DOWN go to the row
        // right above or below, wherever on it.
        final rows = t.widgetList<TvFocusRow>(find.byType(TvFocusRow));
        expect(rows.length, onTv ? greaterThanOrEqualTo(2) : 0);
        expect(rows.every((r) => r.stacked), isTrue);
        await t.pump(const Duration(seconds: 4));
      });

      testWidgets('a search\'s releases, $where', (t) async {
        isTvDevice = onTv;
        await _alone(
          t,
          const ArrReleasesScreen(target: ArrReleaseTarget.movie(5)),
          radarr: radarr(),
          size: tv,
        );
        // On a TV a release is one stop, and its download a step to the
        // right of it.
        final grab = find.byTooltip('Grab');
        expect(grab, findsWidgets);
        expect(
          labels(t, grab.first),
          onTv ? contains('tvRowActions') : isNot(contains('tvRowActions')),
        );
        await t.pump(const Duration(seconds: 4));
      });

      testWidgets('adding a title, $where', (t) async {
        isTvDevice = onTv;
        await _alone(
          t,
          const ArrAddScreen(),
          sonarr: sonarr(),
          radarr: radarr(),
          size: tv,
        );
        // Opened to type: a TV leaves the remote on the field.
        Finder landing(Type field) => find.ancestor(
          of: find.byType(field),
          matching: find.byType(TvLandingSpot),
        );
        expect(landing(SearchField), onTv ? findsOneWidget : findsNothing);
        // The Movies and Shows switch is passed by on the way to the results.
        final only = find.byWidgetPredicate((w) => w is SegmentedButton);
        expect(only, findsOneWidget);
        expect(
          labels(t, only),
          onTv ? contains('tvChrome') : isNot(contains('tvChrome')),
        );
        await t.pump(const Duration(seconds: 4));

        // Opened with its words, it's the results the remote is for.
        await t.pumpWidget(const SizedBox());
        await _alone(
          t,
          const ArrAddScreen(term: 'dune'),
          sonarr: sonarr(),
          radarr: radarr(),
          size: tv,
        );
        expect(landing(SearchField), findsNothing);
        await t.pump(const Duration(seconds: 4));
      });
    }

    testWidgets('a download the app couldn\'t match opens what can still be '
        'done with it', (t) async {
      isTvDevice = true;
      await _open(t, radarr: radarr(), size: tv);
      await _tab(t, 'Activity');
      await t.tap(find.text('Movie.2020'));
      await _settle(t);
      await t.pump(const Duration(milliseconds: 400));
      // Its menu: taking it off the queue, and nothing that needs a pointer.
      expect(find.text('Remove from Queue'), findsOneWidget);
      expect(find.text('Manual Import'), findsNothing);
      expect(find.text('Select'), findsNothing);
      await t.pump(const Duration(seconds: 4));
    });

    testWidgets('a blocked release\'s menu has no Select', (t) async {
      // The way to it on a TV is a pointer plugged in: a remote has none.
      for (final onTv in [false, true]) {
        isTvDevice = onTv;
        final server = _Server(
          (path) => switch (path) {
            'blocklist' => _page([
              {
                'id': 3,
                'movieId': 5,
                'sourceTitle': 'Dune.2021.CAM',
                'movie': {'id': 5, 'title': 'Dune', 'year': 2021},
              },
            ]),
            'queue' || 'history' => _page(const []),
            'wanted/missing' || 'wanted/cutoff' => _page(const []),
            'queue/status' => {
              'totalCount': 0,
              'warnings': false,
              'errors': false,
            },
            'system/status' => {'version': '1.0.0'},
            _ => const [],
          },
        );
        await _open(t, radarr: server, size: tv);
        await _tab(t, 'Activity');
        await t.tap(find.text('Blocklist'));
        await _settle(t);
        expect(find.byTooltip('Select').evaluate().isEmpty, onTv);
        await t.tap(
          find.text('Dune.2021.CAM').first,
          buttons: kSecondaryButton,
        );
        await _settle(t);
        await t.pump(const Duration(milliseconds: 400));
        expect(find.text('Remove from Blocklist'), findsOneWidget);
        expect(
          find.text('Select'),
          onTv ? findsNothing : findsOneWidget,
          reason: 'on a TV: $onTv',
        );
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 4));
      }
    });
  });

  test('Discover keeps the Seerr logo wherever the navigation draws it', () {
    const NavDest discover = (
      route: '/discover',
      icon: Icons.travel_explore_rounded,
      label: 'Discover',
      fixed: false,
    );
    const NavDest manage = (
      route: '/arr',
      icon: kManageIcon,
      label: 'Manage',
      fixed: false,
    );
    expect(navDestIcon(discover, color: Colors.white), isA<SeerrIcon>());
    final icon = navDestIcon(manage, color: Colors.white, size: 20);
    expect(icon, isA<Icon>());
    expect((icon as Icon).icon, kManageIcon);
  });
}
