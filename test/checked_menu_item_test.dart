import 'dart:io';

import 'package:fathom/widgets/checked_menu_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// On a TV, Select on a line of a checked menu (Sort, Filter) did nothing:
// Flutter's own checked line holds a ListTile that takes the remote's focus
// for itself and can't be pressed. Seen on the Android TV emulator in a
// library's Sort menu; Manage's Filter and History menus had it too.

Future<String?> _pickSecondWithRemote(
  WidgetTester t,
  PopupMenuEntry<String> Function(String value, bool checked) line,
) async {
  String? got;
  await t.pumpWidget(
    MaterialApp(
      // As on a TV.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          navigationMode: NavigationMode.directional,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: PopupMenuButton<String>(
          onSelected: (v) => got = v,
          itemBuilder: (_) => [
            for (final v in ['a', 'b', 'c']) line(v, v == 'a'),
          ],
        ),
      ),
    ),
  );
  await t.tap(find.byType(PopupMenuButton<String>));
  await t.pumpAndSettle();
  for (var i = 0; i < 6 && got == null; i++) {
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    if (i == 0) continue; // first press lands on the first line
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pumpAndSettle();
  }
  return got;
}

void main() {
  testWidgets('the remote can pick a line', (t) async {
    final got = await _pickSecondWithRemote(
      t,
      (v, checked) =>
          CheckedMenuItem<String>(value: v, checked: checked, child: Text(v)),
    );
    expect(got, 'b');
  });

  testWidgets("Flutter's own checked line is why: Select does nothing", (
    t,
  ) async {
    final got = await _pickSecondWithRemote(
      t,
      (v, checked) => CheckedPopupMenuItem<String>(
        value: v,
        checked: checked,
        child: Text(v),
      ),
    );
    // If this starts passing, Flutter fixed it; ours can still stay.
    expect(got, isNot('b'));
  });

  testWidgets('the line in use is ticked', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PopupMenuButton<String>(
            itemBuilder: (_) => [
              CheckedMenuItem(value: 'a', checked: true, child: const Text('a')),
              CheckedMenuItem(value: 'b', checked: false, child: const Text('b')),
            ],
          ),
        ),
      ),
    );
    await t.tap(find.byType(PopupMenuButton<String>));
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    await t.tap(find.text('b'));
    await t.pumpAndSettle();
  });

  test('no screen uses the Material checked line', () {
    final material = 'Checked' 'PopupMenuItem';
    expect(
      [
        for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
          if (f.path.endsWith('.dart') && f.readAsStringSync().contains(material))
            f.path,
      ],
      isEmpty,
    );
  });
}
