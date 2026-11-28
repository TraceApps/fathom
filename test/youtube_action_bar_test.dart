import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/models/youtube_video.dart';
import 'package:fathom/theme/app_theme.dart';
import 'package:fathom/widgets/youtube_actions.dart';

/// The action bar must never overflow.
///
/// Crammed onto the channel row it overflowed by 304px at 420px wide — the
/// striped warning, on the watch page. A Wrap can't do that: the buttons drop
/// to another line instead. These widths are the ones that matter: a narrow
/// window, the content column beside the Up Next rail, and full width.
void main() {
  final video = YoutubeVideo(
    id: 'v1',
    title: 'A video',
    author: 'Someone',
    url: 'https://www.youtube.com/watch?v=v1',
    thumbnailUrl: 't',
  );

  Future<void> pumpAt(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.dark(const Color(0xFF7C4DFF)),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: YoutubeVideoActionBar(video: video),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  for (final width in [320.0, 420.0, 600.0, 900.0, 1400.0]) {
    testWidgets('fits at ${width.toInt()}px', (tester) async {
      await pumpAt(tester, width);
      expect(tester.takeException(), isNull,
          reason: 'the action bar overflowed at ${width.toInt()}px');
      expect(find.byTooltip('Copy Link'), findsOneWidget);
      expect(find.byTooltip('Open in Browser'), findsOneWidget);
    });
  }

  testWidgets('actions are labelled, not guessable icons', (tester) async {
    await pumpAt(tester, 900);
    for (final label in ['Play Next', 'Add to Queue', 'Copy Link',
                         'Open in Browser']) {
      expect(find.byTooltip(label), findsOneWidget);
    }
  });

  testWidgets('the action bar offers Download', (tester) async {
    // It didn't. Download was added to the menu only, so the watch page — the
    // first place anyone looks — silently lacked it.
    await pumpAt(tester, 900);
    expect(find.byTooltip('Download'), findsOneWidget);
  });

  testWidgets('the bar and the menu offer the same actions', (tester) async {
    // Two hand-written lists drifted within a day of being written. Both are
    // built from actionsFor now; this fails if they diverge again.
    late List<String> barLabels;
    late List<String> menuLabels;

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.dark(const Color(0xFF7C4DFF)),
        home: Scaffold(
          body: Consumer(builder: (context, ref, _) {
            barLabels = [
              for (final a in YoutubeActions.actionsFor(context, ref, video))
                a.label,
            ];
            menuLabels = [
              for (final a in YoutubeActions.menuItems(context, ref, video))
                a.label,
            ];
            return const SizedBox();
          }),
        ),
      ),
    ));
    await tester.pump();

    // The menu adds two entries the bar surfaces separately (not via the shared
    // actionsFor list): a playlist entry (the bar's leading widget) and
    // "Play Audio" (the bar's leading "Listen" pill).
    final menu = menuLabels
        .where((l) => !l.contains('Playlist') && l != 'Play Audio')
        .toSet();
    expect(menu, equals(barLabels.toSet()),
        reason: 'the bar and the menu must offer the same actions');
    expect(barLabels, contains('Download'));
  });
}
