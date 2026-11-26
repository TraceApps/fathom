import 'dart:io';

import 'package:fathom/widgets/shimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The rule for loading: a page that will show posters loads as their shapes;
// a list or a form loads behind the spinner. A person's page and a film
// series were the two poster pages still behind a spinner.

void main() {
  test('no page with a poster grid loads behind the spinner', () {
    final grid = RegExp(r'SliverGrid|GridView|ItemGridBody|PosterTile');
    final spinner = RegExp(r'loading: \(\) => const Center\(child: AppSpinner\(\)\)');
    final both = [
      for (final f in Directory('lib/screens').listSync().whereType<File>())
        if (f.path.endsWith('.dart') &&
            grid.hasMatch(f.readAsStringSync()) &&
            spinner.hasMatch(f.readAsStringSync()))
          f.path,
    ]..sort();
    // Discover's is its request list, which shares a file with the grids.
    expect(both, ['lib/screens/discover_screen.dart']);
  });

  for (final width in [360.0, 1400.0]) {
    testWidgets('the header and grid skeleton fits at ${width.toInt()}', (
      t,
    ) async {
      t.view.physicalSize = Size(width, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        const MaterialApp(home: Scaffold(body: HeaderGridSkeleton())),
      );
      await t.pump(const Duration(milliseconds: 100));
      expect(t.takeException(), isNull);
      expect(find.byType(BackButton), findsOneWidget);
      expect(find.byType(ShimmerBox), findsWidgets);
    });
  }
}
