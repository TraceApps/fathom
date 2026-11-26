import 'dart:io';

import 'package:fathom/widgets/page_width.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Settings and its pages keep a readable width on a wide window: a row's
// name and its switch used to sit a whole monitor apart. The list still
// spans the window, so the wheel works anywhere over it.

Future<void> _show(WidgetTester t, double width) async {
  t.view.physicalSize = Size(width, 600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            const PageHeader(child: Text('header', key: Key('header'))),
            Expanded(
              child: PageWidth(
                builder: (_, inset) => ListView(
                  key: const Key('list'),
                  padding: pageInsets(inset, const EdgeInsets.only(bottom: 8)),
                  children: const [ListTile(key: Key('row'), title: Text('A'))],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a wide window keeps rows in a centered column', (t) async {
    await _show(t, 1640);
    final row = t.getRect(find.byKey(const Key('row')));
    expect(row.width, pageMaxWidth);
    expect(row.left, 400);
    expect(t.getRect(find.byKey(const Key('list'))).width, 1640);
    expect(t.getRect(find.byKey(const Key('header'))).left, row.left);
  });

  testWidgets('a phone is untouched', (t) async {
    await _show(t, 400);
    expect(t.getRect(find.byKey(const Key('row'))).width, 400);
    expect(t.getRect(find.byKey(const Key('header'))).left, 0);
  });

  test('Settings and its pages use it', () {
    final missing = [
      for (final name in [
        'settings', 'preferences', 'accounts', 'backup', 'updates', 'support',
        'diagnostics', 'notifications', 'navigation_layout', 'home_layout',
        'keyboard_shortcuts',
      ])
        if (!File('lib/screens/${name}_screen.dart')
            .readAsStringSync()
            .contains('PageWidth('))
          name,
    ];
    expect(missing, isEmpty);
  });

  test('Administration, Requests and Downloads use it too', () {
    final files = [
      'lib/screens/admin_screen.dart',
      'lib/screens/user_edit_screen.dart',
      'lib/screens/downloads_screen.dart',
      'lib/screens/discover_screen.dart',
      for (final f in Directory('lib/screens/admin').listSync().whereType<File>())
        f.path,
    ];
    expect(
      [
        for (final f in files)
          if (!File(f).readAsStringSync().contains('PageWidth(')) f,
      ],
      isEmpty,
    );
  });

  testWidgets('a list with no padding of its own stays clear of the bars', (
    t,
  ) async {
    late EdgeInsets got;
    await t.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(1640, 600),
          padding: EdgeInsets.only(bottom: 24),
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: PageWidth(
            builder: (c, inset) {
              got = pageInsetsSafe(c, inset);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(got.bottom, 24);
  });
}
