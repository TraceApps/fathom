import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fathom/api/arr_client.dart';
import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/models/arr.dart';
import 'package:fathom/routing/nav_destinations.dart';
import 'package:fathom/screens/arr_screen.dart';
import 'package:fathom/state/arr_providers.dart';
import 'package:fathom/theme/app_theme.dart';
import 'package:fathom/widgets/arr_actions.dart';
import 'package:fathom/widgets/arr_widgets.dart';
import 'package:fathom/widgets/detail_header.dart';
import 'package:fathom/widgets/hover_pill_button.dart';
import 'package:fathom/widgets/seerr_icon.dart';
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
  _Rig({this.sonarr, this.radarr});

  Widget app() {
    router = GoRouter(
      initialLocation: '/arr',
      routes: [
        GoRoute(path: '/arr', builder: (_, _) => const ArrScreen()),
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
