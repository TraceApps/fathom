import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fathom/api/jellyfin_client.dart';
import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/models/base_item.dart';
import 'package:fathom/models/session.dart';
import 'package:fathom/screens/library_screen.dart';
import 'package:fathom/state/library_providers.dart';
import 'package:fathom/state/preferences.dart';
import 'package:fathom/state/providers.dart';
import 'package:fathom/state/session_controller.dart';
import 'package:fathom/widgets/list_toolbar.dart';
import 'package:fathom/widgets/search_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// One toolbar for every library: a Jellyfin library and Manage offer search,
// Filter, Sort (with its direction) and Select the same way, and a library
// that has nothing to match says so instead of calling itself empty.

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

class _Prefs extends PreferencesController {
  @override
  Future<Prefs> build() async => const Prefs(libraryViewMode: 'list');
  @override
  Future<void> edit(Prefs Function(Prefs) change) async {
    state = AsyncData(change(state.asData!.value));
  }
}

class _Signed extends SessionController {
  @override
  Future<Session?> build() async => const Session(
    baseUrl: 'http://jf',
    accessToken: 't',
    userId: 'u1',
    userName: 'rig',
  );
}

/// A server with three movies, which searches and sorts as it's asked.
class _Server implements HttpClientAdapter {
  final asked = <Map<String, dynamic>>[];

