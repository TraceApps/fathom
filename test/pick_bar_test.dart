import 'dart:io';

import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/widgets/pick_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// One bar while picking, everywhere: a Jellyfin library, Manage's lists and
// YouTube downloads had three that looked and behaved differently.

Iterable<File> _sources() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart') && !f.path.contains('/generated/'));

Future<List<String>> _show(WidgetTester t, double width, {int count = 2}) async {
  t.view.physicalSize = Size(width, 400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final ran = <String>[];
  await t.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: PickBar(
          count: count,
          onCancel: () => ran.add('cancel'),
          onSelectAll: () => ran.add('all'),
          actions: [
            for (final name in ['Watched', 'Favorite', 'Playlist'])
              PickAction(Icons.check_rounded, name, () => ran.add(name)),
            PickAction(
              Icons.delete_outline_rounded,
              'Delete',
              () => ran.add('Delete'),
              danger: true,
            ),
          ],
        ),
      ),
    ),
  );
  return ran;
}

void main() {
  test('only the shared bar counts what is picked', () {
    final own = [
      for (final f in _sources())
        if (RegExp(r'l\.(selectionSelectAll|ytSelectAll|ytNSelected)\b')
            .hasMatch(f.readAsStringSync()))
          f.path,
    ];
    expect(own, ['lib/widgets/pick_bar.dart']);
  });

  testWidgets('a wide bar has each action as a button', (t) async {
    final ran = await _show(t, 900);
    await t.tap(find.byTooltip('Delete'));
    await t.tap(find.text('Select All'));
    await t.tap(find.byTooltip('Cancel'));
    expect(ran, ['Delete', 'all', 'cancel']);
    expect(t.takeException(), isNull);
  });

  testWidgets('a phone folds the actions into one menu', (t) async {
    final ran = await _show(t, 360);
    expect(find.byTooltip('Delete'), findsNothing);
    await t.tap(find.byTooltip('More Options'));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();
    expect(ran, ['Delete']);
    expect(t.takeException(), isNull);
  });

  testWidgets('with nothing picked, the actions wait', (t) async {
    final ran = await _show(t, 900, count: 0);
    await t.tap(find.byTooltip('Delete'), warnIfMissed: false);
    expect(ran, isEmpty);
    await t.tap(find.text('Select All'));
    expect(ran, ['all']);
  });
}
