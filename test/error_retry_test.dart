import 'dart:io';

import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/widgets/error_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// A page that couldn't load says so the same way everywhere, and offers
// Retry: no page is a dead end with only an error's text on it.

/// Every call of [name] in [source], whole, with its arguments.
Iterable<String> _calls(String source, String name) sync* {
  for (final m in RegExp('(?<![A-Za-z_])$name\\(').allMatches(source)) {
    if (source.substring(0, m.start).endsWith('class ')) continue;
    var depth = 1;
    var i = m.end;
    while (depth > 0 && i < source.length) {
      if (source[i] == '(') depth++;
      if (source[i] == ')') depth--;
      i++;
    }
    final call = source.substring(m.start, i);
    // The widget's own constructor.
    if (call.contains('super.key')) continue;
    yield call;
  }
}

void main() {
  final files = [
    for (final dir in ['lib/screens', 'lib/widgets', 'lib/routing'])
      ...Directory(dir).listSync(recursive: true).whereType<File>().where(
        (f) => f.path.endsWith('.dart'),
      ),
  ];

  test('every full-page error view offers Retry', () {
    final without = <String>[];
    for (final f in files) {
      for (final call in _calls(f.readAsStringSync(), 'ErrorView')) {
        if (!call.contains('onRetry')) without.add('${f.path}: $call');
      }
    }
    expect(without, isEmpty);
  });

  test('no page shows an error as bare text', () {
    final bare = RegExp(
      r"error: \(e, \w+\) =>\s*(Center\(\s*child: )?(Padding\([^;]{0,80}child: )?Text\(\s*'\$e'",
    );
    final found = <String>[
      for (final f in files)
        if (f.path.contains('/screens/'))
          for (final m in bare.allMatches(f.readAsStringSync()))
            '${f.path}: ${m.group(0)}',
    ];
    expect(found, isEmpty);
  });

  testWidgets('Retry is there, and asks again', (t) async {
    var asked = 0;
    await t.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ErrorView(message: 'Could not reach the server.', onRetry: () => asked++),
        ),
      ),
    );
    expect(find.text('Could not reach the server.'), findsOneWidget);
    await t.tap(find.text('Retry'));
    expect(asked, 1);
  });

  testWidgets('on a wide window Retry is a button, not a banner', (t) async {
    t.view.physicalSize = const Size(1600, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: ErrorView(message: 'Could not reach Radarr.', onRetry: () {})),
      ),
    );
    final button = t.getSize(find.ancestor(
      of: find.text('Retry'),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    ));
    expect(button.width, lessThanOrEqualTo(320));
  });
}
