import 'dart:io';

import 'package:fathom/services/tv_mode.dart';
import 'package:fathom/widgets/tv_focus.dart';
import 'package:fathom/widgets/tv_keyboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// A remote on an Android TV: where a page opens, how UP, DOWN, LEFT and RIGHT
// move through it, and that none of it is there on a phone or a computer.

/// An Android TV's screen.
const _tv = Size(960, 540);

/// A button the remote can stop on, known by its name.
class _Stop extends StatefulWidget {
  const _Stop(
    this.name, {
    super.key,
    this.autofocus = false,
    this.enabled = true,
    this.width = 160,
  });
  final String name;
  final bool autofocus;
  final bool enabled;
  final double width;

  @override
  State<_Stop> createState() => _StopState();
}

class _StopState extends State<_Stop> {
  late final FocusNode _node = FocusNode(debugLabel: widget.name);

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.width,
    height: 48,
    child: TextButton(
      focusNode: _node,
      autofocus: widget.autofocus,
      onPressed: widget.enabled ? () {} : null,
      child: Text(widget.name),
    ),
  );
}

/// A list's row that is itself a button, with buttons of its own inside.
class _RowStop extends StatefulWidget {
  const _RowStop(this.name, this.buttons, {this.height = 64});
  final String name;
  final List<Widget> buttons;
  final double height;

  @override
  State<_RowStop> createState() => _RowStopState();
}

class _RowStopState extends State<_RowStop> {
  late final FocusNode _node = FocusNode(debugLabel: widget.name);

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InkWell(
    focusNode: _node,
    onTap: () {},
    child: SizedBox(
      height: widget.height,
      child: Row(
        children: [
          Expanded(child: Text(widget.name)),
          ...widget.buttons,
        ],
      ),
    ),
  );
}

/// What the remote is on.
String? _at() => FocusManager.instance.primaryFocus?.debugLabel;

/// The stop called [name].
FocusNode _node(String name) => FocusManager.instance.rootScope.descendants
    .firstWhere((n) => n.debugLabel == name);

/// Whether anything in the tree is the focus node called [name].
bool _has(String name) =>
    FocusManager.instance.rootScope.descendants.any((n) => n.debugLabel == name);

