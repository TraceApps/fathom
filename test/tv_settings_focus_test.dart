import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/screens/preferences_screen.dart';
import 'package:fathom/services/tv_mode.dart';
import 'package:fathom/state/preferences.dart';
import 'package:fathom/theme/app_theme.dart';
import 'package:fathom/widgets/app_dropdown.dart';
import 'package:fathom/widgets/tv_focus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Prefs extends PreferencesController {
  @override
  Future<Prefs> build() async => const Prefs();
}

// On a TV, a setting's row that holds its control (a dropdown, a switch at
// the end) is no stop of its own: Flutter would let it take the remote and
// light nothing, one press away from the control.
void main() {
  // As main() sets a TV up: the remote, never touch.
  setUpAll(() {
    isTvDevice = true;
    tvPassInertRows();
  });
  setUp(() {
    isTvDevice = true;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
  });
  tearDown(() {
    isTvDevice = false;
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  Future<void> general(WidgetTester t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        overrides: [preferencesProvider.overrideWith(_Prefs.new)],
        child: MaterialApp(
          theme: AppTheme.dark(const Color(0xFF8AB4F8)),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // A TV navigates by direction: there Flutter lets any row take the
          // remote, one with nothing to do too.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(navigationMode: NavigationMode.directional),
            child: child!,
          ),
          // As the shell holds a TV's pages.
          home: FocusTraversalGroup(
            policy: TvContentTraversalPolicy(),
            child: const PreferencesScreen(section: 'general'),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  /// The widget whose focus the remote is on, nearest first.
  bool focusedIn<W extends Widget>() =>
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<W>() !=
      null;

  /// The row right under Open on Startup: the first switch of the page.
  FocusNode rowBelow(WidgetTester t) {
    final dropdown = Focus.of(
      t.element(find.byType(AppDropdown<String>).first),
      createDependency: false,
    );
    final stops = FocusManager.instance.rootScope.traversalDescendants
        .where((n) => n.canRequestFocus && n.context != null)
        .where((n) => n.rect.top > dropdown.rect.bottom)
        .toList()
      ..sort((a, b) => a.rect.top.compareTo(b.rect.top));
    return stops.first;
  }

  testWidgets('Up from the row below goes to the dropdown, not its row', (
    t,
  ) async {
    await general(t);
    rowBelow(t).requestFocus();
    await t.pump();
    expect(focusedIn<AppDropdown<String>>(), isFalse);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.pumpAndSettle();
    expect(focusedIn<AppDropdown<String>>(), isTrue);
  });

  testWidgets('and Down from the dropdown comes back', (t) async {
    await general(t);
    final below = rowBelow(t);
    below.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, below);
  });

  testWidgets('a page opened from Settings lands on the dropdown, and Up '
      'from the row below comes back to it', (t) async {
    // A 1080p TV: 960 x 540 to lay out in.
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final pages = GlobalKey<NavigatorState>();
    await t.pumpWidget(
      ProviderScope(
        overrides: [preferencesProvider.overrideWith(_Prefs.new)],
        child: MaterialApp(
          theme: AppTheme.dark(const Color(0xFF8AB4F8)),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(navigationMode: NavigationMode.directional),
            child: child!,
          ),
          // As the shell holds a TV's pages: Settings, then General over it.
          home: Scaffold(
            body: TvContent(
              location: '/settings',
              child: Navigator(
                key: pages,
                onGenerateRoute: (_) => MaterialPageRoute(
                  builder: (_) => Scaffold(
                    body: ListView(
                      children: [
                        ListTile(title: const Text('General'), onTap: () {}),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 500));
    pages.currentState!.push(
      MaterialPageRoute(
        builder: (_) => const TvPageLanding(
          child: PreferencesScreen(section: 'general'),
        ),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(focusedIn<AppDropdown<String>>(), isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pumpAndSettle();
    expect(focusedIn<AppDropdown<String>>(), isFalse);
    // Back up: Flutter goes to the row, and the remote is passed on.
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.pumpAndSettle();
    expect(focusedIn<AppDropdown<String>>(), isTrue);
  });

  testWidgets('off a TV a row keeps the remote', (t) async {
    isTvDevice = false;
    await general(t);
    final row = FocusManager.instance.rootScope.descendants.firstWhere(
      tvInertRow,
    );
    row.requestFocus();
    await t.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, row);
  });

}
