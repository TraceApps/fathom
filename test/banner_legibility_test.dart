import 'package:fathom/theme/status_colors.dart';
import 'package:fathom/widgets/featured_hero.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The Home banner's words are white on a picture. In the light theme the
// picture faded into a white page right behind them, so over a pale picture,
// or none, the description was pale on pale.

Gradient _gradientOf(Widget w) =>
    ((w as Positioned).child as DecoratedBox).decoration is BoxDecoration
    ? (((w).child as DecoratedBox).decoration as BoxDecoration).gradient!
    : throw StateError('not a gradient');

void main() {
  test('the light theme puts a dark shade behind the words', () {
    final light = bannerScrims(ThemeData(brightness: Brightness.light));
    final dark = bannerScrims(ThemeData(brightness: Brightness.dark));
    expect(light.length, dark.length + 1);
    final shade = _gradientOf(light.first) as LinearGradient;
    expect(shade.begin, Alignment.bottomLeft);
    // White words on that shade over a white picture still read.
    final behind = Color.alphaBlend(shade.colors.first, Colors.white);
    expect(contrastOf(Colors.white, behind), greaterThan(4.5));
  });

  test('and keeps the fade into the page to the bottom edge', () {
    LinearGradient fade(Brightness b) =>
        bannerScrims(ThemeData(brightness: b))
                .map(_gradientOf)
                .whereType<LinearGradient>()
                .firstWhere((g) => g.begin == Alignment.topCenter);
    expect(fade(Brightness.light).stops!.first, greaterThan(0.8));
    expect(fade(Brightness.dark).stops!.first, lessThan(0.5));
  });

  testWidgets('a title with no backdrop gets a dark field, not an icon', (
    t,
  ) async {
    for (final b in Brightness.values) {
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: b),
          home: const SizedBox(
            width: 400,
            height: 200,
            child: BannerBackdropFallback(),
          ),
        ),
      );
      expect(find.byType(Icon), findsNothing);
      final box = t.widget<DecoratedBox>(
        find.descendant(
          of: find.byType(BannerBackdropFallback),
          matching: find.byType(DecoratedBox),
        ),
      );
      final g = (box.decoration as BoxDecoration).gradient as LinearGradient;
      for (final c in g.colors) {
        expect(contrastOf(Colors.white, c), greaterThan(4.5), reason: '$b');
      }
    }
  });
}