  /// A search for this waits here before it's answered.
  String? slowTerm;
  final slow = Completer<void>();
  static const _names = ['Alien', 'Brazil', 'Casablanca'];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    if (!o.path.endsWith('/Items')) {
      return ResponseBody.fromString('{}', 404);
    }
    final q = o.queryParameters;
    asked.add(q);
    final term = (q['SearchTerm'] as String?)?.toLowerCase();
    if (term != null && term == slowTerm) await slow.future;
    var names = [
      for (final n in _names)
        if (term == null || n.toLowerCase().contains(term)) n,
    ];
    if (q['SortOrder'] == 'Descending') names = names.reversed.toList();
    return ResponseBody.fromString(
      jsonEncode({
        'Items': [
          for (final n in names) {'Id': n, 'Name': n, 'Type': 'Movie'},
        ],
        'TotalRecordCount': names.length,
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<_Server> _open(WidgetTester t, {double width = 900}) async {
  t.view.physicalSize = Size(width, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final server = _Server();
  final c = ProviderContainer(
    overrides: [
      sessionControllerProvider.overrideWith(_Signed.new),
      preferencesProvider.overrideWith(_Prefs.new),
      currentUserProvider.overrideWith((ref) async => null),
      jellyfinClientProvider.overrideWithValue(
        JellyfinClient(
          deviceId: 'd',
          httpClient: Dio()..httpClientAdapter = server,
        ),
      ),
    ],
  );
  addTearDown(c.dispose);
  await c.read(sessionControllerProvider.future);
  await c.read(preferencesProvider.future);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const LibraryScreen(
          library: BaseItemDto(
            id: 'lib',
            name: 'Movies',
            collectionType: 'movies',
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return server;
}

/// A line of an open menu, by its words.
Finder _line(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((w) => w is PopupMenuEntry),
).first;

void main() {
  group('The Sort menu', () {
    Future<List<(String, bool)>> open(
      WidgetTester t, {
      String value = 'name',
      bool descending = false,
    }) async {
      final picked = <(String, bool)>[];
      await t.pumpWidget(
        _app(
          SortMenu<String>(
            value: value,
            options: const {'name': 'Name', 'added': 'Date Added'},
            descending: descending,
            startsDescending: (v) => v == 'added',
            onChanged: (v, d) => picked.add((v, d)),
          ),
        ),
      );
      await t.tap(find.byTooltip('Sort'));
      await t.pumpAndSettle();
      return picked;
    }

    testWidgets('lists the orders, then Ascending and Descending', (t) async {
      await open(t);
      for (final label in ['Name', 'Date Added', 'Ascending', 'Descending']) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('another order starts the way it usually reads', (t) async {
      final picked = await open(t);
      await t.tap(_line('Date Added'));
      await t.pumpAndSettle();
      expect(picked, [('added', true)]);
    });

    testWidgets('Descending turns the same order round', (t) async {
      final picked = await open(t);
      await t.tap(_line('Descending'));
      await t.pumpAndSettle();
      expect(picked, [('name', true)]);
    });

    testWidgets('picking what is already on changes nothing', (t) async {
      final picked = await open(t, descending: true);
      await t.tap(_line('Descending'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Sort'));
      await t.pumpAndSettle();
      await t.tap(_line('Name'));
      await t.pumpAndSettle();
      expect(picked, isEmpty);
    });
  });

  group('The toolbar', () {
    Future<List<String>> show(WidgetTester t, double width) async {
      t.view.physicalSize = Size(width, 600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final tapped = <String>[];
      await t.pumpWidget(
        _app(
          ListToolbar(
            search: SearchField(
              controller: TextEditingController(),
              hint: 'Search',
            ),
            menus: [
              IconButton(
                tooltip: 'Filter',
                icon: const ListFilterIcon(active: 0),
                onPressed: () {},
              ),
            ],
            tools: [
              ListTool(Icons.checklist_rounded, 'Select', () {
                tapped.add('Select');
              }),
            ],
          ),
        ),
      );
      return tapped;
    }

    testWidgets('a wide window has each tool as a button', (t) async {
      final tapped = await show(t, 1000);
      expect(find.byTooltip('More'), findsNothing);
      await t.tap(find.byTooltip('Select'));
      expect(tapped, ['Select']);
      expect(t.takeException(), isNull);
    });

    testWidgets('a phone folds the tools under More, on one line', (t) async {
      final tapped = await show(t, 360);
      expect(find.byTooltip('Select'), findsNothing);
      expect(find.byTooltip('Filter'), findsOneWidget);
      await t.tap(find.byTooltip('More'));
      await t.pumpAndSettle();
      await t.tap(find.text('Select'));
      await t.pumpAndSettle();
      expect(tapped, ['Select']);
      expect(t.takeException(), isNull);
    });

    testWidgets('the Filter icon counts the filters that are on', (t) async {
      await t.pumpWidget(_app(const ListFilterIcon(active: 2)));
      expect(find.text('2'), findsOneWidget);
      expect(find.byIcon(Icons.filter_alt_rounded), findsOneWidget);
      await t.pumpWidget(_app(const ListFilterIcon(active: 0)));
      expect(find.byIcon(Icons.filter_list_rounded), findsOneWidget);
    });
  });

  group('A Jellyfin library', () {
    testWidgets('has search, Filter, Sort, the view and Select', (t) async {
      await _open(t);
      expect(find.byType(SearchField), findsOneWidget);
      for (final tip in ['Filter', 'Sort', 'Grid View', 'Select']) {
        expect(find.byTooltip(tip), findsOneWidget, reason: tip);
      }
      expect(find.text('Alien'), findsOneWidget);
      expect(find.text('3 items'), findsOneWidget);
    });

    testWidgets('searches the server once the typing pauses', (t) async {
      final server = await _open(t);
      await t.enterText(find.byType(TextField), 'bra');
      await t.pump(const Duration(milliseconds: 100));
      expect(server.asked.length, 1, reason: 'not on every letter');
      await t.pumpAndSettle(const Duration(milliseconds: 400));
      expect(server.asked.last['SearchTerm'], 'bra');
      expect(find.text('Brazil'), findsOneWidget);
      expect(find.text('Alien'), findsNothing);
    });

    testWidgets('a slow answer to an older search is dropped', (t) async {
      final server = await _open(t);
      server.slowTerm = 'bra';
      await t.enterText(find.byType(TextField), 'bra');
      await t.pump(const Duration(milliseconds: 400));
      await t.enterText(find.byType(TextField), 'cas');
      await t.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.text('Casablanca'), findsOneWidget);
      server.slow.complete();
      await t.pumpAndSettle();
      expect(find.text('Brazil'), findsNothing);
      expect(find.text('Casablanca'), findsOneWidget);
    });

    testWidgets('says nothing matches, and Clear Filters brings it back', (
      t,
    ) async {
      await _open(t);
      await t.enterText(find.byType(TextField), 'zzz');
      await t.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.text('Nothing matches'), findsOneWidget);
      expect(find.text('This library is empty'), findsNothing);
      await t.tap(find.text('Clear Filters'));
      await t.pumpAndSettle();
      expect(find.text('Casablanca'), findsOneWidget);
      expect(find.text('Nothing matches'), findsNothing);
    });

    testWidgets('Descending asks the server for the other direction', (
      t,
    ) async {
      final server = await _open(t);
      await t.tap(find.byTooltip('Sort'));
      await t.pumpAndSettle();
      await t.tap(_line('Descending'));
      await t.pumpAndSettle();
      expect(server.asked.last['SortOrder'], 'Descending');
      expect(server.asked.last['SortBy'], 'SortName');
    });

    testWidgets('Select picks rows in the list view too, and Back ends it', (
      t,
    ) async {
      await _open(t);
      await t.tap(find.byTooltip('Select'));
      await t.pumpAndSettle();
      expect(find.byTooltip('Select'), findsNothing);
      expect(
        find.byIcon(Icons.radio_button_unchecked_rounded),
        findsNWidgets(3),
      );
      await t.tap(find.text('Brazil'));
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.radio_button_unchecked_rounded), findsNothing);
      expect(find.byTooltip('Select'), findsOneWidget);
    });

    testWidgets('fits a phone', (t) async {
      await _open(t, width: 360);
      expect(t.takeException(), isNull);
      expect(find.byTooltip('More'), findsOneWidget);
    });
  });
}
