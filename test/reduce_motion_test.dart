import 'dart:io';

import 'package:fathom/widgets/equalizer_bars.dart';
import 'package:fathom/widgets/motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Reduced motion: what moves by itself for as long as it's on screen (the
// playing bars, the recording dot, the sync pulse) stands still, and pages
// fade in without sliding.

Widget _app(Widget child, {required bool reduce}) => MaterialApp(
  builder: (context, c) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
    child: c!,
  ),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('the playing bars stand still when asked', (t) async {
    await t.pumpWidget(_app(const EqualizerBars(playing: true, color: Colors.white), reduce: true));
    await t.pump(const Duration(milliseconds: 300));
    expect(t.hasRunningAnimations, isFalse);
  });

  testWidgets('and move otherwise', (t) async {
    await t.pumpWidget(_app(const EqualizerBars(playing: true, color: Colors.white), reduce: false));
    await t.pump(const Duration(milliseconds: 300));
    expect(t.hasRunningAnimations, isTrue);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a looping controller is held at the asked value', (t) async {
    late AnimationController c;
    late bool stilled;
    await t.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, _) {
            c = AnimationController(
              vsync: t,
              duration: const Duration(seconds: 1),
            )..repeat();
            stilled = stillIfReduced(context, c, at: 1);
            return const SizedBox();
          },
        ),
        reduce: true,
      ),
    );
    expect(stilled, isTrue);
    expect(c.isAnimating, isFalse);
    expect(c.value, 1);
    c.dispose();
  });

  test('every looping pulse and the page transition ask', () {
    for (final f in [
      'lib/screens/guide_view.dart',
      'lib/screens/player_screen.dart',
      'lib/screens/exo_player_screen.dart',
      'lib/widgets/equalizer_bars.dart',
    ]) {
      expect(File(f).readAsStringSync(), contains('stillIfReduced('), reason: f);
    }
    expect(
      File('lib/routing/app_router.dart').readAsStringSync(),
      contains('if (reduceMotion(context))'),
    );
  });

  test('icon-only buttons have a name for a screen reader', () {
    for (final f in [
      'lib/widgets/media_cards.dart',
      'lib/widgets/media_section.dart',
      'lib/widgets/mini_video.dart',
      'lib/widgets/popout_video.dart',
      'lib/widgets/playback_stats.dart',
      'lib/widgets/exo_stats_panel.dart',
      'lib/widgets/tv_keyboard.dart',
      'lib/screens/profile_screen.dart',
      'lib/screens/preferences_screen.dart',
    ]) {
      expect(
        File(f).readAsStringSync(),
        contains('Semantics(button: true'),
        reason: f,
      );
    }
  });
}
