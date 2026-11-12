import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/widgets/player_controls.dart';

// Chapter titles from the video that prompted this (FIdOdiUQ91Y).
const _chapters = <PlayerMarker>[
  (position: Duration.zero, label: 'Why Tim Left the U.S.'),
  (position: Duration(seconds: 63), label: 'How Life in Kenya Transformed Him'),
  (position: Duration(seconds: 96), label: 'The 4 Bedroom Mansion'),
];

void main() {
  late Player player;
  setUpAll(() {
    MediaKit.ensureInitialized();
    player = Player();
  });

  test('the current chapter is the last one that has started', () {
    expect(chapterAt(_chapters, Duration.zero)?.label, 'Why Tim Left the U.S.');
    expect(
      chapterAt(_chapters, const Duration(seconds: 70))?.label,
      'How Life in Kenya Transformed Him',
    );
    expect(
      chapterAt(_chapters, const Duration(hours: 1))?.label,
      'The 4 Bedroom Mansion',
    );
    expect(
      chapterAt([
        (position: const Duration(seconds: 5), label: 'Late'),
      ], Duration.zero),
      isNull,
      reason: 'no chapter before the first one starts',
    );
  });

  Future<void> pump(
    WidgetTester tester,
    double width, {
    List<PlayerMarker> chapters = _chapters,
    VoidCallback? onChapters,
  }) async {
    tester.view.physicalSize = Size(width, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          backgroundColor: Colors.black,
          body: FathomPlayerControls(
            player: player,
            title: 'A video',
            isLive: false,
            loading: false,
            onBack: () {},
            onSeekBy: (_) {},
            onToggleMute: () {},
            onChapters: onChapters,
            chapters: chapters,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the pill names the chapter and opens the list', (tester) async {
    var opened = 0;
    await pump(tester, 1280, onChapters: () => opened++);
    expect(find.text('Why Tim Left the U.S.'), findsOneWidget);
    await tester.tap(find.text('Why Tim Left the U.S.'));
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the pill fits on a phone without overflowing', (tester) async {
    await pump(tester, 400, onChapters: () {});
    expect(tester.takeException(), isNull);
    // Shortened, but still there: a phone is where it helps most.
    expect(find.text('Why Tim Left the U.S.'), findsOneWidget);
  });

  // A tablet in landscape showed the right group (Next, CC, settings,
  // fullscreen) stranded mid-bar: the pill's Flexible(flex: 3) kept three
  // quarters of the free room beside a flex-1 Spacer. The right group must sit
  // exactly where it does without chapters, flush right.
  for (final width in [800.0, 1000.0, 1280.0, 2000.0]) {
    testWidgets('the right group stays flush right at ${width.toInt()}px', (
      tester,
    ) async {
      await pump(tester, width, chapters: const [], onChapters: () {});
      final without = tester
          .getTopRight(find.byIcon(Icons.settings_rounded))
          .dx;
      await pump(tester, width, onChapters: () {});
      expect(find.text('Why Tim Left the U.S.'), findsOneWidget);
      final withPill = tester
          .getTopRight(find.byIcon(Icons.settings_rounded))
          .dx;
      expect(withPill, moreOrLessEquals(without, epsilon: 0.5));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('no chapters, no pill', (tester) async {
    await pump(tester, 1280, chapters: const []);
    expect(find.text('Why Tim Left the U.S.'), findsNothing);
  });
}
