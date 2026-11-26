import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/models/seerr_result.dart';
import 'package:fathom/widgets/seerr_poster_card.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// A Discover poster has a menu like every other poster: right-click or
// long-press for Details, and Request when it can be requested. Without it a
// finger, which has no hover, had to open the title to request it.

SeerrResult _title({int? status}) => SeerrResult.fromJson({
  'id': 1,
  'mediaType': 'movie',
  'title': 'A Movie',
  if (status != null) 'mediaInfo': {'status': status},
});

Future<void> _show(WidgetTester t, Widget card) => t.pumpWidget(
  ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(child: SizedBox(width: 176, height: 300, child: card)),
      ),
    ),
  ),
);

Future<void> _rightClick(WidgetTester t) async {
  await t.tap(find.byIcon(Icons.movie_rounded), buttons: kSecondaryButton);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('a poster in a grid offers Details and Request', (t) async {
    await _show(t, SeerrGridCard(result: _title()));
    await _rightClick(t);
    expect(find.text('Details'), findsOneWidget);
    // The hover button's, and the menu's.
    expect(find.text('Request'), findsNWidgets(2));
  });

  testWidgets('a poster in a row does too', (t) async {
    await _show(t, SeerrPosterCard(result: _title()));
    await _rightClick(t);
    expect(find.text('Details'), findsOneWidget);
    // The hover button's, and the menu's.
    expect(find.text('Request'), findsNWidgets(2));
  });

  testWidgets('one already in the library offers Details only', (t) async {
    await _show(t, SeerrGridCard(result: _title(status: 5)));
    await _rightClick(t);
    expect(find.text('Details'), findsOneWidget);
    expect(find.text('Request'), findsNothing);
  });
}
