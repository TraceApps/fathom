import 'dart:io';

import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/widgets/format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// One clock for the whole app: the viewer's language decides its form, and
// a device set to 24 hours gets 24 hours. Live TV used to say AM and PM to
// everyone.

Future<String> _shown(
  WidgetTester t,
  DateTime time, {
  required Locale locale,
  required bool use24,
}) async {
  late String text;
  await t.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: use24),
        child: child!,
      ),
      home: Builder(
        builder: (context) {
          text = clockTime(context, time);
          return const SizedBox();
        },
      ),
    ),
  );
  await t.pump();
  // The narrow space some languages put before AM/PM reads as a plain one.
  return text.replaceAll(' ', ' ');
}

void main() {
  final afternoon = DateTime(2026, 11, 25, 15, 5);

  testWidgets('English, 12 hours: 3:05 PM', (t) async {
    expect(
      await _shown(t, afternoon, locale: const Locale('en'), use24: false),
      '3:05 PM',
    );
  });

  testWidgets('a device set to 24 hours gets 15:05, in English too', (t) async {
    expect(
      await _shown(t, afternoon, locale: const Locale('en'), use24: true),
      '15:05',
    );
  });

  testWidgets("a server's UTC time shows as the viewer's own", (t) async {
    final utc = DateTime.utc(2026, 11, 25, 15, 5);
    final local = utc.toLocal();
    final shown = await _shown(t, utc, locale: const Locale('en'), use24: true);
    expect(
      shown,
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}',
    );
  });

  test('no screen builds a clock by hand', () {
    // The pattern the Live TV screens used.
    final byHand = RegExp(r"hour < 12 \? 'AM' : 'PM'");
    expect(
      [
        for (final f in ['lib/screens/guide_view.dart', 'lib/screens/program_detail_screen.dart', 'lib/widgets/live_info_panel.dart'])
          if (byHand.hasMatch(File(f).readAsStringSync())) f,
      ],
      isEmpty,
    );
  });

  testWidgets('a day and a time: Nov 25, 3:05 PM', (t) async {
    late String text;
    await t.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            text = shortDateTime(context, afternoon);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(text.replaceAll('\u202f', ' '), 'Nov 25, 3:05 PM');
  });

  test('Administration builds no dates by hand, and no bare empty lines', () {
    final admin = [
      File('lib/screens/admin_screen.dart'),
      ...Directory('lib/screens/admin').listSync().whereType<File>(),
    ];
    final byHand = RegExp(r"\.(month|day|hour|minute)\.toString\(\)\.padLeft");
    final bareEmpty = RegExp(r'Center\(child: Text\(');
    expect(
      [
        for (final f in admin)
          if (byHand.hasMatch(f.readAsStringSync()) ||
              bareEmpty.hasMatch(f.readAsStringSync()))
            f.path,
      ],
      isEmpty,
    );
  });
}
