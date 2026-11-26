import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/services/tv_mode.dart';
import 'package:fathom/widgets/reorder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Home Layout and Navigation are reordered by dragging, which a remote
// can't do. On a TV each row has Move Up and Move Down.

Future<List<(int, int)>> _show(WidgetTester t, int index) async {
  final moves = <(int, int)>[];
  await t.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: TvMoveButtons(
          index: index,
          count: 3,
          onMove: (a, b) => moves.add((a, b)),
        ),
      ),
    ),
  );
  return moves;
}

void main() {
  tearDown(() => isTvDevice = false);

  testWidgets('nothing off a TV, where rows are dragged', (t) async {
    await _show(t, 1);
    expect(find.byType(IconButton), findsNothing);
  });

  testWidgets('on a TV a row moves up and down', (t) async {
    isTvDevice = true;
    final moves = await _show(t, 1);
    await t.tap(find.byTooltip('Move Up'));
    await t.tap(find.byTooltip('Move Down'));
    expect(moves, [(1, 0), (1, 2)]);
  });

  testWidgets('the first row has nowhere up to go, the last nowhere down', (
    t,
  ) async {
    isTvDevice = true;
    var moves = await _show(t, 0);
    await t.tap(find.byTooltip('Move Up'), warnIfMissed: false);
    expect(moves, isEmpty);
    moves = await _show(t, 2);
    await t.tap(find.byTooltip('Move Down'), warnIfMissed: false);
    expect(moves, isEmpty);
  });
}