Future<void> _frames(WidgetTester t, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _press(WidgetTester t, LogicalKeyboardKey key) async {
  await t.sendKeyEvent(key);
  await _frames(t);
}

Future<void> _focus(WidgetTester t, String name) async {
  _node(name).requestFocus();
  await _frames(t, 2);
}

const _up = LogicalKeyboardKey.arrowUp;
const _down = LogicalKeyboardKey.arrowDown;
const _left = LogicalKeyboardKey.arrowLeft;
const _right = LogicalKeyboardKey.arrowRight;

/// A test of a page on a TV. A landing keeps looking for somewhere to put the
/// remote for a few seconds; the test lets that run out before it ends.
void _tvTest(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(name, (t) async {
      await body(t);
      await t.pump(const Duration(seconds: 4));
    });

late GoRouter _router;
late GlobalKey<NavigatorState> _root;

/// A page with a bar on top and [children] down its left edge.
Widget _page(String title, List<Widget> children, {List<Widget>? bar}) =>
    Scaffold(
      appBar: AppBar(
        leading: const _Stop('Back', width: 56),
        title: Text(title),
        actions: bar,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [const SizedBox(height: 40), ...children],
      ),
    );

/// The app's shell as a TV has it: the rail's 200 at the left, the routed
/// pages beside it. Off TV, the same without the TV's own wiring.
Future<void> _shell(
  WidgetTester t,
  Map<String, WidgetBuilder> pages, {
  String at = '/a',
}) async {
  t.view.physicalSize = _tv;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  _root = GlobalKey<NavigatorState>();
  _router = GoRouter(
    navigatorKey: _root,
    initialLocation: at,
    routes: [
      ShellRoute(
        builder: (_, _, child) => Builder(
          builder: (context) => _railAndPages(
            GoRouterState.of(context).matchedLocation,
            child,
          ),
        ),
        routes: [
          for (final e in pages.entries)
            GoRoute(path: e.key, builder: (c, _) => e.value(c)),
        ],
      ),
    ],
  );
  await t.pumpWidget(MaterialApp.router(routerConfig: _router));
  await _frames(t);
}

Widget _railAndPages(String location, Widget child) => Material(
          child: Row(
            children: [
              SizedBox(
                width: 200,
                child: FocusTraversalGroup(
                  policy: isTvDevice ? TvRailPolicy() : null,
                  child: Column(
                    children: [
                      const SizedBox(height: 120),
                      TextButton(
                        focusNode: tvNavBarNode,
                        onPressed: () {},
                        child: const Text('Rail'),
                      ),
                      const _Stop('Rail Two'),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: isTvDevice
                    ? TvContent(location: location, child: child)
                    : FocusTraversalGroup(child: child),
              ),
            ],
          ),
        );

Future<void> _push(WidgetTester t, String page) async {
  _router.push(page);
  await _frames(t, 10);
}

/// A list, and a title's page that opens over it.
Map<String, WidgetBuilder> _listAndTitle({
  Widget Function(Widget)? wrap,
  List<Widget>? title,
}) => {
  '/a': (_) => _page('List', const [_Stop('One'), _Stop('Two')]),
  '/a/title': (_) => (wrap ?? (w) => TvPageLanding(child: w))(
    _page(
      'Title',
      title ??
          const [
            TvChrome(child: _Stop('Toolbar')),
            SizedBox(height: 120),
            _Stop('Search Movie'),
            _Stop('Edit'),
          ],
    ),
  ),
};

void main() {
  setUp(() {
    isTvDevice = true;
    tvLastContentFocus = null;
  });
  tearDown(() => isTvDevice = false);

  group('a page opened over another', () {
    _tvTest('opens on its first stop under the header', (t) async {
      await _shell(t, _listAndTitle());
      expect(_at(), 'One');
      await _push(t, '/a/title');
      // Not the Back button, and not the toolbar above the content.
      expect(_at(), 'Search Movie');
    });

    _tvTest('has nothing lit without a landing of its own', (t) async {
      // What the shell alone does: its landing is for a change of section.
      await _shell(t, _listAndTitle(wrap: (w) => w));
      await _push(t, '/a/title');
      expect(_at(), isNot('Search Movie'));
      expect(FocusManager.instance.primaryFocus, isA<FocusScopeNode>());
    });

    _tvTest('leaves the remote where the page itself put it', (t) async {
      await _shell(
        t,
        _listAndTitle(
          title: const [
            SizedBox(height: 120),
            _Stop('Search Movie'),
            _Stop('Edit', autofocus: true),
          ],
        ),
      );
      await _push(t, '/a/title');
      expect(_at(), 'Edit');
    });

    _tvTest('comes back to where the remote was on the page under it', (
      t,
    ) async {
      await _shell(t, _listAndTitle());
      await _press(t, _down);
      expect(_at(), 'Two');
      await _push(t, '/a/title');
      expect(_at(), 'Search Movie');
      _router.pop();
      await _frames(t, 10);
      expect(_at(), 'Two');
    });

    _tvTest('waits for a page that is still loading', (t) async {
      final loaded = ValueNotifier(false);
      addTearDown(loaded.dispose);
      await _shell(t, {
        '/a': (_) => _page('List', const [_Stop('One')]),
        '/a/title': (_) => TvPageLanding(
          child: ValueListenableBuilder(
            valueListenable: loaded,
            builder: (_, on, _) => _page('Title', [
              const SizedBox(height: 120),
              if (on) const _Stop('Search Movie'),
            ]),
          ),
        ),
      });
      await _push(t, '/a/title');
      expect(_at(), isNot('Back'));
      loaded.value = true;
      await _frames(t, 6);
      expect(_at(), 'Search Movie');
    });

    _tvTest('and never takes the remote back from the rail', (t) async {
      final loaded = ValueNotifier(false);
      addTearDown(loaded.dispose);
      await _shell(t, {
        '/a': (_) => _page('List', const [_Stop('One')]),
        '/a/title': (_) => TvPageLanding(
          child: ValueListenableBuilder(
            valueListenable: loaded,
            builder: (_, on, _) => _page('Title', [
              const SizedBox(height: 120),
              if (on) const _Stop('Search Movie'),
            ]),
          ),
        ),
      });
      await _push(t, '/a/title');
      tvNavBarNode.requestFocus();
      await _frames(t, 2);
      loaded.value = true;
      await _frames(t, 10);
      expect(FocusManager.instance.primaryFocus, tvNavBarNode);
    });

    _tvTest('nor from a dialog opened over it', (t) async {
      final loaded = ValueNotifier(false);
      addTearDown(loaded.dispose);
      await _shell(t, {
        '/a': (_) => _page('List', const [_Stop('One')]),
        '/a/title': (_) => TvPageLanding(
          child: ValueListenableBuilder(
            valueListenable: loaded,
            builder: (_, on, _) => _page('Title', [
              const SizedBox(height: 120),
              if (on) const _Stop('Search Movie'),
            ]),
          ),
        ),
      });
      await _push(t, '/a/title');
      showDialog<void>(
        context: _root.currentContext!,
        builder: (_) => const AlertDialog(
          content: _Stop('Confirm', autofocus: true),
        ),
      );
      await _frames(t, 8);
      expect(_at(), 'Confirm');
      loaded.value = true;
      await _frames(t, 10);
      expect(_at(), 'Confirm');
    });

    _tvTest('passes by a stop the page put somewhere out of sight', (
      t,
    ) async {
      await _shell(t, {
        '/a': (_) => _page('List', const [_Stop('One')]),
        '/a/title': (_) => TvPageLanding(
          child: Scaffold(
            appBar: AppBar(leading: const _Stop('Back', width: 56)),
            body: const SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(height: 120),
                  _Stop('Search Movie'),
                  SizedBox(height: 900),
                  _Stop('Far Down', autofocus: true),
                ],
              ),
            ),
          ),
        ),
      });
      await _push(t, '/a/title');
      expect(_at(), 'Search Movie');
    });

    _tvTest('lands once a dialog that opened while it loaded is gone', (
      t,
    ) async {
      final loaded = ValueNotifier(false);
      addTearDown(loaded.dispose);
      await _shell(t, {
        '/a': (_) => _page('List', const [_Stop('One')]),
        '/a/title': (_) => TvPageLanding(
          child: ValueListenableBuilder(
            valueListenable: loaded,
            builder: (_, on, _) => _page('Title', [
              const SizedBox(height: 120),
              if (on) const _Stop('Search Movie'),
            ]),
          ),
        ),
      });
      await _push(t, '/a/title');
      showDialog<void>(
        context: _root.currentContext!,
        builder: (_) => const AlertDialog(
          content: _Stop('Confirm', autofocus: true),
        ),
      );
      await _frames(t, 8);
      expect(_at(), 'Confirm');
      Navigator.of(_root.currentContext!).pop();
      await _frames(t, 8);
      loaded.value = true;
      await _frames(t, 10);
      expect(_at(), 'Search Movie');
    });

    _tvTest('a page with nothing under its header opens on its toolbar', (
      t,
    ) async {
      await _shell(
        t,
        _listAndTitle(
          title: const [TvChrome(child: _Stop('Toolbar'))],
        ),
      );
      await _push(t, '/a/title');
      expect(_at(), isNot('Toolbar'));
      // Within a second, not after the page gives up.
      await _frames(t, 24);
      expect(_at(), 'Toolbar');
      await _frames(t, 70);
      expect(_at(), 'Toolbar');
    });

    group('a stop that only loads later, above where it opened', () {
      late ValueNotifier<bool> ready;
      Future<void> open(WidgetTester t) async {
        ready = ValueNotifier(false);
        addTearDown(ready.dispose);
        await _shell(t, {
          '/a': (_) => _page('List', const [_Stop('One')]),
          '/a/title': (_) => TvPageLanding(
            child: ValueListenableBuilder(
              valueListenable: ready,
              builder: (_, on, _) => _page('Title', [
                const SizedBox(height: 120),
                _Stop('Quality Profile', enabled: on),
                const _Stop('Tags'),
                const _Stop('Notes'),
              ]),
            ),
          ),
        });
        await _push(t, '/a/title');
        expect(_at(), 'Tags');
      }

      _tvTest('takes the remote', (t) async {
        await open(t);
        ready.value = true;
        await _frames(t, 4);
        expect(_at(), 'Quality Profile');
      });

      _tvTest('but not once a key has been pressed', (t) async {
        await open(t);
        // Nothing to its right: the remote stays, but it's the person's now.
        await _press(t, _right);
        expect(_at(), 'Tags');
        ready.value = true;
        await _frames(t, 4);
        expect(_at(), 'Tags');
      });

      _tvTest('nor once the remote is on the rail', (t) async {
        await open(t);
        tvNavBarNode.requestFocus();
        await _frames(t, 2);
        ready.value = true;
        await _frames(t, 4);
        expect(FocusManager.instance.primaryFocus, tvNavBarNode);
      });

      _tvTest('nor once the page has moved it itself', (t) async {
        await open(t);
        _node('Notes').requestFocus();
        await _frames(t, 2);
        ready.value = true;
        await _frames(t, 4);
        expect(_at(), 'Notes');
      });

      _tvTest('nor after a few seconds', (t) async {
        await open(t);
        await t.pump(const Duration(seconds: 4));
        await t.pump(const Duration(milliseconds: 50));
        ready.value = true;
        await _frames(t, 4);
        expect(_at(), 'Tags');
      });
    });

    _tvTest('off a TV nothing is moved', (t) async {
      isTvDevice = false;
      await _shell(t, _listAndTitle());
      await _push(t, '/a/title');
      expect(_at(), isNot('Search Movie'));
      expect(_has('tvChrome'), isFalse);
    });
  });

  group('a section', () {
    _tvTest('opens under its toolbar, which stays one UP away', (t) async {
      await _shell(t, {
        '/a': (_) => _page('List', const [
          SizedBox(height: 40),
          TvChrome(child: _Stop('Filter')),
          _Stop('One'),
        ]),
      });
      expect(_at(), 'One');
      await _press(t, _up);
      expect(_at(), 'Filter');
    });

    _tvTest('passes by a toolbar that took the remote while it loaded', (
      t,
    ) async {
      final loaded = ValueNotifier(false);
      addTearDown(loaded.dispose);
      await _shell(t, {
        '/a': (_) => _page('List', const [_Stop('One')]),
        '/b': (_) => ValueListenableBuilder(
          valueListenable: loaded,
          builder: (_, on, _) => _page('Other', [
            const SizedBox(height: 40),
            const TvChrome(child: _Stop('Filter', autofocus: true)),
            if (on) const _Stop('Other One'),
          ]),
        ),
      });
      _router.go('/b');
      await _frames(t, 4);
      expect(_at(), 'Filter');
      loaded.value = true;
      await _frames(t, 10);
      expect(_at(), 'Other One');
    });

    _tvTest('opens on the toolbar when it has nothing else', (t) async {
      await _shell(t, {
        '/a': (_) => _page('List', const [
          SizedBox(height: 40),
          TvChrome(child: _Stop('Filter')),
        ]),
      });
      // An empty list: within a second, not after the page gives up.
      await _frames(t, 24);
      expect(_at(), 'Filter');
      await _frames(t, 70);
      expect(_at(), 'Filter');
    });

    // A list that's slow to come: the toolbar first, then what came.
    Future<ValueNotifier<bool>> slow(WidgetTester t) async {
      final loaded = ValueNotifier(false);
      addTearDown(loaded.dispose);
      await _shell(t, {
        '/a': (_) => ValueListenableBuilder(
          valueListenable: loaded,
          builder: (_, on, _) => _page('List', [
            const SizedBox(height: 40),
            const TvChrome(
              child: Row(children: [_Stop('Filter'), _Stop('Sort')]),
            ),
            if (on) const _Stop('One'),
          ]),
        ),
      });
      await _frames(t, 24);
      expect(_at(), 'Filter');
      return loaded;
    }

    _tvTest('moves down off its toolbar once the list comes', (t) async {
      final loaded = await slow(t);
      loaded.value = true;
      await _frames(t, 8);
      expect(_at(), 'One');
    });

    _tvTest('but not once the remote has moved along the toolbar', (t) async {
      final loaded = await slow(t);
      await _press(t, _right);
      expect(_at(), 'Sort');
      loaded.value = true;
      await _frames(t, 8);
      expect(_at(), 'Sort');
    });

    // A page for searching: its field up in the bar, results once there
    // are any.
    Future<ValueNotifier<bool>> search(
      WidgetTester t,
      Widget Function(Widget) field,
    ) async {
      final found = ValueNotifier(false);
      addTearDown(found.dispose);
      await _shell(t, {
        '/a': (_) => ValueListenableBuilder(
          valueListenable: found,
          builder: (_, on, _) => Scaffold(
            appBar: AppBar(
              leading: const _Stop('Back', width: 56),
              title: const Text('Add'),
            ),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                field(const _Stop('Search', autofocus: true)),
                const SizedBox(height: 120),
                if (on) const _Stop('Result'),
              ],
            ),
          ),
        ),
      });
      return found;
    }

    _tvTest('for searching stays on its search field', (t) async {
      final found = await search(t, (f) => TvLandingSpot(child: f));
      expect(_at(), 'Search');
      found.value = true;
      await _frames(t, 10);
      expect(_at(), 'Search');
      // The rail and back: still the field, the page's own choice.
      await _press(t, _left);
      expect(FocusManager.instance.primaryFocus, tvNavBarNode);
      await _press(t, _right);
      expect(_at(), 'Search');
    });

    _tvTest('and without that, moves down to its first result', (t) async {
      final found = await search(t, (f) => f);
      expect(_at(), 'Search');
      found.value = true;
      await _frames(t, 10);
      expect(_at(), 'Result');
    });

    _tvTest('leaves the remote in a dialog that is over everything', (
      t,
    ) async {
      final loaded = ValueNotifier(false);
      addTearDown(loaded.dispose);
      await _shell(t, {
        '/a': (_) => ValueListenableBuilder(
          valueListenable: loaded,
          builder: (_, on, _) =>
              _page('List', [if (on) const _Stop('One')]),
        ),
      });
      showDialog<void>(
        context: _root.currentContext!,
        builder: (_) => const AlertDialog(
          content: _Stop('Confirm', autofocus: true),
        ),
      );
      await _frames(t, 8);
      expect(_at(), 'Confirm');
      loaded.value = true;
      await _frames(t, 12);
      expect(_at(), 'Confirm');
    });

    _tvTest('lands anew when the section changes', (t) async {
      await _shell(t, {
        '/a': (_) => _page('List', const [_Stop('One')]),
        '/b': (_) => _page('Other', const [_Stop('Other One')]),
      });
      expect(_at(), 'One');
      _router.go('/b');
      await _frames(t, 10);
      expect(_at(), 'Other One');
    });
  });

  group('the rail', () {
    _tvTest('is LEFT of every page, and RIGHT comes back', (t) async {
      await _shell(t, _listAndTitle());
      await _press(t, _down);
      expect(_at(), 'Two');
      await _press(t, _left);
      expect(FocusManager.instance.primaryFocus, tvNavBarNode);
      await _press(t, _right);
      expect(_at(), 'Two');
    });

    _tvTest('UP and DOWN stay in it', (t) async {
      await _shell(t, _listAndTitle());
      await _press(t, _left);
      await _press(t, _down);
      expect(_at(), 'Rail Two');
      await _press(t, _down);
      expect(_at(), 'Rail Two');
      await _press(t, _up);
      expect(FocusManager.instance.primaryFocus, tvNavBarNode);
    });

    _tvTest('RIGHT goes to the page in front, not one under it', (
      t,
    ) async {
      await _shell(t, _listAndTitle());
      await _push(t, '/a/title');
      expect(_at(), 'Search Movie');
      // The list's stops are still built under the title's page.
      expect(_has('One'), isTrue);
      for (final from in ['Search Movie', 'Edit']) {
        await _focus(t, from);
        await _press(t, _left);
        expect(FocusManager.instance.primaryFocus, tvNavBarNode);
        await _press(t, _right);
        expect(_at(), from);
      }
    });

    _tvTest('a page opened from the rail takes the remote', (t) async {
      await _shell(t, _listAndTitle());
      await _press(t, _left);
      expect(FocusManager.instance.primaryFocus, tvNavBarNode);
      await _push(t, '/a/title');
      expect(_at(), 'Search Movie');
    });

    _tvTest('RIGHT never returns to a stop of a page under the front', (
      t,
    ) async {
      await _shell(t, _listAndTitle());
      await _push(t, '/a/title');
      // Where the remote last left the list, which is still built.
      tvLastContentFocus = _node('Two');
      await _focus(t, 'tvNavRail');
      await _press(t, _right);
      expect(_at(), 'Search Movie');
    });

    _tvTest('RIGHT with nothing to stop on yet stays on the rail', (t) async {
      final loaded = ValueNotifier(false);
      addTearDown(loaded.dispose);
      await _shell(t, {
        '/a': (_) => _page('List', const [_Stop('One')]),
        '/a/title': (_) => TvPageLanding(
          child: ValueListenableBuilder(
            valueListenable: loaded,
            builder: (_, on, _) => Scaffold(
              body: on ? const _Stop('Search Movie') : const SizedBox(),
            ),
          ),
        ),
      });
      await _push(t, '/a/title');
      await _focus(t, 'tvNavRail');
      await _press(t, _right);
      // Not the list's stop under the page that's loading.
      expect(FocusManager.instance.primaryFocus, tvNavBarNode);
      loaded.value = true;
      await _frames(t, 2);
      await _press(t, _right);
      expect(_at(), 'Search Movie');
    });

    _tvTest('RIGHT comes back under the header, not to its bar', (t) async {
      await _shell(t, _listAndTitle());
      await _focus(t, 'Back');
      await _press(t, _left);
      expect(FocusManager.instance.primaryFocus, tvNavBarNode);
      await _press(t, _right);
      expect(_at(), 'One');
    });

    _tvTest('RIGHT passes by where the remote was once that scrolled away', (
      t,
    ) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await _shell(t, {
        '/a': (_) => Scaffold(
          appBar: AppBar(title: const Text('List')),
          body: SingleChildScrollView(
            controller: scroll,
            child: Column(
              children: [for (var i = 0; i < 30; i++) _Stop('Item $i')],
            ),
          ),
        ),
      });
      scroll.jumpTo(600);
      await _frames(t, 2);
      await _focus(t, 'Item 20');
      await _press(t, _left);
      expect(FocusManager.instance.primaryFocus, tvNavBarNode);
      // The list back at its top: the remote's spot is below the screen.
      scroll.jumpTo(0);
      await _frames(t, 2);
      await _press(t, _right);
      expect(_at(), isNot('Item 20'));
      final at = FocusManager.instance.primaryFocus!.rect;
      expect(at.top, greaterThanOrEqualTo(0));
      expect(at.bottom, lessThanOrEqualTo(_tv.height));
    });

    // The rail's collapse button sits at the right of its header, narrower
    // than the tiles under it.
    testWidgets('DOWN from a narrow button at its top reaches the tiles', (
      t,
    ) async {
      t.view.physicalSize = _tv;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          home: Material(
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 200,
                child: FocusTraversalGroup(
                  policy: TvRailPolicy(),
                  child: const Column(
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: _Stop('Collapse', width: 40),
                      ),
                      _Stop('Home', width: 180),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await _focus(t, 'Collapse');
      await _press(t, _down);
      expect(_at(), 'Home');
      await _press(t, _up);
      expect(_at(), 'Collapse');
    });

    _tvTest('DOWN never leaves it for a card scrolled in under it', (
      t,
    ) async {
      await _shell(t, {
        '/a': (_) => const Scaffold(
          body: Stack(
            clipBehavior: Clip.none,
            children: [
              // A row's card, scrolled left until it's partly under the rail.
              Positioned(left: -60, top: 400, child: _Stop('Card', width: 100)),
            ],
          ),
        ),
      });
      await _focus(t, 'Rail Two');
      await _press(t, _down);
      expect(_at(), 'Rail Two');
    });

    _tvTest('RIGHT from a tile level with a hidden stop', (t) async {
      await _shell(t, _listAndTitle());
      await _push(t, '/a/title');
      for (final tile in ['tvNavRail', 'Rail Two']) {
        tvLastContentFocus = null;
        await _focus(t, tile);
        await _press(t, _right);
        expect(_at(), 'Search Movie', reason: 'from $tile');
      }
    });
  });

  group('a row with buttons of its own', () {
    Widget list() => _page('Activity', [
      for (final n in ['1', '2', '3'])
        _RowStop('Row $n', [
          TvRowActions(child: _Stop('Grab $n', width: 80)),
          TvRowActions(child: _Stop('Remove $n', width: 80)),
        ]),
    ]);

    _tvTest('is one stop for UP and DOWN', (t) async {
      await _shell(t, {'/a': (_) => list()});
      expect(_at(), 'Row 1');
      await _press(t, _down);
      expect(_at(), 'Row 2');
      await _press(t, _down);
      expect(_at(), 'Row 3');
      await _press(t, _up);
      expect(_at(), 'Row 2');
    });

    _tvTest('RIGHT steps onto its buttons and along, LEFT back', (t) async {
      await _shell(t, {'/a': (_) => list()});
      await _press(t, _down);
      await _press(t, _right);
      expect(_at(), 'Grab 2');
      await _press(t, _right);
      expect(_at(), 'Remove 2');
      await _press(t, _right);
      expect(_at(), 'Remove 2');
      await _press(t, _left);
      expect(_at(), 'Grab 2');
      await _press(t, _left);
      expect(_at(), 'Row 2');
      await _press(t, _left);
      expect(FocusManager.instance.primaryFocus, tvNavBarNode);
    });

    _tvTest('UP and DOWN from a button go on from its row', (t) async {
      await _shell(t, {'/a': (_) => list()});
      await _press(t, _down);
      await _press(t, _right);
      await _press(t, _right);
      expect(_at(), 'Remove 2');
      await _press(t, _down);
      expect(_at(), 'Row 3');
      await _press(t, _right);
      expect(_at(), 'Grab 3');
      await _press(t, _up);
      expect(_at(), 'Row 2');
    });

    _tvTest('DOWN from above its buttons is the row', (t) async {
      await _shell(t, {
        '/a': (_) => _page('Activity', [
          const Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [_Stop('Filter', width: 80)],
          ),
          for (final n in ['1', '2'])
            _RowStop('Row $n', [
              TvRowActions(child: _Stop('Grab $n', width: 80)),
              TvRowActions(child: _Stop('Remove $n', width: 80)),
            ]),
        ]),
      });
      await _focus(t, 'Filter');
      await _press(t, _down);
      expect(_at(), 'Row 1');
    });

    _tvTest('RIGHT with nothing lit isn\'t onto a row\'s button', (t) async {
      await _shell(t, {'/a': (_) => list()});
      // As when a page gave up looking: the page itself holds the remote.
      final page = _node('Row 1').enclosingScope!;
      TvContentTraversalPolicy().inDirection(page, TraversalDirection.right);
      await _frames(t, 2);
      expect(_at(), isNot(startsWith('Grab')));
      expect(_at(), isNot(startsWith('Remove')));
    });

    _tvTest('off a TV the buttons are ordinary stops', (t) async {
      isTvDevice = false;
      await _shell(t, {'/a': (_) => list()});
      expect(_has('tvRowActions'), isFalse);
      await _focus(t, 'Row 1');
      await _press(t, LogicalKeyboardKey.tab);
      expect(_at(), 'Grab 1');
    });
  });

  group('what is only read', () {
    Widget facts() => _page('Title', const [
      SizedBox(height: 120),
      _Stop('Search Movie'),
      TvReadStop(child: Text('Overview and facts')),
      _Stop('History'),
    ]);

    _tvTest('is a stop on a TV, outlined while the remote is on it', (
      t,
    ) async {
      await _shell(t, {'/a': (_) => facts()});
      expect(_at(), 'Search Movie');
      final outline = find.descendant(
        of: find.byType(TvReadStop),
        matching: find.byType(Positioned),
      );
      expect(outline, findsNothing);
      await _press(t, _down);
      expect(_at(), 'tvReadStop');
      expect(outline, findsOneWidget);
      await _press(t, _down);
      expect(_at(), 'History');
      expect(outline, findsNothing);
    });

    _tvTest('and nothing but itself off a TV', (t) async {
      isTvDevice = false;
      await _shell(t, {'/a': (_) => facts()});
      expect(_has('tvReadStop'), isFalse);
      expect(
        find.descendant(
          of: find.byType(TvReadStop),
          matching: find.byType(Padding),
        ),
        findsNothing,
      );
    });
  });

  group('a title page that scrolls', () {
    late ScrollController scroll;
    Widget title(List<Widget> top, List<Widget> end) => Scaffold(
      body: TvPageEnds(
        child: CustomScrollView(
          controller: scroll,
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 240,
              leading: const _Stop('Back', width: 56),
              flexibleSpace: const FlexibleSpaceBar(
                background: Align(
                  alignment: Alignment.bottomLeft,
                  child: TvOpenHeaderOnly(
                    child: Row(children: [_Stop('Watch'), _Stop('Edit')]),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...top,
                  const SizedBox(height: 500),
                  ...end,
                ],
              ),
            ),
          ],
        ),
      ),
    );
    Future<void> open(
      WidgetTester t, {
      List<Widget> top = const [_Stop('File')],
      List<Widget> end = const [
        _Stop('History'),
        SizedBox(height: 700, child: Text('Nothing yet')),
      ],
    }) async {
      scroll = ScrollController();
      addTearDown(scroll.dispose);
      await _shell(t, {'/a': (_) => title(top, end)});
    }

    _tvTest('opens on its header\'s first button', (t) async {
      await open(t);
      expect(_at(), 'Watch');
    });

    _tvTest('keeps the header\'s buttons out once it has scrolled', (
      t,
    ) async {
      await open(t);
      expect(_node('Watch').canRequestFocus, isTrue);
      scroll.jumpTo(150);
      await _frames(t, 2);
      expect(_node('Watch').canRequestFocus, isFalse);
      expect(_node('Edit').canRequestFocus, isFalse);
      scroll.jumpTo(0);
      await _frames(t, 2);
      expect(_node('Watch').canRequestFocus, isTrue);
    });

    _tvTest('UP from its first stop opens the header again', (t) async {
      await open(t);
      scroll.jumpTo(150);
      await _frames(t, 2);
      await _focus(t, 'File');
      await _press(t, _up);
      await _frames(t, 12);
      expect(scroll.offset, 0);
      expect(_at(), 'Watch');
    });

    _tvTest('UP from a button of its first row opens the header too', (
      t,
    ) async {
      // A season: a tall row, its buttons in the middle of it.
      await open(
        t,
        top: const [
          _RowStop('Season 1', [
            TvRowActions(child: _Stop('Search Season', width: 80)),
          ], height: 120),
        ],
      );
      scroll.jumpTo(150);
      await _frames(t, 2);
      await _focus(t, 'Search Season');
      await _press(t, _up);
      await _frames(t, 12);
      expect(scroll.offset, 0);
      expect(_at(), 'Watch');
    });

    _tvTest('UP from the bar\'s Back button leaves the page where it is', (
      t,
    ) async {
      await open(t);
      scroll.jumpTo(150);
      await _frames(t, 2);
      await _focus(t, 'Back');
      await _press(t, _up);
      await _frames(t, 12);
      expect(scroll.offset, 150);
      expect(_at(), 'Back');
    });

    _tvTest('UP with the header open goes to the button above', (t) async {
      await open(
        t,
        top: const [
          Padding(padding: EdgeInsets.only(left: 160), child: _Stop('Tags')),
        ],
      );
      await _focus(t, 'Tags');
      await _press(t, _up);
      await _frames(t, 12);
      expect(_at(), 'Edit');
    });

    _tvTest('DOWN from its last stop scrolls on', (t) async {
      await open(t);
      await _press(t, _down);
      await _press(t, _down);
      expect(_at(), 'History');
      final before = scroll.offset;
      expect(before, lessThan(scroll.position.maxScrollExtent));
      await _press(t, _down);
      await _frames(t, 8);
      expect(scroll.offset, greaterThan(before + 100));
      expect(_at(), 'History');
    });

    _tvTest('and at the page\'s end the remote stays where it is', (
      t,
    ) async {
      await open(t);
      await _press(t, _down);
      await _press(t, _down);
      for (var i = 0; i < 6; i++) {
        await _press(t, _down);
      }
      // As far as it goes with the remote's stop still in sight, under the
      // bar: never scrolled away under it, where OK would press it unseen.
      expect(scroll.offset, greaterThan(0));
      final at = _node('History').rect;
      expect(at.top, greaterThanOrEqualTo(_tv.height * 0.16));
      expect(at.bottom, lessThanOrEqualTo(_tv.height));
      expect(_at(), 'History');
    });

    _tvTest('DOWN from a stop already up under the bar moves nothing', (
      t,
    ) async {
      await open(t);
      scroll.jumpTo(718);
      await _frames(t, 2);
      await _focus(t, 'History');
      expect(_node('History').rect.top, lessThan(_tv.height * 0.16 + 8));
      await _press(t, _down);
      await _frames(t, 8);
      expect(scroll.offset, 718);
      expect(_at(), 'History');
    });

    _tvTest('DOWN reads on to the end of a last stop taller than the screen', (
      t,
    ) async {
      await open(
        t,
        end: const [
          TvReadStop(
            child: SizedBox(height: 1200, child: Text('A long overview')),
          ),
        ],
      );
      await _focus(t, 'tvReadStop');
      for (var i = 0; i < 12; i++) {
        await _press(t, _down);
      }
      expect(scroll.offset, closeTo(scroll.position.maxScrollExtent, 1));
      expect(_at(), 'tvReadStop');
    });

    _tvTest('in between, UP and DOWN move stop by stop', (t) async {
      await open(t);
      await _press(t, _down);
      expect(_at(), 'File');
      await _press(t, _down);
      expect(_at(), 'History');
      await _press(t, _up);
      expect(_at(), 'File');
    });

    _tvTest('off a TV the header\'s buttons stay, and nothing listens', (
      t,
    ) async {
      isTvDevice = false;
      await open(t);
      expect(_has('tvPageEnds'), isFalse);
      scroll.jumpTo(150);
      await _frames(t, 2);
      expect(_node('Watch').canRequestFocus, isTrue);
      await _focus(t, 'History');
      final before = scroll.offset;
      await _press(t, _down);
      expect(scroll.offset, before);
    });
  });

  group('cards piled one over another', () {
    // As a collection's card: its own buttons at the far right, its movies
    // in a strip under them from the left.
    Widget card(String n) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Collection $n')),
            TvChrome(
              child: TvFocusRow(
                stacked: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Stop('Monitor $n', width: 90),
                    _Stop('Edit $n', width: 90),
                  ],
                ),
              ),
            ),
          ],
        ),
        SizedBox(
          height: 150,
          child: TvFocusRow(
            stacked: true,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final m in ['1', '2', '3'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: _Stop('Movie $n$m', width: 100),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
    late ScrollController scroll;
    Future<void> open(WidgetTester t) async {
      scroll = ScrollController();
      addTearDown(scroll.dispose);
      await _shell(t, {
        '/a': (_) => Scaffold(
          appBar: AppBar(title: const Text('Collections')),
          body: ListView(
            controller: scroll,
            children: [
              const SizedBox(height: 40),
              for (final n in ['A', 'B', 'C', 'D']) card(n),
            ],
          ),
        ),
      });
    }

    _tvTest('open on the first movie, not on a card\'s buttons', (t) async {
      await open(t);
      expect(_at(), 'Movie A1');
    });

    _tvTest('UP from any movie reaches its card\'s buttons', (t) async {
      await open(t);
      await _press(t, _right);
      expect(_at(), 'Movie A2');
      await _press(t, _up);
      expect(_at(), 'Monitor A');
      await _press(t, _right);
      expect(_at(), 'Edit A');
      // And back down to the movie it left.
      await _press(t, _down);
      expect(_at(), 'Movie A2');
    });

    _tvTest('UP from a card further down is its own buttons', (t) async {
      await open(t);
      await _press(t, _down);
      await _press(t, _down);
      expect(_at(), 'Movie B1');
      await _press(t, _up);
      expect(_at(), 'Monitor B');
      await _press(t, _up);
      expect(_at(), 'Movie A1');
    });

    _tvTest('DOWN goes on to the next card\'s buttons, then its movies', (
      t,
    ) async {
      await open(t);
      await _press(t, _down);
      expect(_at(), 'Monitor B');
      await _press(t, _down);
      expect(_at(), 'Movie B1');
    });

    _tvTest('and brings a card further down into view', (t) async {
      await open(t);
      for (var i = 0; i < 6; i++) {
        await _press(t, _down);
      }
      expect(_at(), 'Movie D1');
      expect(scroll.offset, greaterThan(0));
      final at = _node('Movie D1').rect;
      expect(at.bottom, lessThanOrEqualTo(_tv.height));
    });

    _tvTest('LEFT past a card\'s first movie is the rail', (t) async {
      await open(t);
      await _press(t, _left);
      expect(FocusManager.instance.primaryFocus, tvNavBarNode);
    });
  });

  group('when what the remote was on goes away', () {
    _tvTest('it moves to what stands nearest', (t) async {
      final rows = ValueNotifier(['A', 'B', 'C']);
      addTearDown(rows.dispose);
      await _shell(t, {
        '/a': (_) => TvFocusKeeper(
          child: ValueListenableBuilder(
            valueListenable: rows,
            builder: (_, names, _) => _page('Activity', [
              for (final n in names) _Stop('Download $n', key: ValueKey(n)),
            ]),
          ),
        ),
      });
      await _press(t, _down);
      expect(_at(), 'Download B');
      rows.value = ['A', 'C'];
      await _frames(t, 4);
      // C is where B was.
      expect(_at(), 'Download C');
      rows.value = ['A'];
      await _frames(t, 4);
      expect(_at(), 'Download A');
    });

    _tvTest('but not while a dialog over the page has it', (t) async {
      final rows = ValueNotifier(['A', 'B', 'C']);
      addTearDown(rows.dispose);
      await _shell(t, {
        '/a': (_) => TvFocusKeeper(
          child: ValueListenableBuilder(
            valueListenable: rows,
            builder: (_, names, _) => _page('Activity', [
              for (final n in names) _Stop('Download $n', key: ValueKey(n)),
            ]),
          ),
        ),
      });
      await _press(t, _down);
      expect(_at(), 'Download B');
      showDialog<void>(
        context: _root.currentContext!,
        builder: (_) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [_Stop('Confirm', autofocus: true), _Stop('Cancel')],
          ),
        ),
      );
      await _frames(t, 8);
      expect(_at(), 'Confirm');
      rows.value = ['A', 'C'];
      await _frames(t, 4);
      await _press(t, _down);
      expect(_at(), 'Cancel');
      // Closed, the page has it again, on what's in B's place.
      Navigator.of(_root.currentContext!).pop();
      await _frames(t, 8);
      expect(_at(), 'Download C');
    });

    _tvTest('off a TV the page is left to itself', (t) async {
      isTvDevice = false;
      await _shell(t, {
        '/a': (_) => TvFocusKeeper(
          child: _page('Activity', const [_Stop('Download A')]),
        ),
      });
      expect(_has('tvKeeper'), isFalse);
    });
  });

  group('a field to type in', () {
    testWidgets('is as tall as its two lines in a dialog', (t) async {
      t.view.physicalSize = _tv;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final text = TextEditingController();
      addTearDown(text.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AlertDialog(
              title: const Text('New Tag'),
              content: TvTextField(controller: text, label: 'Tag'),
            ),
          ),
        ),
      );
      await _frames(t);
      expect(t.getSize(find.byType(TvTextField)).height, lessThan(120));
    });
  });

  test('every page of Manage has a landing on a TV', () {
    final router = File('lib/routing/app_router.dart').readAsStringSync();
    // Each is wrapped in one on a TV, and only there.
    expect(
      router,
      contains(
        '_managePage(Widget child) =>\n'
        '    _fadePage(isTvDevice ? TvPageLanding(child: child) : child);',
      ),
    );
    final routes = RegExp(
      r"path: '(/arr[^']*)',\s*pageBuilder: \([^)]*\) => (\w+)\(",
    ).allMatches(router).toList();
    expect(routes.length, greaterThanOrEqualTo(12));
    expect(
      {
        for (final m in routes)
          if (m.group(2) != '_managePage') m.group(1),
      },
      isEmpty,
    );
    // And no route of the section is written another way.
    expect(
      RegExp(r"path: '/arr").allMatches(router).length,
      routes.length,
    );
  });
}
