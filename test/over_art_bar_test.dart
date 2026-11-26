import 'dart:io';

import 'package:fathom/theme/status_colors.dart';
import 'package:fathom/widgets/over_art_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The top bar of a title's page sits over its artwork. Its buttons took the
// page's icon color: dark in the light theme, so over dark art Back and the
// buttons beside it all but vanished. Seen on the foldable in the light
// theme.

void main() {
  for (final b in Brightness.values) {
    testWidgets('$b: the bar\'s buttons are white on a dark disc', (t) async {
      late ButtonStyle style;
      late Color? menu;
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: b),
          home: OverArtBar(
            child: Builder(
              builder: (context) {
                style = IconButtonTheme.of(context).style!;
                menu = PopupMenuTheme.of(context).iconColor;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      final icon = style.foregroundColor!.resolve({})!;
      final disc = style.backgroundColor!.resolve({})!;
      expect(icon, Colors.white);
      expect(menu, Colors.white);
      // On a white page and on black art alike.
      for (final under in [Colors.white, Colors.black]) {
        expect(
          contrastOf(icon, Color.alphaBlend(disc, under)),
          greaterThan(under == Colors.white ? 3.0 : 4.5),
        );
      }
    });
  }

  test('every page with a bar over artwork uses it', () {
    for (final f in [
      'lib/screens/detail_screen.dart',
      'lib/screens/seerr_detail_screen.dart',
      'lib/screens/collection_view.dart',
      'lib/screens/album_screen.dart',
      'lib/screens/seerr_collection_screen.dart',
    ]) {
      expect(
        File(f).readAsStringSync(),
        contains('OverArtBar(child: SliverAppBar('),
        reason: f,
      );
    }
  });
}
